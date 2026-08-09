@icon("res://icon.svg")
class_name SchemeConfig
extends Resource
## Every balance number in the game. Nothing here is referenced by name outside
## `SchemeSim`, so the whole feel of the game is tunable from the Inspector
## without opening a script.

@export_group("Opening Position")
@export var start_investors: int = 5
@export var start_fund: float = 20000.0
@export_range(0.0, 100.0, 1.0) var start_trust: float = 65.0
@export_range(0.0, 100.0, 1.0) var start_heat: float = 2.0
@export_range(0.0, 100.0, 1.0) var start_hype: float = 15.0
## Weekly-equivalent return the scheme opens on. The interval only decides when
## it lands, never how much it is worth.
@export_range(0.01, 0.15, 0.005) var start_promised_return: float = 0.04
@export_range(1, 13, 1) var start_interval_weeks: int = 1
@export_range(0.0, 0.5, 0.01) var start_skim_rate: float = 0.10

@export_group("Recruitment")
## Average cheque a new mark writes on joining.
@export var avg_deposit: float = 4000.0
@export_range(0.0, 1.0, 0.01) var deposit_variance: float = 0.35
## Recruits per week that arrive regardless of how big the scheme already is.
@export var walk_in_investors: float = 2.0
## Recruits per week contributed by each existing investor. This term is what
## makes the scheme grow exponentially — and what makes it die when it stalls.
@export_range(0.0, 1.0, 0.01) var referral_rate: float = 0.22
@export var appeal_base: float = 0.0
@export var appeal_from_return: float = 1.10
@export var appeal_from_hype: float = 0.35
@export var appeal_from_trust: float = 0.32
@export var appeal_from_heat: float = 0.50
## Appeal lost by making people wait, scaled by (1 - 1/interval): zero for weekly
## terms, nearly all of it for quarterly. Marks want to see cash soon, whatever
## the yield says. Weekly is the reference case so this dial never silently
## rescales the rest of the appeal curve.
@export var appeal_from_impatience: float = 0.82
## The promised return that scores a full 1.0 on the "greed" appeal term.
@export_range(0.01, 0.5, 0.005) var reference_return: float = 0.10
## Ceiling on that term. Past this, a bigger number stops pulling a bigger crowd
## — but you still owe every point of it. This is what makes over-promising a
## trap rather than a dial, so raising it un-teaches the whole lesson.
@export_range(0.5, 3.0, 0.05) var appeal_greed_ceiling: float = 1.05

@export_group("Hype")
@export_range(0.0, 1.0, 0.01) var hype_decay: float = 0.14
@export var hype_per_1k_marketing: float = 6.0

@export_group("The Flex Loop")
## Appeal bought by investors publicly showing off the money you paid them.
## Pillar 3: paying out *is* your marketing, so starving a payout has to cost
## recruitment and not just trust.
@export var appeal_from_flex: float = 0.19
## Reach gained per interval-week actually settled in cash. Multiplied by the
## interval serviced, so a quarterly cheque buys as much showing-off as thirteen
## weekly ones — otherwise long terms would be punished twice over.
@export_range(0.0, 1.0, 0.01) var flex_recover: float = 0.30
## Share of the showing-off that evaporates when a bill is broken in full. Two
## starved weeks and the feed has nothing good left in it.
@export_range(0.0, 1.0, 0.01) var flex_collapse: float = 0.62
## Weekly drift down when nothing was due. Slow: people keep posting about the
## cheque that already cleared.
@export_range(0.0, 0.5, 0.01) var flex_idle_decay: float = 0.04
## Flex posts a week at full reach. The visible half of the same number.
@export_range(0, 5, 1) var flex_posts_max: int = 3

@export_group("Tells and Signals")
## Withdrawal rate multiplier on the week a wave lands. Fixed, never rolled: the
## tell announces the odds and the odds are the whole message, so the size of the
## hit has to be something the player can know in advance (DESIGN.md §4.3).
@export_range(1.0, 8.0, 0.1) var wave_multiplier: float = 2.0
## Recruitment multiplier on the week a word-of-mouth spike lands. Marketing is
## resolved before recruitment, so spending into a signalled spike amplifies it —
## that is the reward for reading the precursor.
@export_range(1.0, 5.0, 0.1) var buzz_multiplier: float = 1.9
## Heat and hype a byline drops when the journalist signal lands. Bad press is
## still press, so it moves both.
@export var journalist_heat: float = 9.0
@export var journalist_hype: float = 7.0

@export_subgroup("Pressure")
## Everything below feeds `PendingSignal.band_for()`. Raising a coefficient makes
## that signal both more frequent *and* louder when it appears, because pressure
## picks the band — there is no separate frequency dial by design.
##
## The bands start at 0.20, so a healthy scheme wants to sit *below* that on the
## bad signals and just above it on the good one. Tuned against the census in
## `balance_probe.gd`: anything firing more than about a quarter of weeks has
## stopped being an event and become a second progress bar.
@export var wave_from_distrust: float = 0.10
@export var wave_per_missed_payout: float = 0.30
@export var wave_from_insolvency: float = 0.16
## Word-of-mouth pressure is a **product**, not a sum: a spike needs an audience,
## people visibly being paid, and enthusiasm — and missing any one of the three
## kills it. Summing them let a scheme with dead hype still buzz on trust alone,
## and compressed the range so hard that the loud band was arithmetically
## unreachable and a third of the tell vocabulary could never be printed.
@export var buzz_scale: float = 0.45
## Floor under the flex term, so a young scheme that has not owed anybody a
## cheque yet is not mute.
@export_range(0.0, 1.0, 0.05) var buzz_flex_floor: float = 0.40
## Exponent on trust. Above 1.0 enthusiasm becomes non-linear: people who are
## merely satisfied do not tell anybody, and only the delighted recruit.
##
## This is the *spread* dial, not a strength dial — `buzz_scale` is set against
## it to hold the average firing rate steady. Raising both together is what makes
## the loud band reachable at all: trust drifts downward at any real promised
## return, so a gentler curve leaves a well-run scheme and a mediocre one sounding
## exactly alike.
@export_range(1.0, 3.0, 0.05) var buzz_trust_curve: float = 2.0
## Squared, so heat barely registers until it is dangerous and then the press
## warning gets loud fast. A linear term left a scheme at 90 heat getting the
## same faint mention as one at 45, which is the one moment the warning has to
## be unmissable.
@export var byline_from_heat: float = 0.60
## Spread on every pressure reading before it is banded. Without it the same
## scheme state would produce the same tell every week, and the vocabulary would
## degenerate into a second progress bar for trust.
##
## **Added, not multiplied.** A multiplicative spread cannot lift a quiet week
## into a loud band no matter how wide it is, so the top third of the vocabulary
## was unreachable by construction. Keep this strictly below
## `PendingSignal.PRESSURE_FLOOR`, or a scheme with nothing wrong with it starts
## receiving warnings out of thin air.
@export_range(0.0, 0.19, 0.01) var pressure_noise: float = 0.18

@export_group("The Cast")
## Visible roster size. Everyone else in the scheme is aggregate.
@export_range(2, 24, 1) var cast_size: int = 11
## New faces admitted per week when recruitment is running.
@export_range(0, 4, 1) var cast_intake: int = 2
## Heat above which a journalist takes up a seat in the roster, and below which
## they lose interest. Their byline in your mentions *is* the heat readout.
@export_range(0.0, 100.0, 1.0) var cast_journalist_heat: float = 45.0
## Hype above which an influencer shows up.
@export_range(0.0, 100.0, 1.0) var cast_influencer_hype: float = 40.0

@export_group("Payouts")
## Ceiling on the share of promised returns investors leave in the fund instead
## of taking as cash. Scaled by trust. Reinvested money never leaves — but it
## does increase what you owe.
@export_range(0.0, 1.0, 0.01) var reinvest_ceiling: float = 0.60
## Share of a due payout that PART_PAY actually hands over.
@export_range(0.0, 1.0, 0.05) var part_pay_share: float = 0.50
## How many weeks of the obligation calendar the HUD is given.
@export_range(1, 24, 1) var forecast_weeks: int = 8

@export_group("Withdrawals")
@export_range(0.0, 1.0, 0.01) var withdraw_base: float = 0.02
@export_range(0.0, 1.0, 0.01) var withdraw_from_distrust: float = 0.10
@export_range(0.0, 1.0, 0.01) var withdraw_per_missed_payout: float = 0.12

@export_group("Trust")
## Awarded on a payout week, multiplied by the interval that was serviced, so
## paying quarterly is not four times less reassuring than paying weekly.
@export var trust_on_time_bonus: float = 2.5
@export var trust_missed_penalty: float = 26.0
## Announcing a delay is a public admission. Worse than quietly coming up short.
@export var trust_delay_penalty: float = 34.0
## Part-paying is the same admission, softened by the fact that money did move.
@export var trust_part_pay_penalty: float = 17.0
## Per-week trust bleed, multiplied by the promised return. Promising 15% a week
## makes people suspicious all by itself.
@export var trust_skepticism: float = 34.0
@export var trust_from_heat: float = 0.03

@export_group("Heat")
@export var heat_base: float = 0.30
@export var heat_from_size: float = 0.55
@export var heat_from_promise: float = 15.0
@export var heat_per_complaint: float = 3.5
@export var heat_decay: float = 0.35
## Heat you can never scrub off, scaled by scheme size. Past a certain size the
## regulator is simply aware of you and no amount of lunch fixes that.
@export var heat_floor_scale: float = 12.0
@export var heat_floor_reference: float = 500000.0
## Each bribe is less effective and more expensive than the last.
@export_range(0.0, 2.0, 0.05) var lobby_diminish: float = 0.60

@export_group("Action Costs")
@export var fake_audit_cost: float = 12000.0
@export_range(0.0, 0.2, 0.005) var fake_audit_cost_scale: float = 0.020
@export var gala_cost: float = 9000.0
@export_range(0.0, 0.2, 0.005) var gala_cost_scale: float = 0.015
@export var lobby_cost: float = 25000.0
@export_range(0.0, 0.2, 0.005) var lobby_cost_scale: float = 0.040

@export_group("Failure & Payout")
## How many payout shortfalls the scheme survives before investors bolt.
@export var missed_payouts_allowed: int = 2
## Share of a withdrawal queue you must cover to avoid an outright bank run.
## Below this, the scheme unravels the same week.
@export_range(0.0, 1.0, 0.05) var bank_run_threshold: float = 0.50
## Share of the pocket you keep when the scheme collapses under you.
@export_range(0.0, 1.0, 0.01) var collapse_pocket_keep: float = 0.35
## Share of the pocket lost when you exit voluntarily, scaled by heat.
@export_range(0.0, 1.0, 0.01) var exit_heat_penalty: float = 0.50

@export_group("Player Lever Ranges")
@export_range(0.005, 0.5, 0.005) var max_promised_return: float = 0.15
@export_range(0.0, 1.0, 0.01) var max_skim_rate: float = 0.50
@export var max_marketing: float = 25000.0
