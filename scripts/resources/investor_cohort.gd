class_name InvestorCohort
extends Resource
## One batch of investors holding identical paperwork.
##
## The cohort is the unit of obligation. It owes `principal * rate_per_interval`
## every `interval_weeks` weeks, forever, and **changing the scheme's terms never
## touches it** — old promises are legacy debt you are stuck servicing. Early
## greed is not a bad week, it is a permanent line item.

@export var join_week: int = 0
@export_range(1, 13, 1) var interval_weeks: int = 1
## Paid per interval, not per week. A monthly cohort at 16% is a weekly cohort
## at 4% that lands as one cliff instead of four steps.
@export var rate_per_interval: float = 0.04
@export var principal: float = 0.0
@export var head_count: int = 0


func _init(week: int = 0, interval: int = 1, rate: float = 0.0,
		stake: float = 0.0, heads: int = 0) -> void:
	join_week = week
	interval_weeks = maxi(interval, 1)
	rate_per_interval = rate
	principal = stake
	head_count = heads


## Due on every interval boundary *after* the join week. A cohort never collects
## in the week it signs — the first cheque is one full interval away, which is
## also what makes joining cheap for you and the float real.
func is_due(week: int) -> bool:
	var elapsed := week - join_week
	return elapsed > 0 and elapsed % interval_weeks == 0


func amount_due() -> float:
	return principal * rate_per_interval


## Two cohorts with the same terms sitting at the same point in the payout cycle
## are indistinguishable to the simulation, so they can be folded together. This
## is what keeps the book at (terms in use x interval) entries instead of one
## per week forever — see `SchemeState.consolidate()`.
func schedule_key() -> String:
	return "%d:%d:%d" % [
		interval_weeks,
		roundi(rate_per_interval * 1000000.0),
		posmod(join_week, interval_weeks),
	]
