class_name ChartView
extends Control
## Custom-drawn line chart, in two modes that draw the same history differently.
##
## `PITCH` is what hangs on the wall in reception: one line, total investor value,
## and it only ever goes up. That is not a nicer version of the truth, it is
## exactly the number the scheme owes — the brochure simply never mentions what
## sits behind it.
##
## `HONEST` is the back-office cut: liabilities in red, cash in green, and the gap
## between them is the fraud. Same arrays, same scale, two readings — which is
## the whole of Pillar 4 in one widget.
##
## Drawn with `_draw()` so it needs no assets and no plugins.

enum Mode {
	HONEST,  ## cash vs. liabilities vs. pocket — back office only
	PITCH,   ## total investor value, alone
}

const INSET := Vector2(6.0, 6.0)
const GRID_ROWS := 4
## Vertical space kept clear at the top for the legend, so a line at its peak
## never runs underneath the labels.
const LEGEND_BAND := 16.0
## Alpha of the shaded area under the pitch line. Enough to read as a brochure,
## not enough to hide the grid labels behind it.
const PITCH_FILL_ALPHA := 0.13

@export var mode: Mode = Mode.HONEST:
	set(value):
		mode = value
		queue_redraw()

var _cash: Array[float] = []
var _liabilities: Array[float] = []
var _pocket: Array[float] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func show_history(cash: Array[float], liabilities: Array[float], pocket: Array[float]) -> void:
	_cash = cash
	_liabilities = liabilities
	_pocket = pocket
	queue_redraw()


func clear() -> void:
	_cash = []
	_liabilities = []
	_pocket = []
	queue_redraw()


func _draw() -> void:
	var full := Rect2(INSET, size - INSET * 2.0)
	if full.size.x <= 8.0 or full.size.y <= 8.0 + LEGEND_BAND:
		return

	_draw_legend(full)
	var plot := Rect2(full.position + Vector2(0.0, LEGEND_BAND),
		full.size - Vector2(0.0, LEGEND_BAND))

	var peak := _peak()
	_draw_grid(plot, peak)

	if mode == Mode.PITCH:
		_draw_fill(plot, _liabilities, peak, Palette.PITCH)
		_draw_series(plot, _liabilities, peak, Palette.PITCH, 2.5)
		return

	# Liabilities underneath so the cash line reads as "what's left".
	_draw_series(plot, _liabilities, peak, Palette.LIABILITY, 2.0)
	_draw_series(plot, _cash, peak, Palette.CASH, 2.0)
	_draw_series(plot, _pocket, peak, Palette.POCKET, 1.5)


## Scaled to the series actually on screen. The pitch chart ignoring cash is what
## makes it flatter-looking than the honest one at the same moment.
func _peak() -> float:
	var peak := _series_peak(_liabilities)
	if mode == Mode.HONEST:
		peak = maxf(peak, _series_peak(_cash))
		peak = maxf(peak, _series_peak(_pocket))
	return peak


func _series_peak(series: Array[float]) -> float:
	var peak := 1.0
	for value in series:
		peak = maxf(peak, value)
	return peak


func _draw_grid(plot: Rect2, peak: float) -> void:
	var font := get_theme_default_font()
	for row in GRID_ROWS + 1:
		var t := float(row) / float(GRID_ROWS)
		var y := plot.position.y + plot.size.y * t
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y),
			Color(1.0, 1.0, 1.0, 0.06), 1.0)
		var label := Fmt.money(peak * (1.0 - t))
		draw_string(font, Vector2(plot.position.x + 3.0, y - 3.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1.0, 1.0, 1.0, 0.28))


func _draw_series(plot: Rect2, series: Array[float], peak: float, color: Color,
		width: float) -> void:
	var points := _plot_points(plot, series, peak)
	if points.is_empty():
		return
	if points.size() >= 2:
		draw_polyline(points, color, width, true)
	# Head marker, so a one-week-old run still shows something.
	draw_circle(points[points.size() - 1], width + 1.5, color)


## Shaded area between a series and the baseline. Brochure furniture, so it is
## only ever asked for in `PITCH`.
func _draw_fill(plot: Rect2, series: Array[float], peak: float, color: Color) -> void:
	var points := _plot_points(plot, series, peak)
	if points.size() < 2:
		return
	var poly := points.duplicate()
	poly.append(Vector2(points[points.size() - 1].x, plot.end.y))
	poly.append(Vector2(points[0].x, plot.end.y))
	draw_colored_polygon(poly, Color(color, PITCH_FILL_ALPHA))


func _plot_points(plot: Rect2, series: Array[float], peak: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	if series.is_empty():
		return points
	points.resize(series.size())
	var span := float(maxi(series.size() - 1, 1))
	for i in series.size():
		var x := plot.position.x + plot.size.x * (float(i) / span)
		var y := plot.end.y - plot.size.y * clampf(series[i] / peak, 0.0, 1.0)
		points[i] = Vector2(x, y)
	return points


func _draw_legend(plot: Rect2) -> void:
	var font := get_theme_default_font()
	var entries: Array = [["total investor value", Palette.PITCH]] if mode == Mode.PITCH \
		else [
			["cash on hand", Palette.CASH],
			["owed to investors", Palette.LIABILITY],
			["your pocket", Palette.POCKET],
		]
	var x := plot.end.x
	for i in range(entries.size() - 1, -1, -1):
		var entry: Array = entries[i]
		var text: String = entry[0]
		var color: Color = entry[1]
		x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, Vector2(x, plot.position.y + 9.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)
		x -= 8.0
		draw_rect(Rect2(x, plot.position.y + 2.0, 6.0, 6.0), color)
		x -= 14.0
