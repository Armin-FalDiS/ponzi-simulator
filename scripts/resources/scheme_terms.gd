class_name SchemeTerms
extends Resource
## The offer currently on the table. Whoever signs this week is bound to a copy
## of it forever; changing it only ever affects the next cohort.
##
## The player thinks in **weekly-equivalent return** — that is what a mark
## compares between schemes — and picks an interval separately. The interval is
## therefore a pure timing dial: same yield promised, different week it lands.

## Payout intervals offered, in weeks.
const INTERVALS: Array[int] = [1, 2, 4, 13]
const INTERVAL_LABELS: Array[String] = ["Weekly", "Fortnightly", "Monthly", "Quarterly"]

@export_range(1, 13, 1) var interval_weeks: int = 1
@export var rate_per_interval: float = 0.04


## What the promise is worth per week. Cohorts are compared on this, never on
## the headline per-payout rate.
func weekly_rate() -> float:
	return rate_per_interval / float(maxi(interval_weeks, 1))


## Sets the per-interval rate from a weekly-equivalent promise, so moving the
## interval dial never silently changes how generous the offer is.
func set_weekly_rate(weekly: float) -> void:
	rate_per_interval = weekly * float(maxi(interval_weeks, 1))


func interval_label() -> String:
	var index := INTERVALS.find(interval_weeks)
	return INTERVAL_LABELS[index] if index >= 0 else "every %d wks" % interval_weeks


func copy_terms() -> SchemeTerms:
	var copy := SchemeTerms.new()
	copy.interval_weeks = interval_weeks
	copy.rate_per_interval = rate_per_interval
	return copy
