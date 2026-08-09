class_name PendingSignal
extends Resource
## Something the sim has decided is *likely*, announced this week and settled the
## next. The whole of Pillar 5 ("nothing is certain, but the odds are legible")
## lives in this one small object.
##
## The contract with the player, in three parts:
##
##   1. **A band is a probability, not a mood.** `Band.EVERYONE` is 80%, always,
##      in every run. The wording the feed uses is chosen from the band, so a
##      player who learns "everyone's talking about it" has learned a number.
##   2. **Pressure picks the band; the band picks the odds.** The underlying
##      pressure never leaks through as a finer-grained probability, because a
##      probability the vocabulary cannot express is a probability the player
##      cannot read.
##   3. **The size of the hit is not on the card.** Effects are fixed constants on
##      `SchemeConfig`, identical every time, so the only thing a tell has to
##      communicate is *which* event and *how likely*. A varying magnitude would
##      make a correct read lose for reasons the player could never have seen —
##      the exact failure Pillar 5 forbids.
##
## Carried across weeks on `SchemeState.pending_signals`. Raised at the end of
## week N by `SchemeSim._raise_signals`, resolved at the top of week N+1 by
## `SchemeSim._resolve_signals`.

## What is brewing. One pending signal per kind at a time — a second rumour about
## the same thing is the same rumour.
enum Kind {
	WITHDRAWAL_WAVE,  ## a run on the withdrawal desk
	WORD_OF_MOUTH,    ## the scheme about to spread on its own
	JOURNALIST,       ## a byline circling
}

## Volume, which *is* the probability. The labels are the vocabulary from
## DESIGN.md §4.3 and the odds below are what they promise.
enum Band {
	ONE_PERSON,  ## "one person mentioned…"      — 25%
	A_FEW,       ## "a few people are asking…"   — 50%
	EVERYONE,    ## "everyone's talking about…"  — 80%
}

## The promise each band makes. Changing a number here rewrites the meaning of
## words the player has already learned, so treat it as a save-breaking change.
const BAND_ODDS: Array[float] = [0.25, 0.50, 0.80]

const KIND_LABELS: Array[String] = ["withdrawal wave", "word of mouth", "journalist"]
const BAND_LABELS: Array[String] = ["one person", "a few", "everyone"]

## Pressure below this is not worth mentioning, so no signal is raised and the
## event simply cannot happen. That is the point: with all three of these events
## routed through this class, **nothing in this group can arrive unannounced**
## (DESIGN.md §4.3).
## The cut points are set against the pressure *actually reachable* in play, not
## against a tidy 0–1 scale. Trust spends most of a run between 50 and 75 and
## heat rarely idles high, so thresholds spaced for the full range left the top
## two bands unreachable for two of the three kinds — a third of the tell
## vocabulary that no player would ever have read. Re-check these against the
## per-kind band mix in `balance_probe.gd` after any change to the pressure
## formulas: every one of the nine cells has to fire.
const PRESSURE_FLOOR: float = 0.20
const PRESSURE_A_FEW: float = 0.28
const PRESSURE_EVERYONE: float = 0.42

@export var kind: Kind = Kind.WITHDRAWAL_WAVE
@export var band: Band = Band.ONE_PERSON
## Week the tell was posted. The player saw it at the end of this week.
@export var raised_week: int = 0
## Week the coin actually gets flipped.
@export var resolve_week: int = 0


static func make(signal_kind: Kind, signal_band: Band, week: int) -> PendingSignal:
	var pending := PendingSignal.new()
	pending.kind = signal_kind
	pending.band = signal_band
	pending.raised_week = week
	pending.resolve_week = week + 1
	return pending


## Which band a pressure reading falls in, or -1 for "not worth saying out loud".
## Quantising here rather than carrying the raw pressure forward is deliberate —
## see the class comment.
static func band_for(pressure: float) -> int:
	if pressure >= PRESSURE_EVERYONE:
		return Band.EVERYONE
	if pressure >= PRESSURE_A_FEW:
		return Band.A_FEW
	if pressure >= PRESSURE_FLOOR:
		return Band.ONE_PERSON
	return -1


## The chance this lands, and the exact thing the wording promised.
func odds() -> float:
	return BAND_ODDS[int(band)]


func kind_label() -> String:
	return KIND_LABELS[int(kind)]


func band_label() -> String:
	return BAND_LABELS[int(band)]
