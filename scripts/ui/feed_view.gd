class_name FeedView
extends ScrollContainer
## The right-hand column: the scheme as its investors see it.
##
## Replaces the accounting ledger, and that swap is the whole of Pillar 2. What
## used to be "paid $16K of $16K owed" is now a named person saying the cheque
## cleared, or not saying it. Nothing in this file knows any game rules; it turns
## `FeedPost` resources into cards.
##
## Newest at the top, like an actual feed. That also means a new post always
## appears in the same place, so nothing scrolls out from under the player —
## DESIGN.md §7 rules out autoplay that outruns reading.

## Cards kept before the oldest are dropped. A long autoplay run would otherwise
## grow the tree without bound.
const MAX_CARDS := 90

var _column: VBoxContainer


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = false
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 6)
	add_child(_column)


func reset(state: SchemeState) -> void:
	for child in _column.get_children():
		child.queue_free()
		_column.remove_child(child)
	_add(_rule("the scheme opens"), 0)
	_add(_note("%d friends-of-friends are in for %s, at %s %s." % [
		state.investors(), Fmt.money(state.principal()),
		Fmt.percent(state.current_terms.rate_per_interval),
		state.current_terms.interval_label().to_lower()]), 1)


## Inserts the week at the top, keeping the composer's order readable downwards:
## the post the player most needs to notice ends up directly under the rule.
func write_week(report: WeekReport) -> void:
	var at := 0
	_add(_rule("week %d" % report.week), at)
	at += 1
	for post in report.posts:
		_add(PostCard.new(post), at)
		at += 1
	if report.posts.is_empty():
		_add(_note("nobody posted."), at)
	_trim()
	scroll_vertical = 0


func _add(card: Control, index: int) -> void:
	_column.add_child(card)
	_column.move_child(card, index)


## Thin rule between weeks. Not a post — it is the only thing in this column the
## player is meant to read as coming from outside the fiction.
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


func _note(text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = "PostHandle"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _trim() -> void:
	while _column.get_child_count() > MAX_CARDS:
		var oldest := _column.get_child(_column.get_child_count() - 1)
		_column.remove_child(oldest)
		oldest.queue_free()
