class_name CalendarStrip
extends Control
## The obligation calendar: one column per coming week, exact to the dollar.
##
## Pillar 1 made spatial. Cohort schedules are deterministic, so every column here
## is paperwork rather than a forecast — the only assumption in the picture is
## that nobody else ever joins, and that assumption is what makes it frightening.
##
## A column is green while today's cash still covers the **running total** up to
## and including that week, and red once it doesn't. So the first red column is
## the week the scheme dies in if recruitment stopped today, and the wall of red
## after a quarterly cohort matures is the cliff you are supposed to run before.
## Per-week colouring was the first cut and it was worse: it flagged individual
## big weeks while saying nothing about whether you could actually get there.

const INSET := Vector2(2.0, 1.0)
## Room above the bars for the amount, and below them for the week number.
const AMOUNT_BAND := 13.0
const WEEK_BAND := 15.0
## Gap between adjacent columns, taken out of the column width.
const COLUMN_GAP := 7.0
## Height of the stub drawn for a week with nothing due, so a quiet week still
## reads as a week rather than as missing data.
const QUIET_STUB := 2.0
const CORNER := 2.0

var _forecast: Array[float] = []
var _week: int = 0
var _cash: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func show_calendar(week: int, forecast: Array[float], cash: float) -> void:
	_week = week
	_forecast = forecast
	_cash = cash
	queue_redraw()


func clear() -> void:
	_forecast = []
	queue_redraw()


## Index of the first week the running bill outgrows `cash`, or -1 if the cash on
## hand covers every week shown. Static because `main.gd` writes the sentence
## version of this next to the strip's title, and the two must never disagree.
static func dry_index(forecast: Array[float], cash: float) -> int:
	var running := 0.0
	for i in forecast.size():
		running += forecast[i]
		if running > cash:
			return i
	return -1


## Offset (1-based, in weeks from now) of the next week with a bill on it, or -1.
static func next_due_offset(forecast: Array[float]) -> int:
	for i in forecast.size():
		if forecast[i] > 0.5:
			return i + 1
	return -1


func _draw() -> void:
	var font := get_theme_default_font()
	if _forecast.is_empty():
		draw_string(font, Vector2(2.0, size.y * 0.6), "nothing scheduled",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.INK_DIM)
		return

	var full := Rect2(INSET, size - INSET * 2.0)
	var bars := Rect2(full.position + Vector2(0.0, AMOUNT_BAND),
		Vector2(full.size.x, maxf(full.size.y - AMOUNT_BAND - WEEK_BAND, 8.0)))
	if bars.size.x <= 8.0:
		return

	var count := _forecast.size()
	var column := bars.size.x / float(count)
	var bar_width := maxf(column - COLUMN_GAP, 3.0)
	var peak := 1.0
	for amount in _forecast:
		peak = maxf(peak, amount)

	draw_line(Vector2(bars.position.x, bars.end.y), Vector2(bars.end.x, bars.end.y),
		Color(1.0, 1.0, 1.0, 0.10), 1.0)

	var dry := dry_index(_forecast, _cash)
	var next_due := next_due_offset(_forecast)
	for i in count:
		var amount := _forecast[i]
		var covered := dry < 0 or i < dry
		var color := Palette.CASH if covered else Palette.LIABILITY
		var left := bars.position.x + column * float(i) + (column - bar_width) * 0.5
		_draw_column(font, Rect2(left, bars.position.y, bar_width, bars.size.y),
			amount, peak, color, i + 1 == next_due)
		_draw_week_label(font, left, bar_width, bars.end.y + WEEK_BAND - 3.0,
			i + 1, i + 1 == next_due, covered)


func _draw_column(font: Font, cell: Rect2, amount: float, peak: float, color: Color,
		is_next: bool) -> void:
	if amount <= 0.5:
		# A quiet week: a dim stub on the baseline, and no figure to read.
		draw_rect(Rect2(cell.position.x, cell.end.y - QUIET_STUB, cell.size.x, QUIET_STUB),
			Color(Palette.INK_DIM, 0.45))
		return

	var height := maxf(cell.size.y * (amount / peak), QUIET_STUB + 1.0)
	var bar := Rect2(cell.position.x, cell.end.y - height, cell.size.x, height)
	draw_rect(bar, Color(color, 0.85 if is_next else 0.55))
	# The next bill is the one you are actually being asked for, so it gets an
	# outline as well as the brighter fill.
	if is_next:
		draw_rect(bar, color, false, 1.0)

	var text := Fmt.money(amount)
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	draw_string(font, Vector2(cell.position.x + (cell.size.x - text_width) * 0.5,
		cell.position.y - 3.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
		Color(color, 0.95 if is_next else 0.7))


func _draw_week_label(font: Font, left: float, width: float, baseline: float,
		offset: int, is_next: bool, covered: bool) -> void:
	var text := "wk %d" % (_week + offset)
	var color := Palette.INK_DIM
	if is_next:
		color = Palette.INK
	elif not covered:
		color = Color(Palette.LIABILITY, 0.75)
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	draw_string(font, Vector2(left + (width - text_width) * 0.5, baseline), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9, color)
