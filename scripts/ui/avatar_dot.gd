class_name AvatarDot
extends Control
## A generated avatar: a coloured disc with one or two initials on it.
##
## There are no image assets in this project, so this is what a face is. Drawn
## rather than composed from nodes because it is one circle and one string, and
## a dozen of them exist on screen at once.

const DIAMETER := 32.0
const FONT_SIZE := 12

var _initials: String = "?"
var _fill: Color = Palette.PANEL_EDGE


func _init() -> void:
	custom_minimum_size = Vector2(DIAMETER, DIAMETER)
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_member(member: CastMember) -> void:
	_initials = member.initials()
	_fill = Palette.avatar(member.avatar_tint)
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	draw_circle(centre, minf(size.x, size.y) * 0.5, _fill)

	# Baseline sits so the cap height, not the em box, is centred on the disc.
	var font := get_theme_default_font()
	var baseline := centre.y + (font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) * 0.5
	draw_string(font, Vector2(0.0, baseline), _initials,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, FONT_SIZE, Palette.BACKDROP)
