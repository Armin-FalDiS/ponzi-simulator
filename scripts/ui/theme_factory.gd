class_name ThemeFactory
extends RefCounted
## Builds the single Theme assigned at the UI root.
##
## Generated in code rather than shipped as a .tres so the demo needs no assets
## at all — the engine's default font and the fallback theme cover everything
## this file doesn't override. Type variations ("Title", "TileValue", …) let
## individual labels opt into a look without per-node overrides.


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14

	_panels(theme)
	_labels(theme)
	_buttons(theme)
	_progress(theme)
	return theme


static func _panels(theme: Theme) -> void:
	theme.set_stylebox("panel", "PanelContainer", card(Palette.PANEL))
	theme.set_stylebox("panel", "Panel", card(Palette.PANEL))

	# Slimmer card for the stat tiles along the top.
	theme.set_type_variation("Tile", "PanelContainer")
	var tile := card(Palette.PANEL)
	tile.content_margin_left = 10.0
	tile.content_margin_right = 10.0
	tile.content_margin_top = 7.0
	tile.content_margin_bottom = 7.0
	theme.set_stylebox("panel", "Tile", tile)

	# A card sitting inside another card — the back office is one big panel with
	# five sections in it, and they need to separate without a second border.
	theme.set_type_variation("Inner", "PanelContainer")
	var inner := card(Palette.PANEL_SOFT)
	inner.set_content_margin_all(10.0)
	theme.set_stylebox("panel", "Inner", inner)


static func _labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", Palette.INK)
	theme.set_color("default_color", "RichTextLabel", Palette.INK)
	theme.set_font_size("normal_font_size", "RichTextLabel", 13)

	_label_variant(theme, "Title", 26, Palette.INK)
	_label_variant(theme, "Subtitle", 13, Palette.INK_DIM)
	_label_variant(theme, "SectionLabel", 11, Palette.INK_DIM)
	_label_variant(theme, "TileLabel", 10, Palette.INK_DIM)
	_label_variant(theme, "TileValue", 22, Palette.INK)
	_label_variant(theme, "TileNote", 10, Palette.INK_DIM)
	_label_variant(theme, "Verdict", 34, Palette.INK)
	_label_variant(theme, "LeverValue", 15, Palette.POCKET)

	# Back office: a fact readout, a table cell, and a line of arithmetic.
	_label_variant(theme, "FactValue", 13, Palette.INK)
	_label_variant(theme, "TableCell", 11, Palette.INK)
	_label_variant(theme, "LedgerLine", 11, Palette.INK)

	_label_variant(theme, "PostName", 13, Palette.INK)
	_label_variant(theme, "PostHandle", 11, Palette.INK_DIM)
	_label_variant(theme, "PostBody", 13, Palette.INK)
	_label_variant(theme, "PostMeta", 10, Palette.INK_DIM)


static func _label_variant(theme: Theme, name: String, font_size: int, color: Color) -> void:
	theme.set_type_variation(name, "Label")
	theme.set_font_size("font_size", name, font_size)
	theme.set_color("font_color", name, color)


static func _buttons(theme: Theme) -> void:
	theme.set_stylebox("normal", "Button", _button_box(Color("1d2740"), Palette.PANEL_EDGE))
	theme.set_stylebox("hover", "Button", _button_box(Color("27334f"), Color("3c4a6b")))
	theme.set_stylebox("pressed", "Button", _button_box(Color("161e33"), Color("4c5c82")))
	theme.set_stylebox("disabled", "Button", _button_box(Color("151a29"), Color("1e2537")))
	theme.set_stylebox("focus", "Button", _button_box(Color(0, 0, 0, 0), Color("5b6d97")))
	theme.set_color("font_color", "Button", Palette.INK)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color("495570"))
	theme.set_font_size("font_size", "Button", 13)

	# The one button that should look dangerous.
	theme.set_type_variation("Primary", "Button")
	theme.set_stylebox("normal", "Primary", _button_box(Color("1f3a2b"), Color("3f7a55")))
	theme.set_stylebox("hover", "Primary", _button_box(Color("28503a"), Color("55a173")))
	theme.set_stylebox("pressed", "Primary", _button_box(Color("182c20"), Color("55a173")))
	theme.set_stylebox("disabled", "Primary", _button_box(Color("151a29"), Color("1e2537")))
	theme.set_font_size("font_size", "Primary", 15)

	theme.set_type_variation("Danger", "Button")
	theme.set_stylebox("normal", "Danger", _button_box(Color("3a1f24"), Color("7a3f49")))
	theme.set_stylebox("hover", "Danger", _button_box(Color("50282f"), Color("a1555f")))
	theme.set_stylebox("pressed", "Danger", _button_box(Color("2c181c"), Color("a1555f")))
	theme.set_stylebox("disabled", "Danger", _button_box(Color("151a29"), Color("1e2537")))
	theme.set_font_size("font_size", "Danger", 13)


static func _progress(theme: Theme) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("0d1324")
	bg.set_corner_radius_all(3)
	theme.set_stylebox("background", "ProgressBar", bg)
	theme.set_stylebox("fill", "ProgressBar", meter_fill(Palette.TRUST))


## Rounded card with a hairline border — the base look for every panel.
static func card(fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = Palette.PANEL_EDGE
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(12.0)
	return box


## A post card: lifted a shade off the panel behind it, with the tone carried on
## the left edge only. The sentiment of a post has to be readable in peripheral
## vision without colouring the words themselves.
static func post_box(tone: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.PANEL_SOFT
	box.border_color = tone
	box.border_width_left = 3
	box.set_corner_radius_all(4)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box


## One-pixel divider, used to rule off between weeks in the feed.
static func hairline() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.PANEL_EDGE
	return box


static func meter_fill(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(3)
	return box


static func _button_box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 7.0
	box.content_margin_bottom = 7.0
	return box
