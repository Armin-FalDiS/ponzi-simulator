class_name SchemeState
extends Resource
## The mutable state of one run. Pure data plus derived getters — no per-frame
## logic and no scene-tree access, so it can be saved, diffed, or replayed.
##
## The book of investors is a list of `InvestorCohort`, not a headcount and a
## balance. `investors()` and `principal()` are sums over that list, so they
## cannot drift out of step with the payout calendar the way two parallel
## numbers would.

enum Outcome {
	RUNNING,     ## still going
	EXIT_SCAM,   ## player pulled the ripcord
	BANK_RUN,    ## withdrawal demand exceeded the cash on hand
	DEFAULTED,   ## too many missed payouts, investors bolted
	BUSTED,      ## the regulator arrived
}

## How the player intends to handle this week's bill. Reset every tick.
enum PayoutOrder {
	FULL,   ## honour it
	PART,   ## pay a slice, roll the rest forward
	DELAY,  ## pay none of it, roll all of it forward
}

@export var week: int = 0
@export var outcome: Outcome = Outcome.RUNNING

@export_group("Money")
## Actual cash sitting in the scheme.
@export var fund: float = 0.0
## Money you have taken out. The only number that scores.
@export var pocket: float = 0.0

@export_group("The Book")
## Every promise you have ever made, grouped by paperwork.
@export var cohorts: Array[InvestorCohort] = []
## The offer new investors sign this week. Existing cohorts ignore it.
@export var current_terms: SchemeTerms
## Payouts you broke a commitment on. They do not go away; they land next week
## on top of whatever was already scheduled.
@export var deferred_payout: float = 0.0

@export_group("The Cast")
## The visible roster. Data only — `CastDirector` owns every rule about who
## joins it and who ages out of it.
@export var cast: Array[CastMember] = []

@export_group("What's Brewing")
## Events rolled as likely and announced, waiting to be settled next week. At
## most one per kind. `SchemeSim` owns every rule about them; this is the shelf
## they sit on between the tell and the coin flip.
@export var pending_signals: Array[PendingSignal] = []

@export_group("Mood")
@export_range(0.0, 100.0) var trust: float = 0.0
@export_range(0.0, 100.0) var heat: float = 0.0
@export_range(0.0, 100.0) var hype: float = 0.0
## How loudly the people you paid are showing off, 0–1. Set when the bill is
## settled and decayed when it is not, so it is *this* week's payouts feeding
## *next* week's recruitment — Pillar 3, and the reason starving a payout is
## expensive rather than free.
@export_range(0.0, 1.0) var flex_reach: float = 0.0

@export_group("Player Levers")
@export var skim_rate: float = 0.10
@export var marketing: float = 0.0
@export var payout_order: PayoutOrder = PayoutOrder.FULL

@export_group("Run Bookkeeping")
@export var missed_payouts: int = 0
## Bribes paid so far. Each one buys less than the last.
@export var lobby_count: int = 0
## Cash you actually walk away with once the run resolves.
@export var take_home: float = 0.0

@export_group("History")
@export var fund_history: Array[float] = []
@export var liability_history: Array[float] = []
@export var pocket_history: Array[float] = []


#region Derived totals

## What investors believe they are owed. This is the lie, in dollars.
func principal() -> float:
	var total := 0.0
	for cohort in cohorts:
		total += cohort.principal
	return total


func investors() -> int:
	var total := 0
	for cohort in cohorts:
		total += cohort.head_count
	return total


## Fraction of promised liabilities actually backed by cash. Starts near 1.0 and
## only ever goes one direction.
func solvency() -> float:
	var owed := principal()
	if owed <= 0.0:
		return 1.0
	return clampf(fund / owed, 0.0, 4.0)


## What one average investor believes their stake is worth.
func avg_stake() -> float:
	return principal() / float(maxi(investors(), 1))


func is_running() -> bool:
	return outcome == Outcome.RUNNING


## The pending signal of this kind, or null. A lookup over own data, not a rule:
## what raises one and what it does when it lands both live in `SchemeSim`.
func signal_for(kind: PendingSignal.Kind) -> PendingSignal:
	for pending in pending_signals:
		if pending.kind == kind:
			return pending
	return null

#endregion


#region The book

## Signs a new batch of investors onto a copy of the given terms. The copy
## matters: it is what makes a promise permanent instead of retroactive.
func open_cohort(join_week: int, terms: SchemeTerms, stake: float, heads: int) -> InvestorCohort:
	var cohort := InvestorCohort.new(join_week, terms.interval_weeks,
		terms.rate_per_interval, stake, heads)
	cohorts.append(cohort)
	return cohort


## Pulls cash and people out of the book pro rata. A withdrawal queue does not
## care which cohort you are in, so the damage spreads by stake size.
func take_from_cohorts(amount: float, heads: int) -> void:
	var total := principal()
	if total <= 0.0:
		return

	var removed := 0
	for cohort in cohorts:
		var share := cohort.principal / total
		cohort.principal = maxf(cohort.principal - amount * share, 0.0)
		var take := mini(int(floorf(float(heads) * share)), cohort.head_count)
		cohort.head_count -= take
		removed += take

	# Flooring above always undershoots. Hand the remainder out one at a time so
	# the headcount matches the queue that actually left.
	var leftover := heads - removed
	while leftover > 0:
		var moved := false
		for cohort in cohorts:
			if leftover <= 0:
				break
			if cohort.head_count > 0:
				cohort.head_count -= 1
				leftover -= 1
				moved = true
		if not moved:
			break


## Folds cohorts that share terms and a position in the payout cycle, and drops
## the ones nobody is left in. Called once at the end of each week, *after*
## payouts — a cohort signed this week must never be folded into a group that
## already collected today.
func consolidate() -> void:
	var merged: Array[InvestorCohort] = []
	var by_schedule: Dictionary[String, int] = {}

	for cohort in cohorts:
		if cohort.head_count <= 0 and cohort.principal < 1.0:
			continue
		var key := cohort.schedule_key()
		if not by_schedule.has(key):
			by_schedule[key] = merged.size()
			merged.append(cohort)
			continue
		var target := merged[by_schedule[key]]
		target.principal += cohort.principal
		target.head_count += cohort.head_count
		target.join_week = mini(target.join_week, cohort.join_week)

	cohorts = merged

#endregion


func record_history() -> void:
	fund_history.append(fund)
	liability_history.append(principal())
	pocket_history.append(pocket)
