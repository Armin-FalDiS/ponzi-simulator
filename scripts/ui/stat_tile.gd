class_name StatTile
extends PanelContainer
## One readout in the top bar: caption, big number, small note underneath.
##
## Built in code because six near-identical tiles in a .tscn is six copies of the
## same layout to keep in sync. It is still a normal Control that a container
## lays out normally.

var _caption: Label
var _value: Label
var _note: Label


func _init(caption: String = "", min_width: float = 150.0) -> void:
	theme_type_variation = "Tile"
	custom_minimum_size = Vector2(min_width, 0.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 1)
	add_child(column)

	_caption = _make_label(caption.to_upper(), "TileLabel")
	_value = _make_label("—", "TileValue")
	_note = _make_label(" ", "TileNote")
	column.add_child(_caption)
	column.add_child(_value)
	column.add_child(_note)


func set_value(text: String, color: Color = Palette.INK) -> void:
	_value.text = text
	_value.add_theme_color_override("font_color", color)


func set_note(text: String, color: Color = Palette.INK_DIM) -> void:
	_note.text = text
	_note.add_theme_color_override("font_color", color)


## Quick scale pop so a changing number catches the eye without a full animation
## system. Pivot is set every time because size isn't known until layout runs.
func pulse() -> void:
	pivot_offset = size * 0.5
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE * 1.06, 0.08)
	tween.tween_property(self, "scale", Vector2.ONE, 0.16)


func _make_label(text: String, variation: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.focus_mode = Control.FOCUS_NONE
	return label
