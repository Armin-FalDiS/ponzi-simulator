class_name SchemeSim
extends RefCounted
## The whole game, as one function: `advance(state, action) -> WeekReport`.
##
## RefCounted on purpose — no scene tree, no signals, no timers. That means the
## model can be unit-tested, fast-forwarded a thousand weeks, or driven by an AI
## without instantiating a single Node. The UI layer is strictly downstream.
##
## The economics, in one paragraph: new deposits are the only real income.
## Promised returns accrue on *principal*, which includes money you already
## skimmed — so every dollar you pocket still generates interest you owe. Growth
## has to outrun the interest, and growth needs appeal, and appeal dies as heat
## rises. That is the whole trap.
##
## Obligations are held as cohorts on a calendar rather than one weekly bill, so
## the schedule is uneven by itself: staggered join weeks produce quiet weeks and
## cliff weeks with no scripting. The exit decision becomes spatial — you run
## just before a cliff.

enum Action {
	NONE,
	FAKE_AUDIT,
	TESTIMONIAL_GALA,
	LOBBY_REGULATOR,
	DELAY_PAYOUT,
	PART_PAY,
}

const ACTION_LABELS: Array[String] = [
	"Lie Low",
	"Fake Audit",
	"Testimonial Gala",
	"Lobby Regulator",
	"Delay Payout",
	"Part-Pay",
]

const ACTION_HINTS: Array[String] = [
	"Do nothing this week.",
	"Buy a clean bill of health. Heat down, trust up — unless they read it.",
	"Wine, dine, and film the happy ones. Trust and hype up.",
	"A very expensive lunch. Heat way down.",
	"Postpone this week's whole bill. It lands next week on top of the next one, and trust craters.",
	"Hand over half of this week's bill. Rest rolls forward. Cheaper on trust than a delay.",
]

var config: SchemeConfig
## Whether to cast people and write posts each week. The balance probe turns it
## off: it measures the economy, and the economy is complete without anybody
## talking about it. The flex loop is *not* part of this — that is money, and it
## runs either way.
var compose_feed: bool = true

var _rng := RandomNumberGenerator.new()
## Second stream, for everything that only decides who speaks and what they say.
## Kept separate so adding a post kind cannot shift the economic dice and quietly
## invalidate the balance baseline.
var _flavour_rng := RandomNumberGenerator.new()
var _cast: CastDirector
var _composer: FeedComposer


func _init(scheme_config: SchemeConfig = null, rng_seed: int = 0) -> void:
	config = scheme_config if scheme_config != null else SchemeConfig.new()
	if rng_seed == 0:
		_rng.randomize()
		_flavour_rng.randomize()
	else:
		_rng.seed = rng_seed
		_flavour_rng.seed = rng_seed * 2654435761


func create_state() -> SchemeState:
	var state := SchemeState.new()
	state.current_terms = SchemeTerms.new()
	state.current_terms.interval_weeks = config.start_interval_weeks
	state.current_terms.set_weekly_rate(config.start_promised_return)
	state.fund = config.start_fund
	state.pocket = 0.0
	state.trust = config.start_trust
	state.heat = config.start_heat
	state.hype = config.start_hype
	# Nobody has been let down yet, so the founders are as loud as they will ever
	# be. It is downhill from here or it is nothing.
	state.flex_reach = 1.0
	state.skim_rate = config.start_skim_rate
	state.marketing = 0.0
	# The people who got you started are a cohort like any other, and they are
	# on the calendar from week zero.
	state.open_cohort(0, state.current_terms, config.start_fund, config.start_investors)
	if compose_feed:
		_director().seed_cast(state)
	state.record_history()
	return state


## Casting and content are built on first use, so a probe that never narrates
## never pays to load the content pool.
func _director() -> CastDirector:
	if _cast == null:
		_cast = CastDirector.new(config, _flavour_rng)
	return _cast


func _writer() -> FeedComposer:
	if _composer == null:
		_composer = FeedComposer.new(config, _flavour_rng)
	return _composer


## Exact amount due in each of the next `weeks` weeks, from the paperwork that
## exists right now. Deterministic and knowable — this is the number the game is
## actually about, so it is allowed on the main view (DESIGN.md §3).
func obligation_forecast(state: SchemeState, weeks: int) -> Array[float]:
	var calendar: Array[float] = []
	for step in range(1, weeks + 1):
		var week := state.week + step
		# Anything you broke a promise on lands the very next week.
		var total := state.deferred_payout if step == 1 else 0.0
		for cohort in state.cohorts:
			if cohort.is_due(week):
				total += cohort.amount_due()
		calendar.append(total)
	return calendar


## Cash price of an action at the current scheme size. Costs scale with
## liabilities so bribes stay relevant when the numbers get silly.
func action_cost(state: SchemeState, action: Action) -> float:
	var owed := state.principal()
	match action:
		Action.FAKE_AUDIT:
			return config.fake_audit_cost + owed * config.fake_audit_cost_scale
		Action.TESTIMONIAL_GALA:
			return config.gala_cost + owed * config.gala_cost_scale
		Action.LOBBY_REGULATOR:
			# Every previous bribe raises the going rate.
			var base := config.lobby_cost + owed * config.lobby_cost_scale
			return base * (1.0 + config.lobby_diminish * float(state.lobby_count))
		_:
			return 0.0


## Heat that cannot be scrubbed off at the current size. A scheme this big is
## simply on somebody's radar, and no amount of lunch changes that.
func heat_floor(state: SchemeState) -> float:
	return minf(config.heat_floor_scale
		* log(1.0 + state.principal() / config.heat_floor_reference), 92.0)


#region Weekly tick

func advance(state: SchemeState, action: Action = Action.NONE) -> WeekReport:
	var report := WeekReport.new()
	if not state.is_running():
		report.snapshot(state)
		return report

	state.week += 1
	state.payout_order = SchemeState.PayoutOrder.FULL
	# Complaint pressure accumulated this week; feeds straight into heat.
	var complaints := 0.0

	# The player moves first, then last week's rumours settle. That order is the
	# entire value of a tell: a bribe bought on Monday is already paid for by the
	# time Tuesday's byline lands.
	_resolve_action(state, action, report)
	_resolve_signals(state, report)
	_resolve_marketing(state, report)
	_resolve_recruitment(state, report)

	var missed_before := state.missed_payouts
	complaints += _resolve_payouts(state, report)

	# A week that already failed its payouts doesn't also run a withdrawal queue —
	# everyone is standing at the payout window instead. This is what separates
	# the two collapse modes: miss enough payouts in a row and you DEFAULT; get
	# hit by a queue you can't cover on a solvent week and it's a BANK RUN.
	if state.missed_payouts > missed_before:
		report.add_ledger_line("The withdrawal desk never opened. The queue was already inside.",
			WeekReport.Tone.BAD)
	else:
		complaints += _resolve_withdrawals(state, report)
	_resolve_pressure(state, report, complaints)
	_roll_events(state, report)
	# Fold this week's signings into the calendar only now that payouts are done,
	# so a cohort born today cannot inherit a due date that already passed.
	state.consolidate()
	_check_outcome(state, report)
	# After the outcome, and last before the feed is written. A scheme that died
	# this week does not gossip about next week — and `_plan` replaces the whole
	# feed with collapse posts on an ending week, so a tell raised here would be
	# a promise of a warning the player never actually receives.
	_raise_signals(state, report)

	state.record_history()
	report.snapshot(state)
	report.forecast = obligation_forecast(state, config.forecast_weeks)
	_narrate(state, report)
	return report


## The week, as the crowd saw it. Runs last and reads only the finished report,
## so nothing here can change an outcome — the feed reports the world, it does
## not vote on it.
func _narrate(state: SchemeState, report: WeekReport) -> void:
	if not compose_feed:
		return
	_director().update(state, report)
	report.posts = _writer().compose(state, report)


func _resolve_action(state: SchemeState, action: Action, report: WeekReport) -> void:
	if action == Action.NONE:
		return

	# Breaking a payout costs no cash, so it never hits the affordability check.
	# The bill for it is trust, and it is charged in `_resolve_payouts` — where
	# we know whether anything was actually due to break.
	match action:
		Action.DELAY_PAYOUT:
			state.payout_order = SchemeState.PayoutOrder.DELAY
			return
		Action.PART_PAY:
			state.payout_order = SchemeState.PayoutOrder.PART
			return
		_:
			pass

	var cost := action_cost(state, action)
	if cost > state.fund:
		report.add_ledger_line("Couldn't afford %s (%s). Skipped." % [
			ACTION_LABELS[int(action)], Fmt.money(cost)], WeekReport.Tone.BAD)
		return

	state.fund -= cost
	if cost > 0.0:
		report.add_ledger_line("Paid %s for %s." % [Fmt.money(cost), ACTION_LABELS[int(action)]],
			WeekReport.Tone.MONEY_OUT)

	match action:
		Action.FAKE_AUDIT:
			# The higher the heat, the more likely somebody actually reads it.
			if state.heat > 65.0 and _rng.randf() < 0.30:
				state.heat = minf(state.heat + 14.0, 100.0)
				state.trust -= 6.0
				report.mark(WeekReport.Beat.AUDIT_BACKFIRED)
				report.add_ledger_line("The auditor asked for the wrong ledger. Now they're curious.",
					WeekReport.Tone.BAD)
			else:
				state.heat = _cool(state, 22.0, report)
				state.trust += 8.0
				report.mark(WeekReport.Beat.AUDIT_CLEAN)
				report.add_ledger_line("Audit came back spotless. Framed it in the lobby.",
					WeekReport.Tone.GOOD)
		Action.TESTIMONIAL_GALA:
			state.trust += 14.0
			state.hype = minf(state.hype + 22.0, 100.0)
			report.mark(WeekReport.Beat.GALA)
			report.add_ledger_line("Gala went well. Three people cried on camera.",
				WeekReport.Tone.GOOD)
		Action.LOBBY_REGULATOR:
			# Each bribe buys less cooling than the one before it.
			var effect := 34.0 / (1.0 + config.lobby_diminish * float(state.lobby_count))
			state.lobby_count += 1
			state.heat = _cool(state, effect, report)
			report.mark(WeekReport.Beat.LOBBY)
			report.add_ledger_line("Regulator's inbox is now somebody else's problem.",
				WeekReport.Tone.GOOD)
		_:
			pass


func _resolve_marketing(state: SchemeState, report: WeekReport) -> void:
	var spend := clampf(state.marketing, 0.0, maxf(state.fund, 0.0))
	state.fund -= spend
	report.marketing += spend

	var gained := spend / 1000.0 * config.hype_per_1k_marketing
	state.hype = clampf(state.hype * (1.0 - config.hype_decay) + gained, 0.0, 100.0)
	if spend > 0.0:
		report.add_ledger_line("Spent %s on \"education webinars\"." % Fmt.money(spend),
			WeekReport.Tone.MONEY_OUT)


## How attractive the scheme looks to a stranger this week. Marks compare offers
## on weekly-equivalent yield and on how soon they see money — never on the
## headline per-payout rate, which is why the interval is a real decision.
##
## The `flex_reach` term is last week's payouts talking. It is the only appeal
## input the player controls by *spending* rather than promising, and the only
## one that collapses within a fortnight of a broken cheque.
func _appeal(state: SchemeState) -> float:
	var terms := state.current_terms
	var greed := clampf(terms.weekly_rate() / config.reference_return,
		0.0, config.appeal_greed_ceiling)
	var appeal := config.appeal_base \
		+ config.appeal_from_return * greed \
		- config.appeal_from_impatience * (1.0 - 1.0 / float(terms.interval_weeks)) \
		+ config.appeal_from_hype * (state.hype / 100.0) \
		+ config.appeal_from_trust * (state.trust / 100.0) \
		+ config.appeal_from_flex * state.flex_reach \
		- config.appeal_from_heat * (state.heat / 100.0)
	return maxf(appeal, 0.0)


func _resolve_recruitment(state: SchemeState, report: WeekReport) -> void:
	var pool := config.walk_in_investors + float(state.investors()) * config.referral_rate
	var recruits := _round_stochastic(pool * _appeal(state) * report.recruitment_surge
		* _rng.randf_range(0.75, 1.25))
	if recruits <= 0:
		report.mark(WeekReport.Beat.NO_RECRUITS)
		report.add_ledger_line("Nobody signed up. The room has gone quiet.", WeekReport.Tone.BAD)
		return

	var deposits := 0.0
	for _i in recruits:
		var lo := 1.0 - config.deposit_variance
		var hi := 1.0 + config.deposit_variance
		deposits += config.avg_deposit * _rng.randf_range(lo, hi)

	var skimmed := deposits * state.skim_rate
	state.pocket += skimmed
	state.fund += deposits - skimmed
	# You owe the full deposit back regardless of what you skimmed off it, and
	# you owe it on today's terms for as long as the scheme lasts.
	state.open_cohort(state.week, state.current_terms, deposits, recruits)

	report.recruits = recruits
	report.deposits = deposits
	report.skimmed = skimmed
	report.add_ledger_line("%d new investors deposited %s on %s terms." % [
		recruits, Fmt.money(deposits), state.current_terms.interval_label().to_lower()],
		WeekReport.Tone.MONEY_IN)
	if skimmed > 0.0:
		report.add_ledger_line("Moved %s into your own account." % Fmt.money(skimmed),
			WeekReport.Tone.GOOD)


## Settles every cohort whose interval boundary lands this week, plus anything
## carried over from a broken promise. Returns the complaint pressure generated.
##
## This is the spine: what is due is a fact of the calendar, decided weeks ago by
## who signed when and on what terms. Nothing the player does this week changes
## the number — only whether it gets paid.
func _resolve_payouts(state: SchemeState, report: WeekReport) -> float:
	var due_cohorts: Array[InvestorCohort] = []
	var due_amounts: Array[float] = []
	var scheduled := 0.0
	# Due-weighted average interval, so trust rewards a quarterly cheque the same
	# as thirteen weekly ones.
	var interval_weight := 0.0

	for cohort in state.cohorts:
		if not cohort.is_due(state.week):
			continue
		var amount := cohort.amount_due()
		if amount <= 0.0:
			continue
		due_cohorts.append(cohort)
		due_amounts.append(amount)
		scheduled += amount
		interval_weight += amount * float(cohort.interval_weeks)

	var carried := state.deferred_payout
	var due := scheduled + carried
	state.deferred_payout = 0.0
	report.payout_due = due
	report.payout_carried = carried
	report.payout_cohorts = due_cohorts.size()
	if due <= 0.0:
		# Nothing was owed, so nobody was let down and nobody was delighted. The
		# showing-off from earlier weeks fades a little.
		state.flex_reach = clampf(state.flex_reach * (1.0 - config.flex_idle_decay), 0.0, 1.0)
		return 0.0

	# Happy investors leave part of their "returns" in the scheme. Cheap this
	# week, but it compounds what you owe. Money you already stiffed someone on
	# is not eligible — they want the cash this time.
	var reinvest_share := clampf(state.trust / 100.0, 0.0, 1.0) * config.reinvest_ceiling
	var reinvested := scheduled * reinvest_share
	var cash_due := due - reinvested

	# Reinvested returns fold back into the cohort that earned them, so the next
	# cliff on that schedule is bigger than the last one.
	if reinvested > 0.0:
		for i in due_cohorts.size():
			due_cohorts[i].principal += reinvested * (due_amounts[i] / scheduled)

	var intended := cash_due
	match state.payout_order:
		SchemeState.PayoutOrder.DELAY:
			intended = 0.0
		SchemeState.PayoutOrder.PART:
			intended = cash_due * config.part_pay_share
		_:
			pass

	var paid := minf(intended, maxf(state.fund, 0.0))
	state.fund -= paid
	report.reinvested = reinvested
	report.payout_paid = paid

	if reinvested > 0.0:
		report.add_ledger_line("%s of \"returns\" reinvested — you now owe that too." % Fmt.money(reinvested),
			WeekReport.Tone.NEUTRAL)
	if carried > 0.0:
		report.add_ledger_line("Last week's %s came due on top of this week's bill." % Fmt.money(carried),
			WeekReport.Tone.BAD)
	report.add_ledger_line("Paid %s of %s owed to %d cohort%s." % [
		Fmt.money(paid), Fmt.money(cash_due), due_cohorts.size(),
		"" if due_cohorts.size() == 1 else "s"], WeekReport.Tone.MONEY_OUT)

	var serviced := interval_weight / maxf(scheduled, 1.0)
	_settle_flex(state, paid / maxf(cash_due, 1.0), serviced)

	var shortfall := cash_due - paid
	if shortfall > 0.5:
		# Whatever you did not hand over is still owed, and it lands next week on
		# top of whatever the calendar already had waiting.
		state.deferred_payout += shortfall
		state.missed_payouts += 1
		report.payout_deferred = shortfall
		return _charge_broken_promise(state, report, shortfall)

	report.mark(WeekReport.Beat.PAYOUT_FULL)
	state.trust += config.trust_on_time_bonus * serviced
	return 0.0


## Pillar 3, as one line of arithmetic: **paying out is your marketing.** People
## who got their money post about the things they bought with it, their followers
## read those posts, and those readers are next week's deposits — recruitment
## runs before payouts, so this week's cheques can only ever buy next week's
## crowd.
##
## `serviced` is the due-weighted average interval, so settling one quarterly
## cohort buys the same reach as settling thirteen weekly ones. Without that,
## long terms would be punished once by impatience and again by silence.
func _settle_flex(state: SchemeState, paid_share: float, serviced: float) -> void:
	var share := clampf(paid_share, 0.0, 1.0)
	state.flex_reach = clampf(
		state.flex_reach * (1.0 - config.flex_collapse * (1.0 - share))
		+ config.flex_recover * serviced * share, 0.0, 1.0)


## Trust and complaint cost of not settling the bill in full. Announcing it is
## worse than being quietly caught short: people forgive an accident faster than
## a decision.
func _charge_broken_promise(state: SchemeState, report: WeekReport, shortfall: float) -> float:
	match state.payout_order:
		SchemeState.PayoutOrder.DELAY:
			state.trust -= config.trust_delay_penalty
			report.mark(WeekReport.Beat.PAYOUT_DELAYED)
			report.add_ledger_line("You announced a \"processing delay\". %s is now next week's problem."
				% Fmt.money(shortfall), WeekReport.Tone.CRITICAL)
			return 3.0
		SchemeState.PayoutOrder.PART:
			state.trust -= config.trust_part_pay_penalty
			report.mark(WeekReport.Beat.PAYOUT_PART)
			report.add_ledger_line("Everyone got a partial cheque and an apology. %s rolls forward."
				% Fmt.money(shortfall), WeekReport.Tone.BAD)
			return 1.5
		_:
			state.trust -= config.trust_missed_penalty
			report.mark(WeekReport.Beat.PAYOUT_SHORT)
			report.add_ledger_line("PAYOUT SHORTFALL of %s. Phones are ringing." % Fmt.money(shortfall),
				WeekReport.Tone.CRITICAL)
			return 2.0


## Returns the complaint pressure generated by the withdrawal round.
func _resolve_withdrawals(state: SchemeState, report: WeekReport) -> float:
	var head_count := state.investors()
	var rate := (config.withdraw_base \
		+ (1.0 - clampf(state.trust, 0.0, 100.0) / 100.0) * config.withdraw_from_distrust \
		+ float(state.missed_payouts) * config.withdraw_per_missed_payout) \
		* report.withdrawal_surge
	var leavers := mini(_round_stochastic(float(head_count) * rate), head_count)
	if leavers <= 0:
		return 0.0

	var stake := state.avg_stake()
	var demand := leavers * stake
	report.withdrawers = leavers

	if demand <= state.fund:
		state.fund -= demand
		state.take_from_cohorts(demand, leavers)
		report.withdrawn = demand
		report.add_ledger_line("%d investors cashed out %s." % [leavers, Fmt.money(demand)],
			WeekReport.Tone.MONEY_OUT)
		return 0.0

	# Short of the queue. Pay who you can and hope the rest wait a week.
	var paid := maxf(state.fund, 0.0)
	var covered := paid / demand
	var served := int(floorf(covered * float(leavers)))
	state.fund = 0.0
	state.take_from_cohorts(paid, served)
	report.withdrawn = paid
	report.withdrawers = served
	report.add_ledger_line("%d investors demanded %s. You had %s." % [
		leavers, Fmt.money(demand), Fmt.money(paid)], WeekReport.Tone.CRITICAL)

	if covered < config.bank_run_threshold:
		state.outcome = SchemeState.Outcome.BANK_RUN
		return 4.0

	# Survived the week, but everyone in that queue told somebody.
	state.missed_payouts += 1
	state.trust = maxf(state.trust - config.trust_missed_penalty, 0.0)
	report.mark(WeekReport.Beat.QUEUE_UNSERVED)
	report.add_ledger_line("The rest were told to come back next week. They will.",
		WeekReport.Tone.CRITICAL)
	return 3.0


func _resolve_pressure(state: SchemeState, report: WeekReport, complaints: float) -> void:
	var before := state.heat
	var weekly_rate := state.current_terms.weekly_rate()
	state.heat = clampf(state.heat
		+ config.heat_base
		+ config.heat_from_size * log(1.0 + state.principal() / 50000.0)
		+ config.heat_from_promise * maxf(weekly_rate - 0.04, 0.0)
		+ config.heat_per_complaint * complaints
		- config.heat_decay, 0.0, 100.0)
	state.heat = maxf(state.heat, heat_floor(state))
	if state.heat > 60.0 and before <= 60.0:
		report.add_ledger_line("You are now, formally, a person of interest.", WeekReport.Tone.BAD)

	# Promising the impossible erodes trust on its own, and so does bad press.
	state.trust = clampf(state.trust
		- config.trust_skepticism * weekly_rate
		- config.trust_from_heat * state.heat, 0.0, 100.0)


## The events that still arrive without warning. Each one is either a windfall or
## a scratch — nothing here can end a run on its own, which is the line between
## this function and the signal system below. A journalist used to be rolled here
## too; it moved out precisely because it *could*.
func _roll_events(state: SchemeState, report: WeekReport) -> void:
	if state.trust > 60.0 and _rng.randf() < 0.10:
		var whale := config.avg_deposit * _rng.randf_range(4.0, 8.0)
		var cut := whale * state.skim_rate
		state.pocket += cut
		state.fund += whale - cut
		state.open_cohort(state.week, state.current_terms, whale, 1)
		report.deposits += whale
		report.skimmed += cut
		report.recruits += 1
		report.whale_deposit = whale
		report.mark(WeekReport.Beat.WHALE)
		report.add_ledger_line("A whale wired %s after hearing about you at a wedding." % Fmt.money(whale),
			WeekReport.Tone.MONEY_IN)

	if state.solvency() < 0.40 and _rng.randf() < 0.15:
		state.trust = maxf(state.trust - 10.0, 0.0)
		report.mark(WeekReport.Beat.FORUM_SPREADSHEET)
		report.add_ledger_line("Someone posted a spreadsheet on a forum. It is accurate.",
			WeekReport.Tone.BAD)

	if state.week > 8 and _rng.randf() < 0.06:
		state.trust = maxf(state.trust - 8.0, 0.0)
		state.heat = minf(state.heat + 4.0, 100.0)
		report.mark(WeekReport.Beat.RIVAL_COLLAPSE)
		report.add_ledger_line("A rival scheme collapsed. Everyone is looking at yours now.",
			WeekReport.Tone.BAD)


#region Tells and signals

## Settles every coin flip that was announced last week, before any system it
## could bend has run. Nothing else in the sim may consult `pending_signals` —
## a landed signal speaks only through the two surge multipliers and its beat.
##
## Pillar 5 is enforced here by omission: the roll uses `pending.odds()`, the
## exact number the wording promised, and nothing about the current state. A tell
## that said 50% is 50% even if the week since has gone beautifully, because a
## band that quietly re-prices itself is a band the player cannot learn.
func _resolve_signals(state: SchemeState, report: WeekReport) -> void:
	if state.pending_signals.is_empty():
		return

	var carried: Array[PendingSignal] = []
	for pending in state.pending_signals:
		if pending.resolve_week > state.week:
			carried.append(pending)
			continue
		if _rng.randf() >= pending.odds():
			# It came to nothing. Worth saying so: a player who paid to dodge a
			# 50% and watched it miss has to see that they read it right.
			report.mark(WeekReport.Beat.SIGNAL_FIZZLED)
			report.add_ledger_line("The talk about %s came to nothing." % pending.kind_label(),
				WeekReport.Tone.GOOD)
			continue
		_land_signal(state, report, pending)
	state.pending_signals = carried


func _land_signal(state: SchemeState, report: WeekReport, pending: PendingSignal) -> void:
	match pending.kind:
		PendingSignal.Kind.WITHDRAWAL_WAVE:
			report.withdrawal_surge = config.wave_multiplier
			report.mark(WeekReport.Beat.WAVE_LANDED)
			report.add_ledger_line("The withdrawal desk is three deep. They all read the same post.",
				WeekReport.Tone.CRITICAL)
		PendingSignal.Kind.WORD_OF_MOUTH:
			report.recruitment_surge = config.buzz_multiplier
			report.mark(WeekReport.Beat.BUZZ_LANDED)
			report.add_ledger_line("The thing everyone was sharing did the rounds properly.",
				WeekReport.Tone.GOOD)
		PendingSignal.Kind.JOURNALIST:
			state.heat = minf(state.heat + config.journalist_heat, 100.0)
			state.hype = minf(state.hype + config.journalist_hype, 100.0)
			report.mark(WeekReport.Beat.PRESS_CALL)
			report.add_ledger_line("A journalist called for comment. Bad press is still press.",
				WeekReport.Tone.BAD)
		_:
			pass


## Reads the pressure on each of the three telegraphed events and, where it is
## loud enough to be worth mentioning, announces it. One signal per kind at a
## time — a second rumour about the same thing is the same rumour, and stacking
## them would let a run be ambushed by a queue of coin flips it was only warned
## about once.
func _raise_signals(state: SchemeState, report: WeekReport) -> void:
	if not state.is_running():
		return
	_raise(state, report, PendingSignal.Kind.WITHDRAWAL_WAVE, _wave_pressure(state))
	_raise(state, report, PendingSignal.Kind.WORD_OF_MOUTH, _buzz_pressure(state))
	_raise(state, report, PendingSignal.Kind.JOURNALIST, _byline_pressure(state))


func _raise(state: SchemeState, report: WeekReport, kind: PendingSignal.Kind,
		pressure: float) -> void:
	if state.signal_for(kind) != null:
		return
	var band := PendingSignal.band_for(pressure + _rng.randf_range(
		-config.pressure_noise, config.pressure_noise))
	if band < 0:
		return
	var pending := PendingSignal.make(kind, band as PendingSignal.Band, state.week)
	state.pending_signals.append(pending)
	report.signals_raised.append(pending)


## People leave when they have stopped believing, when they have already been
## stiffed once, and when the arithmetic has started circulating. All three are
## things the crowd can see, which is why the crowd is the one that announces it.
func _wave_pressure(state: SchemeState) -> float:
	return (1.0 - clampf(state.trust, 0.0, 100.0) / 100.0) * config.wave_from_distrust \
		+ float(state.missed_payouts) * config.wave_per_missed_payout \
		+ maxf(0.75 - state.solvency(), 0.0) * config.wave_from_insolvency


## The mirror image, and the reason the tell system is not purely a warning
## siren: the same mechanism that tells you to run also tells you to stay one
## more week. A tell you are always happy to see teaches nothing.
## Trust carries most of this and is raised to a power, because enthusiasm is not
## linear: people who are merely satisfied do not tell anybody. Hype is only a
## trim — it pins at 100 under any real marketing spend, so leaning on it would
## be leaning on a constant.
func _buzz_pressure(state: SchemeState) -> float:
	var reach := config.buzz_flex_floor \
		+ (1.0 - config.buzz_flex_floor) * clampf(state.flex_reach, 0.0, 1.0)
	var belief := pow(clampf(state.trust, 0.0, 100.0) / 100.0, config.buzz_trust_curve)
	var loudness := 0.6 + 0.4 * (state.hype / 100.0)
	return belief * reach * loudness * config.buzz_scale


## Squared on purpose — see `SchemeConfig.byline_from_heat`. A scheme at 90 heat
## has to be told, loudly, that the story is about to run.
func _byline_pressure(state: SchemeState) -> float:
	var normalised := clampf(state.heat, 0.0, 100.0) / 100.0
	return normalised * normalised * config.byline_from_heat

#endregion


func _check_outcome(state: SchemeState, report: WeekReport) -> void:
	if not state.is_running():
		_settle(state, report)
		return

	if state.heat >= 100.0:
		state.outcome = SchemeState.Outcome.BUSTED
		report.add_ledger_line("Two people with badges are in reception.", WeekReport.Tone.CRITICAL)
	elif state.missed_payouts > config.missed_payouts_allowed:
		state.outcome = SchemeState.Outcome.DEFAULTED
		report.add_ledger_line("Word got out that the cheques bounced. It's over.",
			WeekReport.Tone.CRITICAL)

	if not state.is_running():
		_settle(state, report)


## Player-initiated ending. Take what you can carry and disappear.
func exit_scam(state: SchemeState) -> WeekReport:
	var report := WeekReport.new()
	if not state.is_running():
		report.snapshot(state)
		return report

	state.outcome = SchemeState.Outcome.EXIT_SCAM
	report.week = state.week
	report.add_ledger_line("You emptied the fund and boarded a flight.", WeekReport.Tone.GOOD)
	_settle(state, report)
	report.snapshot(state)
	report.forecast = obligation_forecast(state, config.forecast_weeks)
	_narrate(state, report)
	return report


## Works out what the player actually walks away with. This is the whole reason
## to quit early: heat makes money hard to move, and getting caught makes it
## impossible.
func _settle(state: SchemeState, report: WeekReport) -> void:
	match state.outcome:
		SchemeState.Outcome.EXIT_SCAM:
			# You also grab whatever cash was still in the fund.
			var grabbed := maxf(state.fund, 0.0)
			state.pocket += grabbed
			state.fund = 0.0
			var kept := 1.0 - (state.heat / 100.0) * config.exit_heat_penalty
			state.take_home = state.pocket * clampf(kept, 0.0, 1.0)
			report.add_ledger_line("Swept %s out of the fund on the way." % Fmt.money(grabbed),
				WeekReport.Tone.MONEY_IN)
			report.add_ledger_line("Laundering at %d%% heat cost you %s." % [
				int(state.heat), Fmt.money(state.pocket - state.take_home)],
				WeekReport.Tone.MONEY_OUT)
		SchemeState.Outcome.BUSTED:
			state.take_home = 0.0
			report.add_ledger_line("Assets frozen. You keep nothing.", WeekReport.Tone.CRITICAL)
		SchemeState.Outcome.BANK_RUN, SchemeState.Outcome.DEFAULTED:
			state.take_home = state.pocket * config.collapse_pocket_keep
			report.add_ledger_line("You got out with %s of the %s you'd set aside." % [
				Fmt.money(state.take_home), Fmt.money(state.pocket)], WeekReport.Tone.BAD)
		_:
			state.take_home = 0.0

#endregion


## Applies a heat reduction, but never below the floor the scheme's own size
## sets. Reports when the floor is what's stopping you.
func _cool(state: SchemeState, amount: float, report: WeekReport) -> float:
	var floor_value := heat_floor(state)
	var cooled := maxf(state.heat - amount, 0.0)
	if cooled < floor_value and state.heat > floor_value:
		report.add_ledger_line("Only got them down to %d%% — you're too big to be invisible now."
			% int(floor_value), WeekReport.Tone.BAD)
	return maxf(cooled, minf(floor_value, state.heat))


## Rounds fractionally: 0.3 investors means a 30% chance of one investor. Keeps
## small schemes from being frozen by integer truncation.
func _round_stochastic(value: float) -> int:
	if value <= 0.0:
		return 0
	var whole := floorf(value)
	var chance := value - whole
	return int(whole) + (1 if _rng.randf() < chance else 0)
