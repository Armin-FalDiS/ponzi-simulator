class_name PostCard
extends PanelContainer
## One post: avatar, name, handle, archetype badge, body, engagement.
##
## Built in code rather than as a scene because it is instantiated dozens of
## times a run and there is exactly one definition of what a post looks like.
## The tone arrives as a `WeekReport.Tone` and becomes a coloured edge — the
## post's sentiment is the trust readout, so it has to be legible at a glance
## without ever printing a trust value (DESIGN.md §4.2).

## Reposts, as a share of likes. A second number makes the engagement read as a
## platform rather than a stat, and it is just as unreliable as the first.
const REPOST_SHARE := 0.16


func _init(post: FeedPost) -> void:
	add_theme_stylebox_override("panel", ThemeFactory.post_box(Palette.tone(int(post.tone))))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	add_child(row)

	var avatar := AvatarDot.new()
	avatar.show_member(post.author)
	row.add_child(avatar)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)

	column.add_child(_byline(post.author))
	column.add_child(_body(post.body))
	column.add_child(_engagement(post.engagement))


## Name, handle, and what this person is — the badge is the heat readout when it
## says "journalist".
func _byline(author: CastMember) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.add_child(_label(author.display_name, "PostName"))
	line.add_child(_label(author.handle, "PostHandle"))

	var badge := _label(author.archetype_label(), "PostMeta")
	badge.add_theme_color_override("font_color",
		Palette.archetype(int(author.archetype)))
	badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(badge)
	return line


func _body(text: String) -> Control:
	var label := _label(text, "PostBody")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _engagement(likes: int) -> Control:
	return _label("♥ %s     ↻ %s" % [
		Fmt.grouped(likes), Fmt.grouped(maxi(int(likes * REPOST_SHARE), 1))],
		"PostMeta")


func _label(text: String, variation: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.focus_mode = Control.FOCUS_NONE
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
