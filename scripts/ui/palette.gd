class_name Palette
extends RefCounted
## Single source of truth for colour. The simulation emits `WeekReport.Tone`
## values; only this file knows what a tone looks like.

const BACKDROP := Color("0b1020")
const PANEL := Color("141a2e")
const PANEL_EDGE := Color("263048")
const INK := Color("e2e8f5")
const INK_DIM := Color("7d8aa8")

const CASH := Color("4ade80")       ## money you actually have
const LIABILITY := Color("f87171")  ## money you owe
const POCKET := Color("fbbf24")     ## money you took
## The brochure line. Same series as `LIABILITY` — total investor value *is* what
## you owe — but the main view sells it rather than confessing it, so it gets a
## confident colour instead of an alarming one. The honest red is in the back
## office, on the same numbers.
const PITCH := Color("2dd4bf")
const TRUST := Color("38bdf8")
const HEAT := Color("fb7185")
const HYPE := Color("a78bfa")
const ALARM := Color("ef4444")

## Slightly lifted panel, for cards sitting inside a card.
const PANEL_SOFT := Color("1a2138")

## Generated avatars. Muted on purpose: a column of a dozen discs has to read as
## one surface, or it competes with the tone colours that actually mean
## something. The sim picks a slot; only this file knows what a slot looks like.
const AVATARS: Array[Color] = [
	Color("5b7fb4"), Color("7d6bb0"), Color("4f9d8a"), Color("b07d5b"),
	Color("a35f7a"), Color("6d8f4e"), Color("4d7f9d"), Color("9c7b4a"),
	Color("8a6ea0"), Color("5f9a6b"),
]

## Badge colour per `CastMember.Archetype`, in enum order. Journalists and cranks
## read as heat because that is exactly what their presence means.
const ARCHETYPES: Array[Color] = [
	POCKET, TRUST, Color("8e9ab8"), CASH, HYPE, HEAT, Color("c2705f"),
]


static func avatar(slot: int) -> Color:
	return AVATARS[posmod(slot, AVATARS.size())]


static func archetype(value: int) -> Color:
	return ARCHETYPES[posmod(value, ARCHETYPES.size())]


static func tone(value: int) -> Color:
	match value:
		WeekReport.Tone.MONEY_IN:
			return CASH
		WeekReport.Tone.MONEY_OUT:
			return POCKET
		WeekReport.Tone.GOOD:
			return TRUST
		WeekReport.Tone.BAD:
			return HEAT
		WeekReport.Tone.CRITICAL:
			return ALARM
		_:
			return INK_DIM


## Green when solvent, red as the gap between assets and promises widens.
static func solvency_color(ratio: float) -> Color:
	return LIABILITY.lerp(CASH, clampf(ratio, 0.0, 1.0))
