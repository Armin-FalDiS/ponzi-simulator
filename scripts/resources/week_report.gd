class_name WeekReport
extends Resource
## Everything that happened in one simulated week, plus a snapshot of where the
## scheme stands afterwards. This is the payload for `EventBus.week_advanced`
## and `EventBus.run_ended` — the UI reads only this, never the sim.
##
## Two narrations travel side by side and they are not interchangeable:
##
##   * `posts` is what the **main view** shows. Named people, in their own words.
##   * `ledger_lines` is arithmetic narration, and `back_office.gd` is the only
##     thing allowed to read it. Putting a line like "paid $16K of $16K" in front
##     of the player hands them a number that is supposed to be inferred —
##     DESIGN.md §7.

## Colour intent for a line or a post. The UI owns the actual colours.
enum Tone {
	NEUTRAL,   ## bookkeeping
	MONEY_IN,  ## cash arriving
	MONEY_OUT, ## cash leaving
	GOOD,      ## went your way
	BAD,       ## went badly
	CRITICAL,  ## run-ending
}

## Discrete things that happened, for the feed composer to react to. Facts, not
## sentences: the sim decides *what* occurred, the content pool decides how
## anybody talks about it.
enum Beat {
	AUDIT_CLEAN,        ## the bought audit held up
	AUDIT_BACKFIRED,    ## somebody read the bought audit
	GALA,               ## testimonial evening
	LOBBY,              ## a regulator was taken to lunch
	PRESS_CALL,         ## a journalist wants comment
	WHALE,              ## one very large cheque
	FORUM_SPREADSHEET,  ## somebody did the maths in public
	RIVAL_COLLAPSE,     ## a comparable scheme died
	PAYOUT_FULL,        ## the week's bill was settled in cash, in full
	PAYOUT_DELAYED,     ## announced delay
	PAYOUT_PART,        ## announced part-payment
	PAYOUT_SHORT,       ## quietly came up short
	QUEUE_UNSERVED,     ## withdrawal queue went home unpaid
	NO_RECRUITS,        ## nobody signed
	WAVE_LANDED,        ## a telegraphed withdrawal wave actually arrived
	BUZZ_LANDED,        ## a telegraphed word-of-mouth spike actually arrived
	SIGNAL_FIZZLED,     ## something that was brewing came to nothing
}

@export var week: int = 0
@export var outcome: SchemeState.Outcome = SchemeState.Outcome.RUNNING

@export_group("Cash Movements")
@export var deposits: float = 0.0
@export var skimmed: float = 0.0
@export var payout_due: float = 0.0
@export var payout_paid: float = 0.0
## Part of `payout_due` that was carried in from a promise broken earlier.
@export var payout_carried: float = 0.0
## Part of this week's bill pushed onto next week, however it got pushed.
@export var payout_deferred: float = 0.0
@export var reinvested: float = 0.0
@export var withdrawn: float = 0.0
@export var marketing: float = 0.0
## One large cheque that arrived outside normal recruitment, if any.
@export var whale_deposit: float = 0.0

@export_group("People")
@export var recruits: int = 0
@export var withdrawers: int = 0
## How many cohorts came due this week. One is a step; five is a cliff.
@export var payout_cohorts: int = 0

@export_group("What's Brewing")
## Tells posted at the end of this week, each settling next week. The composer
## turns these into the only warning the player ever gets, so a request built
## from one is mandatory rather than best-effort (see `FeedComposer._plan`).
@export var signals_raised: Array[PendingSignal] = []
## Multipliers a landed signal applied this week, 1.0 when nothing landed. Kept
## on the report rather than as hidden sim state so a replay reproduces the week
## exactly, and so the back office can explain a bad week after the fact.
@export var withdrawal_surge: float = 1.0
@export var recruitment_surge: float = 1.0

@export_group("Calendar")
## Exact amount owed in each of the coming weeks, from paperwork that already
## exists. Knowable by definition, so the HUD is allowed to show all of it.
@export var forecast: Array[float] = []

@export_group("Snapshot")
@export var fund: float = 0.0
@export var principal: float = 0.0
@export var pocket: float = 0.0
@export var investors: int = 0
@export var trust: float = 0.0
@export var heat: float = 0.0
@export var hype: float = 0.0
@export var solvency: float = 1.0
## How loudly paid investors are currently showing off, 0–1. The recruitment
## engine of Pillar 3, and the only thing that silences the feed when you starve
## a payout.
@export var flex_reach: float = 0.0
## Weeks of cash left at the current burn. Negative means cash-flow positive.
@export var runway: float = -1.0
@export var take_home: float = 0.0

@export_group("Feed")
## What the main view shows. Named people, in their own words.
@export var posts: Array[FeedPost] = []
## Facts the composer reacted to. Kept on the report so a replay composes the
## same week the same way.
@export var beats: Array[int] = []

@export_group("Back Office")
## Arithmetic narration. `back_office.gd` consumes this; the main view must not.
@export var ledger_lines: Array[String] = []
@export var ledger_tones: Array[int] = []


## Weeks from now until the next bill lands, or -1 if the calendar is clear for
## as far as the forecast reaches.
func weeks_until_due() -> int:
	for i in forecast.size():
		if forecast[i] > 0.5:
			return i + 1
	return -1


func next_due_amount() -> float:
	var offset := weeks_until_due()
	return forecast[offset - 1] if offset > 0 else 0.0


func add_ledger_line(text: String, tone: Tone = Tone.NEUTRAL) -> void:
	ledger_lines.append(text)
	ledger_tones.append(int(tone))


func mark(beat: Beat) -> void:
	if not beats.has(int(beat)):
		beats.append(int(beat))


func has_beat(beat: Beat) -> bool:
	return beats.has(int(beat))


func snapshot(state: SchemeState) -> void:
	week = state.week
	outcome = state.outcome
	fund = state.fund
	principal = state.principal()
	pocket = state.pocket
	investors = state.investors()
	trust = state.trust
	heat = state.heat
	hype = state.hype
	solvency = state.solvency()
	flex_reach = state.flex_reach
	take_home = state.take_home

	var cash_out := payout_paid + withdrawn + marketing
	var cash_in := deposits - skimmed
	var burn := cash_out - cash_in
	runway = fund / burn if burn > 1.0 else -1.0
