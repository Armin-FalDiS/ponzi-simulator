class_name BackOffice
extends Control
## The honest books, one keypress away. Pillar 4 lives in this file.
##
## Everything the main view is not allowed to say: the two-line chart with the gap
## in it, solvency, the exact soft stats, what you would actually walk away with
## at today's heat, the cohort table, and the arithmetic narration the sim has
## been writing to `WeekReport.ledger_lines` since Phase 2 with nobody reading it.
##
## Two rules it must keep:
##
##   * **It is a view.** It reads a `SchemeState`, a `SchemeConfig` and a stream of
##     `WeekReport`s handed over by `main.gd`, and touches the simulation through
##     neither. Nothing in here decides anything.
##   * **Opening it is a deliberate act.** Nothing here leaks into the main view,
##     and the main view never quietly answers a question this panel exists to
##     answer. If a number appears in both places, one of them is a bug.
##
## Built entirely in code: it is six near-identical fact rows, a table and a list,
## and those are exactly the shapes that rot when they live in a .tscn.

## Fact rows down the left, in display order. The key is the caption *and* the
## lookup, so a row cannot be relabelled without moving its writer.
const FACTS: Array[String] = [
	"assets cover", "take-home if you run now", "laundering cut",
	"cash runway", "carried forward", "missed payouts in a row",
	"showing-off reach", "average stake",
]

const COHORT_COLUMNS: Array[String] = ["signed", "terms", "heads", "principal", "next cheque"]

## Ledger rows kept before the oldest is dropped. A long run would otherwise grow
## the tree without bound, exactly as the feed would.
const MAX_LEDGER_ROWS := 200

var _chart: ChartView
var _facts: Dictionary[String, Label] = {}
var _cohort_grid: GridContainer
var _ledger: VBoxContainer
var _ledger_scroll: ScrollContainer
var _trust: MeterBar
var _heat: MeterBar
var _hype: MeterBar
var _close: Button

var _state: SchemeState
var _config: SchemeConfig
var _calendar: Array[float] = []
var _heat_floor: float = -1.0


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Swallows clicks so the levers underneath cannot be worked blind while the
	# books are open. `main.gd` blocks the keyboard equivalent for the same reason.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


#region Construction

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(Palette.BACKDROP, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var card := PanelContainer.new()
	margin.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)
	column.add_child(_build_header())
	column.add_child(_build_body())


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = "BACK OFFICE"
	title.theme_type_variation = "Title"
	row.add_child(title)

	var note := Label.new()
	note.text = "the numbers nobody outside this room gets to see"
	note.theme_type_variation = "Subtitle"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_END
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(note)

	_close = Button.new()
	_close.text = "Close   (Tab)"
	_close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close.pressed.connect(func() -> void: set_open(false))
	row.add_child(_close)

	return row


func _build_body() -> Control:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.6
	left.add_theme_constant_override("separation", 10)
	left.add_child(_build_chart())
	left.add_child(_build_facts())
	left.add_child(_build_meters())
	row.add_child(left)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	right.add_child(_build_book())
	right.add_child(_build_ledger())
	row.add_child(right)

	return row


func _build_chart() -> Control:
	var panel := _section("THE GAP", "what you hold against what you have promised")
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_chart = ChartView.new()
	_chart.mode = ChartView.Mode.HONEST
	_chart.custom_minimum_size = Vector2(0.0, 150.0)
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_of(panel).add_child(_chart)
	return panel


func _build_facts() -> Control:
	var panel := _section("SOLVENCY", "and what leaving today is actually worth")

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 3)
	_body_of(panel).add_child(grid)

	for key in FACTS:
		var caption := Label.new()
		caption.text = key.to_upper()
		caption.theme_type_variation = "SectionLabel"
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(caption)

		var value := Label.new()
		value.text = "—"
		value.theme_type_variation = "FactValue"
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
		_facts[key] = value

	return panel


## The three floats DESIGN.md §3 bans from the main view. They are only readable
## here, and they are readable exactly — a player who wants to optimise may.
func _build_meters() -> Control:
	var panel := _section("MOOD", "inferred from the feed out there; measured in here")
	var box := _body_of(panel)
	box.add_theme_constant_override("separation", 8)

	_trust = MeterBar.new("investor trust", Palette.TRUST,
		"How safe investors feel. Low trust means withdrawals and no reinvestment.",
		-1.0, 25.0)
	_heat = MeterBar.new("regulator heat", Palette.HEAT,
		"Attention from people with subpoena power. At 100 the run ends and you keep nothing.",
		75.0, -1.0)
	_hype = MeterBar.new("market hype", Palette.HYPE,
		"How loud the story is. Decays every week unless you keep paying for it.")
	for meter in [_trust, _heat, _hype]:
		box.add_child(meter)
	return panel


func _build_book() -> Control:
	var panel := _section("THE BOOK", "every promise still on the paperwork")
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0.0, 120.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_of(panel).add_child(scroll)

	_cohort_grid = GridContainer.new()
	_cohort_grid.columns = COHORT_COLUMNS.size()
	_cohort_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cohort_grid.add_theme_constant_override("h_separation", 12)
	_cohort_grid.add_theme_constant_override("v_separation", 3)
	scroll.add_child(_cohort_grid)
	return panel


func _build_ledger() -> Control:
	var panel := _section("THE LEDGER", "the arithmetic, in the words it deserves")
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_ledger_scroll = ScrollContainer.new()
	_ledger_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ledger_scroll.custom_minimum_size = Vector2(0.0, 140.0)
	_ledger_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_of(panel).add_child(_ledger_scroll)

	_ledger = VBoxContainer.new()
	_ledger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ledger.add_theme_constant_override("separation", 3)
	_ledger_scroll.add_child(_ledger)
	return panel


## A titled inner panel. Its second child is always the content box, which is
## what `_body_of` relies on.
func _section(title: String, hint: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Inner"

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	var label := Label.new()
	label.text = title
	label.theme_type_variation = "SectionLabel"
	header.add_child(label)

	var note := Label.new()
	note.text = hint
	note.theme_type_variation = "TileNote"
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.clip_text = true
	header.add_child(note)

	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	return panel


func _body_of(panel: PanelContainer) -> VBoxContainer:
	return panel.get_child(0).get_child(1) as VBoxContainer

#endregion


#region Opening and closing

func toggle() -> void:
	set_open(not visible)


func set_open(open: bool) -> void:
	if open == visible:
		return
	visible = open
	if open:
		_repaint()
		_close.grab_focus()


func is_open() -> bool:
	return visible

#endregion


#region Data in

## Latest position. Called every week whether or not anybody is looking, so the
## widget rebuild waits until somebody is.
func observe(state: SchemeState, config: SchemeConfig, calendar: Array[float],
		heat_floor: float) -> void:
	_state = state
	_config = config
	_calendar = calendar
	_heat_floor = heat_floor
	if visible:
		_repaint()


func reset() -> void:
	for child in _ledger.get_children():
		_ledger.remove_child(child)
		child.queue_free()
	_chart.clear()
	set_open(false)


## Appends a week of arithmetic narration. Newest week at the top, matching the
## feed, so the two columns of the same week are never read in opposite orders.
func write_week(report: WeekReport) -> void:
	var at := 0
	_insert(_rule("week %d" % report.week), at)
	at += 1
	for i in report.ledger_lines.size():
		var tone := report.ledger_tones[i] if i < report.ledger_tones.size() \
			else int(WeekReport.Tone.NEUTRAL)
		_insert(_line(report.ledger_lines[i], Palette.tone(tone)), at)
		at += 1
	_trim_ledger()
	_ledger_scroll.scroll_vertical = 0


func _insert(row: Control, index: int) -> void:
	_ledger.add_child(row)
	_ledger.move_child(row, index)

#endregion


#region Presentation

func _repaint() -> void:
	if _state == null or _config == null:
		return
	_chart.show_history(_state.fund_history, _state.liability_history,
		_state.pocket_history)
	_refresh_facts()
	_refresh_meters()
	_refresh_book()


func _refresh_facts() -> void:
	var ratio := _state.solvency()
	_set_fact("assets cover", "%s · %s" % [Fmt.percent(ratio, 0), _solvency_note(ratio)],
		Palette.solvency_color(ratio))

	# What leaving *right now* is worth, sweeping the fund on the way out and
	# paying the laundering cut at today's heat. The main view is not allowed to
	# say this, because the cut is a function of a number the player is supposed
	# to infer — so the honest figure lives here and nowhere else.
	var kept := clampf(1.0 - (_state.heat / 100.0) * _config.exit_heat_penalty, 0.0, 1.0)
	var gross := _state.pocket + maxf(_state.fund, 0.0)
	_set_fact("take-home if you run now", Fmt.money(gross * kept), Palette.POCKET)
	_set_fact("laundering cut", "%s of %s" % [
		Fmt.money(gross * (1.0 - kept)), Fmt.money(gross)],
		Palette.LIABILITY if kept < 0.75 else Palette.INK)

	_set_fact("cash runway", _projected_runway(),
		Palette.CASH if _state.fund > 0.0 else Palette.LIABILITY)
	_set_fact("carried forward", Fmt.money(_state.deferred_payout),
		Palette.LIABILITY if _state.deferred_payout > 0.5 else Palette.INK_DIM)
	_set_fact("missed payouts in a row", str(_state.missed_payouts),
		Palette.LIABILITY if _state.missed_payouts > 0 else Palette.INK_DIM)
	_set_fact("showing-off reach", Fmt.percent(_state.flex_reach, 0),
		Palette.CASH if _state.flex_reach > 0.5 else Palette.INK_DIM)
	_set_fact("average stake", "%s across %s people" % [
		Fmt.money(_state.avg_stake()), Fmt.grouped(_state.investors())])


func _set_fact(key: String, text: String, color: Color = Palette.INK) -> void:
	var label := _facts.get(key) as Label
	if label == null:
		return
	label.text = text
	label.add_theme_color_override("font_color", color)


func _refresh_meters() -> void:
	_trust.set_value(_state.trust)
	_heat.set_value(_state.heat)
	_heat.set_marker(_heat_floor,
		"Heat you can no longer buy your way out of at this size.")
	_hype.set_value(_state.hype)


## The cohort table, rebuilt rather than diffed: `consolidate()` keeps the book in
## single digits and rewrites rows in place, so there is no stable identity to
## diff against.
func _refresh_book() -> void:
	for child in _cohort_grid.get_children():
		_cohort_grid.remove_child(child)
		child.queue_free()

	for column in COHORT_COLUMNS:
		var header := Label.new()
		header.text = column.to_upper()
		header.theme_type_variation = "SectionLabel"
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if column == "signed" \
			else HORIZONTAL_ALIGNMENT_RIGHT
		_cohort_grid.add_child(header)

	for cohort in _state.cohorts:
		var offset := _weeks_until_cohort_due(cohort)
		_cohort_grid.add_child(_cell("wk %d" % cohort.join_week, HORIZONTAL_ALIGNMENT_LEFT))
		_cohort_grid.add_child(_cell("%s at %s" % [
			_interval_label(cohort.interval_weeks),
			Fmt.percent(cohort.rate_per_interval)]))
		_cohort_grid.add_child(_cell(Fmt.grouped(cohort.head_count)))
		_cohort_grid.add_child(_cell(Fmt.money(cohort.principal)))
		_cohort_grid.add_child(_cell("%s in %d wk%s" % [
			Fmt.money(cohort.amount_due()), offset, "" if offset == 1 else "s"],
			HORIZONTAL_ALIGNMENT_RIGHT, Palette.LIABILITY if offset == 1 else Palette.INK_DIM))

	if _state.cohorts.is_empty():
		_cohort_grid.add_child(_cell("nobody is in", HORIZONTAL_ALIGNMENT_LEFT))


## Weeks until this cohort's next cheque. Mirrors `InvestorCohort.is_due`: the
## join week itself never collects, so a fresh cohort is a full interval away.
func _weeks_until_cohort_due(cohort: InvestorCohort) -> int:
	var elapsed := _state.week - cohort.join_week
	var into_cycle := posmod(elapsed, cohort.interval_weeks)
	return cohort.interval_weeks - into_cycle


func _interval_label(weeks: int) -> String:
	var index := SchemeTerms.INTERVALS.find(weeks)
	return SchemeTerms.INTERVAL_LABELS[index].to_lower() if index >= 0 \
		else "every %d wks" % weeks


## Weeks of cash left once reinvestment at the current trust level is priced in.
## The main view's cash note deliberately assumes nobody reinvests, because
## reinvestment is a guess about other people's minds; this is the version with
## the guess in it, which is why it belongs here.
func _projected_runway() -> String:
	var reinvest := clampf(_state.trust / 100.0, 0.0, 1.0) * _config.reinvest_ceiling
	var cash := _state.fund
	for i in _calendar.size():
		cash -= _calendar[i] * (1.0 - reinvest) + _state.marketing
		if cash < 0.0:
			return Fmt.weeks(float(i))
	return "clear for %d wks" % _calendar.size()


func _solvency_note(ratio: float) -> String:
	if ratio >= 0.90:
		return "still nearly honest"
	if ratio >= 0.65:
		return "the gap is opening"
	if ratio >= 0.35:
		return "structurally a fraud"
	if ratio >= 0.15:
		return "held up by new money only"
	return "there is nothing behind this"


func _cell(text: String, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT,
		color: Color = Palette.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "TableCell"
	label.horizontal_alignment = align
	label.add_theme_color_override("font_color", color)
	return label


func _line(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "LedgerLine"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	return label


func _rule(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = text.to_upper()
	label.theme_type_variation = "SectionLabel"
	row.add_child(label)

	var line := Panel.new()
	line.custom_minimum_size = Vector2(0.0, 1.0)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_theme_stylebox_override("panel", ThemeFactory.hairline())
	row.add_child(line)
	return row


func _trim_ledger() -> void:
	while _ledger.get_child_count() > MAX_LEDGER_ROWS:
		var oldest := _ledger.get_child(_ledger.get_child_count() - 1)
		_ledger.remove_child(oldest)
		oldest.queue_free()

#endregion
