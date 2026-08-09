class_name MeterBar
extends VBoxContainer
## Labelled 0–100 bar for the soft stats (trust / heat / hype), with an optional
## marker for a threshold the player can't cross.
##
## **Back office only.** These three floats are banned from the main view by
## DESIGN.md §3 — not as a bar, not as a number, and not as anything a number can
## be recovered from. This widget exists so the player who deliberately opens the
## books gets the exact values; if it ever appears in `main.tscn` again, Pillar 2
## has been quietly undone.

var _bar: ProgressBar
var _value: Label
var _marker: ColorRect
var _fill: Color
## Reading above which the bar turns red. Negative disables.
var _alarm_above: float
## Reading below which the bar turns red. Negative disables.
var _alarm_below: float
var _tween: Tween


func _init(caption: String = "", fill: Color = Palette.TRUST, hint: String = "",
		alarm_above: float = -1.0, alarm_below: float = -1.0) -> void:
	_fill = fill
	_alarm_above = alarm_above
	_alarm_below = alarm_below
	add_theme_constant_override("separation", 2)
	tooltip_text = hint
	mouse_filter = Control.MOUSE_FILTER_PASS

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(header)

	var caption_label := Label.new()
	caption_label.text = caption.to_upper()
	caption_label.theme_type_variation = "SectionLabel"
	caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption_label.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(caption_label)

	_value = Label.new()
	_value.text = "0"
	_value.theme_type_variation = "SectionLabel"
	header.add_child(_value)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0.0, 9.0)
	_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_bar.add_theme_stylebox_override("fill", ThemeFactory.meter_fill(fill))
	add_child(_bar)

	# Threshold notch, anchored by fraction so it tracks the bar's width.
	_marker = ColorRect.new()
	_marker.color = Color(1.0, 1.0, 1.0, 0.55)
	_marker.visible = false
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_marker.offset_right = 2.0
	_bar.add_child(_marker)


## Tweened rather than snapped so a spike in heat reads as motion.
func set_value(value: float) -> void:
	var target := clampf(value, 0.0, 100.0)
	_value.text = "%d" % int(roundf(target))

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_bar, "value", target, 0.25)

	var alarming := (_alarm_above >= 0.0 and target > _alarm_above) \
		or (_alarm_below >= 0.0 and target < _alarm_below)
	_bar.add_theme_stylebox_override("fill",
		ThemeFactory.meter_fill(Palette.ALARM if alarming else _fill))


## Shows a notch at `value` (0–100). Pass a negative number to hide it.
func set_marker(value: float, label: String = "") -> void:
	if value < 0.0:
		_marker.visible = false
		return
	var ratio := clampf(value, 0.0, 100.0) / 100.0
	_marker.visible = true
	_marker.anchor_left = ratio
	_marker.anchor_right = ratio
	_marker.offset_left = 0.0
	_marker.offset_right = 2.0
	_marker.tooltip_text = label
