extends SceneTree
## THROWAWAY scaffolding. Verifies the half of Phase 3 the balance probe cannot
## see: the probe runs with `compose_feed = false`, so it proves the economics of
## a tell and nothing at all about whether the post ever gets written.
##
## Three claims, all of which the mechanic dies without:
##   1. Every raised signal produces a TELL post that same week (the precursor
##      guarantee — DESIGN.md §4.3 forbids an ambush).
##   2. Every TELL post is worded by the set matching that signal's kind *and*
##      band, so "everyone's talking about it" always means 80%.
##   3. Nothing lands that was not told the week before.
##
##     godot --headless --script res://tools/tell_check.gd

const RUNS := 120
const WEEKS := 45


func _initialize() -> void:
	var config: SchemeConfig = load("res://resources/default_scheme.tres")
	var content: FeedContent = load("res://resources/feed/pool.tres")
	var prefixes := _index_tell_bodies(content)

	var told := 0
	var missing_post := 0
	var wrong_band := 0
	var unannounced := 0
	var landed := 0
	var seen_cells: Dictionary[int, int] = {}

	for run in RUNS:
		var promised: float = [0.04, 0.06, 0.09, 0.12][run % 4]
		var copy: SchemeConfig = config.duplicate()
		copy.start_promised_return = promised
		var sim := SchemeSim.new(copy, run + 1)
		var state := sim.create_state()
		state.skim_rate = 0.25
		state.marketing = 3000.0

		var pending_last_week: Array[int] = []
		while state.is_running() and state.week < WEEKS:
			var report := sim.advance(state)

			# --- claim 3: nothing arrives unannounced -------------------------
			for kind in _landed_kinds(report):
				landed += 1
				if not pending_last_week.has(kind):
					unannounced += 1

			# --- claims 1 and 2: a post exists, in the right vocabulary -------
			var tells: Array[FeedPost] = []
			for post in report.posts:
				if post.kind == FeedPost.Kind.TELL:
					tells.append(post)

			for raised in report.signals_raised:
				told += 1
				var cell := int(raised.kind) * 3 + int(raised.band)
				seen_cells[cell] = seen_cells.get(cell, 0) + 1
				var matched := false
				for post in tells:
					var got := _classify(post.body, prefixes)
					if got == cell:
						matched = true
						break
					if got >= 0 and got / 3 == int(raised.kind):
						wrong_band += 1
				if not matched:
					missing_post += 1

			pending_last_week.clear()
			for pending in state.pending_signals:
				pending_last_week.append(int(pending.kind))

	print("tells told                 %d" % told)
	print("signals landed             %d" % landed)
	print("")
	print("no precursor post          %d   (must be 0)" % missing_post)
	print("post in the wrong band     %d   (must be 0)" % wrong_band)
	print("landed unannounced         %d   (must be 0)" % unannounced)
	print("")
	print("vocabulary cells exercised %d of 9" % seen_cells.size())
	for kind in 3:
		var row := ""
		for band in 3:
			row += ("%d" % seen_cells.get(kind * 3 + band, 0)).lpad(9)
		print("  %s%s" % [PendingSignal.KIND_LABELS[kind].rpad(18), row])
	quit()


## Body text up to its first slot, mapped to `kind * 3 + band`. Slots are filled
## before the post reaches the feed, so the stem is what survives to compare.
func _index_tell_bodies(content: FeedContent) -> Dictionary[String, int]:
	var prefixes: Dictionary[String, int] = {}
	for template in content.sets:
		if template == null or template.kind != FeedPost.Kind.TELL:
			continue
		var cell := int(template.signal_kind) * 3 + int(template.band)
		for body in template.bodies:
			var stem: String = body.split("{")[0]
			prefixes[stem] = cell
	return prefixes


func _classify(body: String, prefixes: Dictionary[String, int]) -> int:
	for stem in prefixes:
		if body.begins_with(stem):
			return prefixes[stem]
	return -1


func _landed_kinds(report: WeekReport) -> Array[int]:
	var kinds: Array[int] = []
	if report.has_beat(WeekReport.Beat.WAVE_LANDED):
		kinds.append(int(PendingSignal.Kind.WITHDRAWAL_WAVE))
	if report.has_beat(WeekReport.Beat.BUZZ_LANDED):
		kinds.append(int(PendingSignal.Kind.WORD_OF_MOUTH))
	if report.has_beat(WeekReport.Beat.PRESS_CALL):
		kinds.append(int(PendingSignal.Kind.JOURNALIST))
	return kinds
