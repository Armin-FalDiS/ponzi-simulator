class_name PostTemplateSet
extends Resource
## A bundle of interchangeable post bodies for one kind, written in one voice.
##
## Content is data, not code (DESIGN.md §6). A set says *who* may say this and
## *when they are in the mood to*; the composer picks a body at random from the
## bag and fills the slots. Adding voices means adding `.tres` files, never
## touching `feed_composer.gd`.
##
## Bodies may use these slots — anything unmatched is left alone:
##   `{name}` `{handle}` `{amount}` `{count}` `{weeks}` `{item}` `{week}`

@export var kind: FeedPost.Kind = FeedPost.Kind.CHATTER
@export var tone: WeekReport.Tone = WeekReport.Tone.NEUTRAL

@export_group("Tells")
## Only read when `kind` is TELL. The pair below is a promise to the player:
## every body in this file must sound like `band`, because the band is the odds
## and the wording is the only place the odds are ever written down. A loud
## sentence filed under ONE_PERSON is not a typo, it is a lie (DESIGN.md §4.3).
@export var signal_kind: PendingSignal.Kind = PendingSignal.Kind.WITHDRAWAL_WAVE
@export var band: PendingSignal.Band = PendingSignal.Band.ONE_PERSON

@export_group("Casting")
## Which archetypes are willing to say this. Bit order matches
## `CastMember.Archetype`.
@export_flags("family", "believer", "sceptic", "whale", "influencer",
	"journalist", "crank") var author_mask: int = 127
## Mood window the author must sit inside. A flex post needs somebody delighted;
## a doubt post needs somebody who has stopped being delighted.
@export_range(-1.0, 1.0, 0.05) var min_mood: float = -1.0
@export_range(-1.0, 1.0, 0.05) var max_mood: float = 1.0

@export_group("Reach")
## Multiplies the engagement this kind pulls. A collapse post travels; a payout
## receipt mostly does not.
@export_range(0.0, 8.0, 0.05) var engagement_scale: float = 1.0

@export_group("Content")
@export var bodies: PackedStringArray = PackedStringArray()


func accepts(member: CastMember) -> bool:
	return author_mask & (1 << int(member.archetype)) != 0 \
		and member.mood >= min_mood and member.mood <= max_mood


## Whether this set is the right vocabulary for a given pending signal. Non-tell
## sets never match, so a tell can only ever be worded by a file that declared
## which band it speaks in.
func speaks_for(pending: PendingSignal) -> bool:
	return kind == FeedPost.Kind.TELL \
		and signal_kind == pending.kind and band == pending.band
