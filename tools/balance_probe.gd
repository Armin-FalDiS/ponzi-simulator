extends SceneTree
## Headless balance probe. Because `SchemeSim` is a plain RefCounted with no
## scene-tree dependencies, thousands of runs can be simulated in a second.
##
##     godot --headless --script res://tools/balance_probe.gd
##
## Prints, per strategy, how long the scheme survives and how much the player
## walks away with. Use it to sanity-check `default_scheme.tres` after tuning.

const RUNS := 400
const MAX_WEEKS := 400


## The interval the sweep runs at, so its rows stay comparable to the baseline
## table in docs/PLAN.md.
const BASE_INTERVAL := 1

#region Tell-reading trial

const READ_IGNORE := 0
const READ_TELLS := 1
const READ_NOISE := 2
const READ_LABELS: Array[String] = ["ignores tells", "reads tells", "reacts blind"]

const TELL_RUNS := 240
## Greedy enough that the run is genuinely at risk, so a saved collapse is worth
## something. At a promise nobody can lose at, reading well pays nothing.
const TELL_PROMISED := 0.09
const TELL_EXIT := 40
## Solvency under which a signalled wave is judged unsurvivable. A knowable
## number: it is cash over what you owe, and both are on the paperwork.
const TELL_EXIT_SOLVENCY := 0.30

#endregion


func _initialize() -> void:
	var config: SchemeConfig = load("res://resources/default_scheme.tres")
	print("strategy                  survives   take-home    peak owed    ends")
	print("".lpad(74, "-"))
	_probe("patient (4%, skim 10%)", config, 0.04, 1, 0.10, 2000.0, 0)
	_probe("greedy (9%, skim 30%)", config, 0.09, 1, 0.30, 4000.0, 0)
	_probe("reckless (15%, skim 50%)", config, 0.15, 1, 0.50, 8000.0, 0)
	_probe("patient, exit at wk 30", config, 0.04, 1, 0.10, 2000.0, 30)
	_probe("greedy, exit at wk 30", config, 0.09, 1, 0.30, 4000.0, 30)
	# Delaying a payout buys a week of cash but stacks missed payouts, which is
	# the only route to the DEFAULTED ending. Confirms it isn't dead code.
	_probe("delays when short (9%)", config, 0.09, 1, 0.30, 4000.0, 0, true)
	print("")
	_sweep(config)
	print("")
	_interval_sweep(config)
	print("")
	_flex_probe(config)
	print("")
	_signal_census(config)
	print("")
	_tell_probe(config)
	quit()


## How often each telegraphed event is announced and how often it then lands, per
## 100 simulated weeks. Not an acceptance test — a tuning instrument. A signal
## that fires most weeks has stopped being an event and become a rate, which is
## how the first pass at this phase quietly turned into a permanent recruitment
## multiplier.
func _signal_census(config: SchemeConfig) -> void:
	var weeks := 0
	var raised: Array[int] = [0, 0, 0]
	var landed: Array[int] = [0, 0, 0]
	# Bands seen per kind, flattened as kind * 3 + band. Every one of the nine
	# cells must be non-zero: a cell that never fires is a `.tres` of vocabulary
	# the player will never read, and a band they can therefore never learn.
	var bands: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0]

	# Sampled across the same promised returns as the main sweep, not one slice of
	# it. Trust climbs at 4%/wk and bleeds at 12%, so a census taken at a single
	# rate reports a band as unreachable when it is merely unreachable *there* —
	# which is exactly how the loud word-of-mouth wording first looked dead.
	for run in 200:
		var promised: float = [0.04, 0.06, 0.09, 0.12][run % 4]
		var sim := SchemeSim.new(_terms_config(config, promised, BASE_INTERVAL), run + 1)
		sim.compose_feed = false
		var state := sim.create_state()
		state.skim_rate = 0.25
		state.marketing = 3000.0
		while state.is_running() and state.week < 40:
			var report := sim.advance(state, _pick_action(sim, state))
			weeks += 1
			for pending in report.signals_raised:
				raised[int(pending.kind)] += 1
				bands[int(pending.kind) * 3 + int(pending.band)] += 1
			if report.has_beat(WeekReport.Beat.WAVE_LANDED):
				landed[0] += 1
			if report.has_beat(WeekReport.Beat.BUZZ_LANDED):
				landed[1] += 1
			if report.has_beat(WeekReport.Beat.PRESS_CALL):
				landed[2] += 1

	var scale := 100.0 / maxf(float(weeks), 1.0)
	print("signals            told/100wk   landed/100wk   one person   a few   everyone")
	print("".lpad(74, "-"))
	for kind in 3:
		var told := maxf(float(raised[kind]), 1.0)
		print("%s%s%s%s%s%s" % [
			PendingSignal.KIND_LABELS[kind].rpad(19),
			("%.1f" % (raised[kind] * scale)).lpad(10),
			("%.1f" % (landed[kind] * scale)).lpad(15),
			Fmt.percent(bands[kind * 3] / told, 0).lpad(13),
			Fmt.percent(bands[kind * 3 + 1] / told, 0).lpad(8),
			Fmt.percent(bands[kind * 3 + 2] / told, 0).lpad(11),
		])


## Pillar 3, measured: **paying out is your marketing.** Two identical schemes,
## one settling every bill and one delaying from week 8, compared on recruitment
## rather than on survival — a delay wrecks trust too, so the third column
## isolates the flex loop by zeroing `appeal_from_flex` and re-running the same
## seeds. If columns two and three move together, the loop is decoration.
func _flex_probe(config: SchemeConfig) -> void:
	var muted: SchemeConfig = config.duplicate()
	muted.appeal_from_flex = 0.0
	print("flex loop            recruits by wk 20      flex reach at wk 20")
	print("".lpad(74, "-"))
	for delay_from in [0, 8]:
		var label := "pays in full" if delay_from == 0 else "delays from wk 8"
		var live := _recruit_trial(config, delay_from)
		var off := _recruit_trial(muted, delay_from)
		print("%s%s live  %s no-flex   %s" % [
			label.rpad(20),
			Fmt.grouped(int(live.x)).lpad(7),
			Fmt.grouped(int(off.x)).lpad(7),
			("%.2f" % live.y).lpad(10),
		])


## Median recruits accumulated to week 20, and median flex reach there. Returns
## them as one vector so the two policies stay on one line.
func _recruit_trial(config: SchemeConfig, delay_from: int) -> Vector2:
	var totals: Array[float] = []
	var reaches: Array[float] = []
	for run in 160:
		var sim := SchemeSim.new(_terms_config(config, 0.06, BASE_INTERVAL), run + 1)
		sim.compose_feed = false
		var state := sim.create_state()
		state.skim_rate = 0.25
		state.marketing = 3000.0
		var joined := 0
		while state.is_running() and state.week < 20:
			var action := SchemeSim.Action.NONE
			if delay_from > 0 and state.week >= delay_from:
				action = SchemeSim.Action.DELAY_PAYOUT
			joined += sim.advance(state, action).recruits
		totals.append(float(joined))
		reaches.append(state.flex_reach)
	return Vector2(_median(totals), _median(reaches))


## Phase 3's acceptance test: **does reading the feed pay?**
##
## Three policies with identical plans, identical seeds, and identical spending
## except for what they do about a tell.
##
##   * `ignores tells` — never looks. The control for "is the game harder now".
##   * `reads tells`   — reacts to the pending signals it can actually see.
##   * `reacts blind`  — makes the *same* reactions at the same rate, on random
##                       weeks. The control that matters: it isolates the
##                       information from the behaviour. If it scores like the
##                       reader, then holding cash and bribing early are simply
##                       good habits and the tells taught nothing.
##
## The reader must beat both by a clear margin. If it does not, the vocabulary is
## noise and the mechanic has failed (PLAN.md, Phase 3).
func _tell_probe(config: SchemeConfig) -> void:
	var quiet: Array[float] = [0.0, 0.0, 0.0]
	# The reader runs first so the blind control can be matched to the rate it
	# actually fired at, per kind. Hand-picked rates drifted out of step every
	# time the pressure formulas moved, and a control that acts half as often as
	# the treatment is not a control.
	var reader := _tell_pass(config, READ_TELLS, quiet)
	var rates: Array[float] = []
	for kind in 3:
		rates.append(float(reader["fires"][kind]) / maxf(float(reader["weeks"]), 1.0))

	print("reading the feed      take-home      exits    collapses   reactions")
	print("".lpad(74, "-"))
	_print_tell_row(READ_IGNORE, _tell_pass(config, READ_IGNORE, quiet))
	_print_tell_row(READ_TELLS, reader)
	_print_tell_row(READ_NOISE, _tell_pass(config, READ_NOISE, rates))


func _tell_pass(config: SchemeConfig, mode: int, rates: Array[float]) -> Dictionary:
	var takes: Array[float] = []
	var fires: Array[int] = [0, 0, 0]
	var exits := 0
	var collapses := 0
	var weeks := 0

	for run in TELL_RUNS:
		var trial := _tell_run(config, mode, rates, run + 1)
		takes.append(trial["take"])
		weeks += int(trial["weeks"])
		for kind in 3:
			fires[kind] += int(trial["fires"][kind])
		if int(trial["outcome"]) == SchemeState.Outcome.EXIT_SCAM:
			exits += 1
		elif int(trial["outcome"]) != SchemeState.Outcome.RUNNING:
			collapses += 1

	return {
		"take": _median(takes),
		"fires": fires,
		"weeks": weeks,
		"exits": exits,
		"collapses": collapses,
	}


func _print_tell_row(mode: int, pass_result: Dictionary) -> void:
	var fires: Array[int] = pass_result["fires"]
	var reactions: int = fires[0] + fires[1] + fires[2]
	print("%s%s%s%s%s" % [
		READ_LABELS[mode].rpad(20),
		Fmt.money(pass_result["take"]).lpad(11),
		Fmt.percent(float(pass_result["exits"]) / TELL_RUNS, 0).lpad(11),
		Fmt.percent(float(pass_result["collapses"]) / TELL_RUNS, 0).lpad(12),
		("%.1f/run" % (float(reactions) / TELL_RUNS)).lpad(12),
	])


## One run under one reading policy. Everything the reader consults is something
## the game already shows: the pending tells (as wording, i.e. kind and band),
## cash, the next bill, and the back office's solvency and heat. It never reads
## the *size* of a pending event, because the card does not carry one.
func _tell_run(config: SchemeConfig, mode: int, rates: Array[float],
		rng_seed: int) -> Dictionary:
	var sim := SchemeSim.new(_terms_config(config, TELL_PROMISED, BASE_INTERVAL), rng_seed)
	sim.compose_feed = false
	var state := sim.create_state()
	state.skim_rate = 0.25
	# Second stream so the policy's own coin flips cannot shift the economy's.
	var noise := RandomNumberGenerator.new()
	noise.seed = rng_seed * 7919
	var fires: Array[int] = [0, 0, 0]
	var weeks := 0

	while state.is_running() and state.week < MAX_WEEKS:
		weeks += 1
		if state.week >= TELL_EXIT:
			sim.exit_scam(state)
			break

		# What this policy believes is coming, as odds. Zero means "no warning".
		var wave := 0.0
		var buzz := 0.0
		var byline := 0.0
		match mode:
			READ_TELLS:
				for pending in state.pending_signals:
					match pending.kind:
						PendingSignal.Kind.WITHDRAWAL_WAVE:
							wave = pending.odds()
						PendingSignal.Kind.WORD_OF_MOUTH:
							buzz = pending.odds()
						PendingSignal.Kind.JOURNALIST:
							byline = pending.odds()
						_:
							pass
			READ_NOISE:
				# Same reactions, same per-kind frequency as the reader actually
				# managed, and no information whatsoever about when.
				wave = 0.8 if noise.randf() < rates[0] else 0.0
				buzz = 0.8 if noise.randf() < rates[1] else 0.0
				byline = 0.8 if noise.randf() < rates[2] else 0.0
			_:
				pass

		state.marketing = 3000.0
		var action := _pick_action(sim, state)

		if buzz >= 0.5:
			# Marketing resolves before recruitment, so buying hype into a spike
			# you were warned about compounds with it.
			state.marketing = 7000.0
			fires[1] += 1
		if byline >= 0.5:
			fires[2] += 1
			if state.heat + config.journalist_heat >= 95.0:
				sim.exit_scam(state)
				break
			if sim.action_cost(state, SchemeSim.Action.LOBBY_REGULATOR) < state.fund:
				action = SchemeSim.Action.LOBBY_REGULATOR
		if wave >= 0.5:
			fires[0] += 1
			# Reserves are the only defence against a queue, so stop spending and
			# stop buying favours for one week.
			state.marketing = 0.0
			action = SchemeSim.Action.NONE
			# Too thin to survive one, so take the money and go rather than lose
			# 65% of it to a collapse.
			if state.solvency() < TELL_EXIT_SOLVENCY:
				sim.exit_scam(state)
				break

		sim.advance(state, action)

	return {
		"take": state.take_home,
		"outcome": int(state.outcome),
		"fires": fires,
		"weeks": weeks,
	}


## Median take-home across promised return × planned exit week. A healthy curve
## has an interior peak: leaving too early is cheap, leaving too late is fatal.
func _sweep(config: SchemeConfig) -> void:
	var returns: Array[float] = [0.04, 0.06, 0.09, 0.12, 0.15]
	var exits: Array[int] = [10, 20, 30, 40, 50, 0]
	var header := "take-home  "
	for exit_week in exits:
		header += ("never" if exit_week == 0 else "wk%d" % exit_week).lpad(10)
	print(header)
	print("".lpad(74, "-"))

	for promised in returns:
		var row := ("%s/wk" % Fmt.percent(promised, 1)).rpad(11)
		for exit_week in exits:
			var takes: Array[float] = []
			for run in 120:
				takes.append(_single_run(config, promised, BASE_INTERVAL, 0.25, 3000.0,
					exit_week, run + 1))
			row += Fmt.money(_median(takes)).lpad(10)
		print(row)


## The payout-interval dial, at a fixed weekly-equivalent promise. No column may
## dominate: float has to be worth roughly what the appeal costs, or the dial is
## decoration.
func _interval_sweep(config: SchemeConfig) -> void:
	var exits: Array[int] = [20, 30, 40, 0]
	var header := "by interval"
	for exit_week in exits:
		header += ("never" if exit_week == 0 else "wk%d" % exit_week).lpad(10)
	print(header)
	print("".lpad(74, "-"))

	for interval in SchemeTerms.INTERVALS:
		var row := ("%d-wk terms" % interval).rpad(11)
		for exit_week in exits:
			var takes: Array[float] = []
			for run in 120:
				takes.append(_single_run(config, 0.06, interval, 0.25, 3000.0,
					exit_week, run + 1))
			row += Fmt.money(_median(takes)).lpad(10)
		print(row)


## Terms are baked into the config copy rather than assigned after the fact, so
## the opening cohort signs the same paperwork as everyone who follows it.
func _terms_config(config: SchemeConfig, promised: float, interval: int) -> SchemeConfig:
	var copy: SchemeConfig = config.duplicate()
	copy.start_promised_return = promised
	copy.start_interval_weeks = interval
	return copy


func _single_run(config: SchemeConfig, promised: float, interval: int, skim: float,
		marketing: float, exit_week: int, rng_seed: int) -> float:
	var sim := SchemeSim.new(_terms_config(config, promised, interval), rng_seed)
	sim.compose_feed = false
	var state := sim.create_state()
	state.skim_rate = skim
	state.marketing = marketing
	while state.is_running() and state.week < MAX_WEEKS:
		if exit_week > 0 and state.week >= exit_week:
			sim.exit_scam(state)
			break
		sim.advance(state, _pick_action(sim, state))
	return state.take_home


## What the coming week's bill will be. The forecast is the sim's own answer, so
## a probe policy reads exactly what a player would.
func _due_now(sim: SchemeSim, state: SchemeState) -> float:
	var calendar := sim.obligation_forecast(state, 1)
	return calendar[0] if not calendar.is_empty() else 0.0


func _pick_action(sim: SchemeSim, state: SchemeState) -> SchemeSim.Action:
	if state.heat > 70.0 and sim.action_cost(state, SchemeSim.Action.LOBBY_REGULATOR) < state.fund:
		return SchemeSim.Action.LOBBY_REGULATOR
	if state.trust < 30.0 and sim.action_cost(state, SchemeSim.Action.TESTIMONIAL_GALA) < state.fund:
		return SchemeSim.Action.TESTIMONIAL_GALA
	return SchemeSim.Action.NONE


func _probe(label: String, config: SchemeConfig, promised: float, interval: int, skim: float,
		marketing: float, exit_week: int, stall: bool = false) -> void:
	var weeks: Array[float] = []
	var takes: Array[float] = []
	var peaks: Array[float] = []
	var endings: Dictionary[int, int] = {}
	var terms_config := _terms_config(config, promised, interval)

	for run in RUNS:
		var sim := SchemeSim.new(terms_config, run + 1)
		sim.compose_feed = false
		var state := sim.create_state()
		state.skim_rate = skim
		state.marketing = marketing

		while state.is_running() and state.week < MAX_WEEKS:
			if exit_week > 0 and state.week >= exit_week:
				sim.exit_scam(state)
				break
			# Buy off the regulator whenever heat is dangerous and it's affordable.
			var action := _pick_action(sim, state)
			if stall and _due_now(sim, state) > state.fund:
				action = SchemeSim.Action.DELAY_PAYOUT
			sim.advance(state, action)

		weeks.append(float(state.week))
		takes.append(state.take_home)
		var peak := 0.0
		for value in state.liability_history:
			peak = maxf(peak, value)
		peaks.append(peak)
		endings[int(state.outcome)] = endings.get(int(state.outcome), 0) + 1

	print("%s%s wks  %s  %s   %s" % [
		label.rpad(26),
		("%d" % int(_median(weeks))).lpad(5),
		Fmt.money(_median(takes)).lpad(10),
		Fmt.money(_median(peaks)).lpad(11),
		_describe(endings),
	])


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _describe(endings: Dictionary[int, int]) -> String:
	var names := {
		SchemeState.Outcome.RUNNING: "still running",
		SchemeState.Outcome.EXIT_SCAM: "exit",
		SchemeState.Outcome.BANK_RUN: "bank run",
		SchemeState.Outcome.DEFAULTED: "default",
		SchemeState.Outcome.BUSTED: "busted",
	}
	var parts: Array[String] = []
	for key in endings:
		parts.append("%d%% %s" % [roundi(100.0 * endings[key] / float(RUNS)), names[key]])
	return ", ".join(parts)
