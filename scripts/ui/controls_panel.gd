class_name ControlsPanel
extends PanelContainer
## The player's whole input surface: three levers, four one-shot actions, and the
## clock.
##
## Reports upward with its own signals — parent/child communication, so no
## EventBus involved — and never touches the simulation directly.

signal promised_return_changed(value: float)
signal payout_interval_changed(weeks: int)
signal skim_changed(value: float)
signal marketing_changed(value: float)
## `action` is a `SchemeSim.Action`; NONE means "nothing queued".
signal action_chosen(action: int)
signal advance_requested()
signal autoplay_toggled(enabled: bool)
signal exit_scam_requested()

## Actions offered as buttons, in display order.
const ACTIONS: Array[int] = [
	SchemeSim.Action.FAKE_AUDIT,
	SchemeSim.Action.TESTIMONIAL_GALA,
	SchemeSim.Action.LOBBY_REGULATOR,
	SchemeSim.Action.DELAY_PAYOUT,
	SchemeSim.Action.PART_PAY,
]


## A caption + slider + readout group.
class Lever extends RefCounted:
	var slider: HSlider
	var readout: Label


var _return: Lever
var _skim: Lever
var _marketing: Lever
var _interval: OptionButton
var _terms_note: Label

var _action_buttons: Array[Button] = []
var _action_costs: Array[float] = []
var _queued_label: Label
var _advance_button: Button
var _auto_button: Button
var _exit_button: Button

var _running: bool = true
var _fund: float = 0.0


func _ready() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	column.add_child(_build_levers())
	column.add_child(_build_terms_row())
	column.add_child(_build_action_row())


#region Construction

func _build_levers() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)

	_return = _add_lever(row, "PROMISED RETURN PER WEEK", 0.005, 0.15, 0.005,
		"The hook. Big promises pull crowds — and accrue against every dollar you owe.")
	_return.slider.value_changed.connect(_on_return_changed)

	_skim = _add_lever(row, "SKIM OFF DEPOSITS", 0.0, 0.5, 0.01,
		"Your cut of every new deposit. You still owe investors the full amount.")
	_skim.slider.value_changed.connect(_on_skim_changed)

	_marketing = _add_lever(row, "MARKETING PER WEEK", 0.0, 25000.0, 500.0,
		"Buys hype, hype buys recruits. Paid out of the fund every week.")
	_marketing.slider.value_changed.connect(_on_marketing_changed)

	return row


func _add_lever(row: HBoxContainer, caption: String, min_value: float, max_value: float,
		step: float, hint: String) -> Lever:
	var group := VBoxContainer.new()
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_theme_constant_override("separation", 2)
	group.tooltip_text = hint
	group.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(group)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	group.add_child(header)

	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.theme_type_variation = "SectionLabel"
	caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption_label.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(caption_label)

	var lever := Lever.new()
	lever.readout = Label.new()
	lever.readout.theme_type_variation = "LeverValue"
	header.add_child(lever.readout)

	lever.slider = HSlider.new()
	lever.slider.min_value = min_value
	lever.slider.max_value = max_value
	lever.slider.step = step
	lever.slider.custom_minimum_size = Vector2(150.0, 0.0)
	lever.slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lever.slider.focus_mode = Control.FOCUS_ALL
	group.add_child(lever.slider)
	return lever


## The payout interval sits apart from the sliders because it behaves
## differently: it is a promise about *when*, and it only ever binds people who
## sign after you change it.
func _build_terms_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var caption := Label.new()
	caption.text = "PAYOUT INTERVAL"
	caption.theme_type_variation = "SectionLabel"
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption)

	_interval = OptionButton.new()
	_interval.focus_mode = Control.FOCUS_ALL
	_interval.tooltip_text = "How often you owe. Short intervals sell better; long ones\n" \
		+ "hand you weeks of float and then land as one cliff.\n" \
		+ "Existing investors keep the terms they signed."
	for i in SchemeTerms.INTERVALS.size():
		_interval.add_item("%s · every %d wk" % [
			SchemeTerms.INTERVAL_LABELS[i], SchemeTerms.INTERVALS[i]], i)
	_interval.item_selected.connect(_on_interval_selected)
	row.add_child(_interval)

	_terms_note = Label.new()
	_terms_note.theme_type_variation = "SectionLabel"
	_terms_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_terms_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_terms_note)

	return row


func _build_action_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	for action in ACTIONS:
		var button := Button.new()
		button.toggle_mode = true
		button.text = SchemeSim.ACTION_LABELS[action]
		button.tooltip_text = SchemeSim.ACTION_HINTS[action]
		button.focus_mode = Control.FOCUS_ALL
		button.toggled.connect(_on_action_toggled.bind(action))
		row.add_child(button)
		_action_buttons.append(button)
		_action_costs.append(0.0)

	_queued_label = Label.new()
	_queued_label.theme_type_variation = "SectionLabel"
	_queued_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_queued_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_queued_label)

	_exit_button = Button.new()
	_exit_button.text = "Exit Scam"
	_exit_button.theme_type_variation = "Danger"
	_exit_button.tooltip_text = "End the run now and keep whatever you can launder.\n" \
		+ "How much that is depends on how hot you are — the back office (Tab)\n" \
		+ "is the only place the figure is written down."
	_exit_button.pressed.connect(func() -> void: exit_scam_requested.emit())
	row.add_child(_exit_button)

	_auto_button = Button.new()
	_auto_button.text = "Auto ▶"
	_auto_button.toggle_mode = true
	_auto_button.tooltip_text = "Let the weeks run by themselves."
	_auto_button.toggled.connect(_on_auto_toggled)
	row.add_child(_auto_button)

	_advance_button = Button.new()
	_advance_button.text = "Next Week   (Space)"
	_advance_button.theme_type_variation = "Primary"
	_advance_button.pressed.connect(func() -> void: advance_requested.emit())
	row.add_child(_advance_button)

	return row

#endregion


#region Sync

## Pushes lever state into the widgets without re-emitting change signals.
func sync_levers(state: SchemeState, config: SchemeConfig) -> void:
	_return.slider.max_value = config.max_promised_return
	_skim.slider.max_value = config.max_skim_rate
	_marketing.slider.max_value = config.max_marketing
	_return.slider.set_value_no_signal(state.current_terms.weekly_rate())
	_skim.slider.set_value_no_signal(state.skim_rate)
	_marketing.slider.set_value_no_signal(state.marketing)
	var index := SchemeTerms.INTERVALS.find(state.current_terms.interval_weeks)
	_interval.select(maxi(index, 0))
	_refresh_readouts()


## Called each week with the current price of each action, so buttons can show
## costs and grey out when the fund can't cover them.
func sync_actions(costs: Array[float], fund: float, queued: int) -> void:
	_fund = fund
	_action_costs = costs
	for i in _action_buttons.size():
		var action := ACTIONS[i]
		var cost := costs[i]
		var button := _action_buttons[i]
		button.text = SchemeSim.ACTION_LABELS[action] if cost <= 0.0 \
			else "%s · %s" % [SchemeSim.ACTION_LABELS[action], Fmt.money(cost)]
		button.set_pressed_no_signal(action == queued)
	_queued_label.text = "" if queued == SchemeSim.Action.NONE \
		else "queued: %s" % SchemeSim.ACTION_LABELS[queued]
	_refresh_enabled()


func set_running(running: bool) -> void:
	_running = running
	_refresh_enabled()
	if not running:
		_auto_button.set_pressed_no_signal(false)
		_auto_button.text = "Auto ▶"


func set_autoplay_state(enabled: bool) -> void:
	_auto_button.set_pressed_no_signal(enabled)
	_auto_button.text = "Auto ⏸" if enabled else "Auto ▶"

#endregion


func _refresh_enabled() -> void:
	_advance_button.disabled = not _running
	_auto_button.disabled = not _running
	_exit_button.disabled = not _running
	for i in _action_buttons.size():
		var affordable := _action_costs[i] <= _fund
		_action_buttons[i].disabled = not _running or not affordable
	for lever in [_return, _skim, _marketing]:
		lever.slider.editable = _running
	_interval.disabled = not _running


func _refresh_readouts() -> void:
	_return.readout.text = Fmt.percent(_return.slider.value)
	_skim.readout.text = Fmt.percent(_skim.slider.value, 0)
	_marketing.readout.text = Fmt.money(_marketing.slider.value)

	# Spell out the promise as it will actually appear on the paperwork, so the
	# headline rate and the weekly-equivalent one are never confused.
	var weeks := _selected_interval()
	_terms_note.text = "new investors sign %s every %d wk" % [
		Fmt.percent(_return.slider.value * float(weeks), 1), weeks]


func _selected_interval() -> int:
	var index := _interval.get_selected_id()
	return SchemeTerms.INTERVALS[index] if index >= 0 else 1


func _on_interval_selected(_index: int) -> void:
	_refresh_readouts()
	payout_interval_changed.emit(_selected_interval())


func _on_return_changed(value: float) -> void:
	_refresh_readouts()
	promised_return_changed.emit(value)


func _on_skim_changed(value: float) -> void:
	_refresh_readouts()
	skim_changed.emit(value)


func _on_marketing_changed(value: float) -> void:
	_refresh_readouts()
	marketing_changed.emit(value)


## Action buttons are radio-like: pressing one queues it, pressing it again or
## picking another clears the previous.
func _on_action_toggled(pressed: bool, action: int) -> void:
	action_chosen.emit(action if pressed else SchemeSim.Action.NONE)


func _on_auto_toggled(pressed: bool) -> void:
	_auto_button.text = "Auto ⏸" if pressed else "Auto ▶"
	autoplay_toggled.emit(pressed)
