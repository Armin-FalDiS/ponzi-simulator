class_name CastMember
extends Resource
## One named person in the visible roster. The cast *is* the instrument panel:
## who is posting, and how they sound, is the only readout the main view gets for
## anything living inside somebody else's head (DESIGN.md §3).
##
## A member carries **its own `join_week`**, deliberately. It cannot read one off
## a cohort: `SchemeState.consolidate()` folds cohorts together and rewrites the
## survivor's `join_week` to the group's earliest, and cohort indices shift as
## empty cohorts are dropped. The paperwork a person signed is fixed; the row it
## happens to be filed under is not.

## Who somebody is, which decides what they are able to post about. Investors
## hold a stake; the last three are onlookers with no money in.
enum Archetype {
	FAMILY,      ## knows where you live
	BELIEVER,    ## has told everyone at work
	SCEPTIC,     ## in, but reading the terms
	WHALE,       ## one signature, a lot of money
	INFLUENCER,  ## audience first, opinion second
	JOURNALIST,  ## the heat meter, wearing a byline
	CRANK,       ## right for the wrong reasons
}

const ARCHETYPE_LABELS: Array[String] = [
	"family", "believer", "sceptic", "whale", "influencer", "journalist", "crank",
]

@export var display_name: String = ""
@export var handle: String = ""
@export var archetype: Archetype = Archetype.BELIEVER

@export_group("Paperwork")
## Week this person signed. Owned here, never derived from a cohort — see above.
@export var join_week: int = 0
## The interval they signed up on. With `join_week` this reproduces their payout
## schedule exactly, without needing the cohort to still exist.
@export_range(1, 13, 1) var interval_weeks: int = 1
## Rate they were promised per interval. With `stake` this is their own cheque,
## which is the only sum they are entitled to quote in public.
@export var rate_per_interval: float = 0.04
## What they believe they are owed. Paperwork, so the UI may show it (DESIGN.md §3).
@export var stake: float = 0.0

@export_group("Presentation")
## Palette slot for the generated avatar. An index, not a `Color` — the sim never
## names colours; `Palette` decides what slot 3 looks like.
@export var avatar_tint: int = 0
## How this person feels, -1 (furious) to +1 (evangelical). Drives which post
## kinds they are willing to author.
@export_range(-1.0, 1.0, 0.01) var mood: float = 0.4
## Rough audience size. Scales the engagement counts their posts pull, which is
## the diegetic hype meter.
@export var reach: int = 40


## Onlookers have no money in the scheme and never appear on the payout calendar.
func is_investor() -> bool:
	return archetype != Archetype.JOURNALIST and archetype != Archetype.CRANK \
		and archetype != Archetype.INFLUENCER


## Whether this person's own money is scheduled to arrive this week. Derived from
## the paperwork they hold, so it survives any amount of cohort reshuffling.
func is_due(week: int) -> bool:
	if not is_investor():
		return false
	var elapsed := week - join_week
	return elapsed > 0 and elapsed % maxi(interval_weeks, 1) == 0


## Up to two letters for the generated avatar. No image assets anywhere in this
## project, so an avatar is initials on a coloured disc and nothing else.
func initials() -> String:
	var letters := ""
	for part in display_name.split(" ", false):
		if not part.is_empty():
			letters += part[0].to_upper()
		if letters.length() >= 2:
			break
	return letters if not letters.is_empty() else "?"


func archetype_label() -> String:
	return ARCHETYPE_LABELS[int(archetype)]
