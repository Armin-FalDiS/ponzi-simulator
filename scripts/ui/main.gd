extends Control
## Root of the demo. Owns the theme, builds the repetitive widget rows, and
## translates EventBus traffic into text. No game rules live here.
##
## Since Phase 4 this view is **the pitch**. Every number on it is one you could
## read off your own paperwork; nothing on it describes what is going on in
## somebody else's head. Trust, heat and hype are not shown, hinted at, or
## derivable from anything here — they live in the back office, behind a keypress
## the player has to decide to make (DESIGN.md §3, Pillar 4).

## Top-bar readouts, in display order. Five facts from the filing cabinet, and
## nothing else is allowed up here — check DESIGN.md §3 before adding a sixth.
const TILES: Array[String] = [
	"week", "your pocket", "cash on hand", "next payout", "owed to investors",
]

## Width per tile, chosen so the five of them fit the 1280px layout.
const TILE_WIDTH := 180.0

@onready var _controller: GameController = %GameController
@onready var _stat_bar: HBoxContainer = %StatBar
@onready var _chart: ChartView = %Chart
@onready var _calendar: CalendarStrip = %Calendar
@onready var _calendar_note: Label = %CalendarNote
@onready var _feed: FeedView = %Feed
@onready var _controls: ControlsPanel = %Controls
@onready var _back_office: BackOffice = %BackOffice
@onready var _books_button: Button = %BooksButton
@onready var _game_over: Control = %GameOver
@onready var _verdict: Label = %Verdict
@onready var _summary: RichTextLabel = %Summary
@onready var _restart: Button = %Restart

var _tiles: Dictionary[String, StatTile] = {}


func _ready() -> void:
	theme = ThemeFactory.build()
	_build_tiles()
	_connect_signals()
	_game_over.visible = false
	_controller.start_run()


func _build_tiles() -> void:
	for caption in TILES:
		var tile := StatTile.new(caption, TILE_WIDTH)
		_stat_bar.add_child(tile)
		_tiles[caption] = tile


func _connect_signals() -> void:
	EventBus.run_started.connect(_on_run_started)
	EventBus.week_advanced.connect(_on_week_advanced)
	EventBus.run_ended.connect(_on_run_ended)

	_controls.promised_return_changed.connect(_on_return_changed)
	_controls.payout_interval_changed.connect(_on_interval_changed)
	_controls.skim_changed.connect(_on_skim_changed)
	_controls.marketing_changed.connect(_on_marketing_changed)
	_controls.action_chosen.connect(_on_action_chosen)
	_controls.advance_requested.connect(_controller.advance_week)
	_controls.autoplay_toggled.connect(_on_autoplay_toggled)
	_controls.exit_scam_requested.connect(_controller.exit_scam)
	_books_button.pressed.connect(_back_office.toggle)
	_restart.pressed.connect(_controller.start_run)


func _exit_tree() -> void:
	EventBus.run_started.disconnect(_on_run_started)
	EventBus.week_advanced.disconnect(_on_week_advanced)
	EventBus.run_ended.disconnect(_on_run_ended)


## Tab is claimed here rather than in `_unhandled_input` because focus navigation
## eats it during the viewport's GUI pass, long before an unhandled event exists.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_back_office"):
		_back_office.toggle()
		get_viewport().set_input_as_handled()
	elif _back_office.is_open() and event.is_action_pressed("ui_cancel"):
		_back_office.set_open(false)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# The books cover the levers, so they cover the keyboard too. Advancing a week
	# you cannot see the feed of is not a shortcut worth having.
	if _back_office.is_open():
		return
	if event.is_action_pressed("advance_week"):
		_controller.advance_week()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_autoplay"):
		var next := not _controller.is_autoplay()
		_controller.set_autoplay(next)
		_controls.set_autoplay_state(_controller.is_autoplay())
		get_viewport().set_input_as_handled()


#region EventBus handlers

func _on_run_started(state: SchemeState) -> void:
	_game_over.visible = false
	_chart.clear()
	_calendar.clear()
	_feed.reset(state)
	_back_office.reset()
	_controls.set_running(true)
	_controls.sync_levers(state, _controller.config)
	_refresh(state)
	_refresh_action_costs()


func _on_week_advanced(report: WeekReport) -> void:
	_feed.write_week(report)
	_back_office.write_week(report)
	_refresh(_controller.state)
	_refresh_action_costs()
	_tiles["your pocket"].pulse()
	if report.payout_due > 0.5:
		_tiles["next payout"].pulse()


func _on_run_ended(report: WeekReport) -> void:
	_controls.set_running(false)
	_back_office.set_open(false)
	_show_verdict(report)

#endregion


#region Presentation

func _refresh(state: SchemeState) -> void:
	if state == null:
		return

	var calendar := _controller.obligation_forecast()
	var owed := state.principal()
	var head_count := state.investors()

	_tiles["week"].set_value(str(state.week))
	_tiles["week"].set_note("%s investors trusting you" % Fmt.grouped(head_count))

	# The score, and only the score. What you would actually *keep* depends on
	# heat, so that figure is a back-office number and the note only points at it.
	# Phase 3 showed it here and it was a heat readout in disguise.
	_tiles["your pocket"].set_value(Fmt.money(state.pocket), Palette.POCKET)
	_tiles["your pocket"].set_note("before the laundering cut")

	_tiles["cash on hand"].set_value(Fmt.money(state.fund), Palette.CASH)
	_tiles["cash on hand"].set_note(_coverage_note(state, calendar))

	_refresh_next_payout(state, calendar)

	_tiles["owed to investors"].set_value(Fmt.money(owed), Palette.LIABILITY)
	_tiles["owed to investors"].set_note("%s due over %d wks" % [
		Fmt.money(_calendar_total(calendar)), calendar.size()])

	_calendar.show_calendar(state.week, calendar, state.fund)
	_calendar_note.text = _calendar_caveat(state, calendar)
	_chart.show_history(state.fund_history, state.liability_history, state.pocket_history)
	_back_office.observe(state, _controller.config, calendar, _controller.heat_floor())


## The bill, presented as a bill. Scheduled weeks out, exact to the dollar, and
## indifferent to how the week goes — which is the point of Pillar 1.
func _refresh_next_payout(state: SchemeState, calendar: Array[float]) -> void:
	var tile := _tiles["next payout"]
	var offset := CalendarStrip.next_due_offset(calendar)
	if offset < 0:
		tile.set_value("—")
		tile.set_note("nothing scheduled")
		return

	var amount := calendar[offset - 1]
	var covered := state.fund >= amount
	tile.set_value(Fmt.money(amount), Palette.CASH if covered else Palette.HEAT)
	var when := "this coming week" if offset == 1 else "week %d · %d wks" % [
		state.week + offset, offset]
	tile.set_note(when if covered else "%s — short %s" % [when, Fmt.money(amount - state.fund)])


func _calendar_total(calendar: Array[float]) -> float:
	var total := 0.0
	for amount in calendar:
		total += amount
	return total


## How far today's cash stretches against the bills already signed, assuming not
## one more person ever joins **and nobody reinvests**. Both halves of that are
## deliberate: reinvestment is a guess about other people's minds, and a guess
## priced off trust has no business on this view. The version with the guess in it
## is in the back office.
func _coverage_note(state: SchemeState, calendar: Array[float]) -> String:
	var dry := CalendarStrip.dry_index(calendar, state.fund)
	if dry < 0:
		return "covers all %d wks of bills" % calendar.size()
	if dry == 0:
		return "short on this week's bill"
	return "covers %d wks of bills" % dry


func _calendar_caveat(state: SchemeState, calendar: Array[float]) -> String:
	var dry := CalendarStrip.dry_index(calendar, state.fund)
	if dry < 0:
		return "if nobody else ever joins · still standing in %d wks" % calendar.size()
	return "if nobody else ever joins · the money is gone by week %d" % (state.week + dry + 1)


func _refresh_action_costs() -> void:
	var costs: Array[float] = []
	for action in ControlsPanel.ACTIONS:
		costs.append(_controller.action_cost(action as SchemeSim.Action))
	var fund := _controller.state.fund if _controller.state != null else 0.0
	_controls.sync_actions(costs, fund, int(_controller.pending_action))


func _show_verdict(report: WeekReport) -> void:
	var headline := ""
	var body := ""
	match report.outcome:
		SchemeState.Outcome.EXIT_SCAM:
			headline = "GONE"
			body = "You closed the fund on week %d and left %s people holding %s of paper." % [
				report.week, Fmt.grouped(report.investors), Fmt.money(report.principal)]
		SchemeState.Outcome.BANK_RUN:
			headline = "BANK RUN"
			body = "Week %d: the withdrawal queue was longer than the balance. It unravelled in an afternoon." % report.week
		SchemeState.Outcome.DEFAULTED:
			headline = "DEFAULT"
			body = "Week %d: the cheques stopped clearing and %s investors worked out why." % [
				report.week, Fmt.grouped(report.investors)]
		SchemeState.Outcome.BUSTED:
			headline = "INDICTED"
			body = "Week %d: the regulator arrived before you did. Every account is frozen." % report.week
		_:
			headline = "OVER"
			body = ""

	_verdict.text = headline
	_summary.clear()
	_summary.append_text("[color=#%s]%s[/color]\n\n" % [Palette.INK_DIM.to_html(false), body])
	_summary.append_text("[color=#%s]Peak liabilities  %s[/color]\n" % [
		Palette.LIABILITY.to_html(false), Fmt.money(_peak_liabilities())])
	_summary.append_text("[color=#%s]Skimmed in total  %s[/color]\n" % [
		Palette.INK.to_html(false), Fmt.money(report.pocket)])
	_summary.append_text("[color=#%s][b]Walked away with  %s[/b][/color]" % [
		Palette.POCKET.to_html(false), Fmt.money(report.take_home)])

	_game_over.visible = true
	_game_over.modulate.a = 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_game_over, "modulate:a", 1.0, 0.35)
	_restart.grab_focus()


func _peak_liabilities() -> float:
	var peak := 0.0
	if _controller.state != null:
		for value in _controller.state.liability_history:
			peak = maxf(peak, value)
	return peak

#endregion


#region Lever handlers

func _on_return_changed(value: float) -> void:
	if _controller.state != null:
		_controller.set_terms(value, _controller.state.current_terms.interval_weeks)
		_refresh(_controller.state)


func _on_interval_changed(weeks: int) -> void:
	if _controller.state != null:
		_controller.set_terms(_controller.state.current_terms.weekly_rate(), weeks)
		_refresh(_controller.state)


func _on_skim_changed(value: float) -> void:
	if _controller.state != null:
		_controller.state.skim_rate = value


func _on_marketing_changed(value: float) -> void:
	if _controller.state != null:
		_controller.state.marketing = value
		_refresh(_controller.state)


func _on_action_chosen(action: int) -> void:
	_controller.pending_action = action as SchemeSim.Action
	_refresh_action_costs()


func _on_autoplay_toggled(enabled: bool) -> void:
	_controller.set_autoplay(enabled)
	_controls.set_autoplay_state(_controller.is_autoplay())

#endregion
