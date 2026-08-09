class_name FeedComposer
extends RefCounted
## Turns one week of facts into one week of posts.
##
## The composer decides *that* somebody talks and *who*; the content pool decides
## what they say. It never writes a sentence, and it never reads a number out
## loud that the information contract says must be inferred — a post carries
## sentiment, authorship and engagement, and those three are the whole readout
## for trust, heat and hype (DESIGN.md §3, §4.2).
##
## Bodies are drawn from a shuffle bag per template set, so a run works through
## the entire vocabulary of a kind before repeating any of it.

const POOL_PATH := "res://resources/feed/pool.tres"

## Most posts one week may produce. Beyond this the feed stops being readable and
## starts being a log, which is the thing it replaced.
const MAX_POSTS := 7
## Fewest, so a quiet week still looks like a place where people exist.
const MIN_POSTS := 2

## Slot fill for flex posts. No image assets, so a luxury is a noun.
const LUXURIES: Array[String] = [
	"a boat", "the kitchen", "a second car", "my dad's mortgage",
	"a watch I cannot justify", "the loft conversion", "a week in Sardinia",
	"business class, both ways", "the ring", "a horse, genuinely a horse",
	"the van the business needed", "school fees, a year up front",
]


## One post the week has earned. Which template set and which person fills it is
## decided later — this only says what needs saying.
class Request extends RefCounted:
	var kind: FeedPost.Kind = FeedPost.Kind.CHATTER
	var slots: Dictionary[String, String] = {}
	## Restrict authorship to people whose own money was on this week's calendar.
	## A payout post from somebody who was not due reads as a lie.
	var needs_due: bool = false
	## Restrict authorship to people who signed this week. Same reason: the person
	## announcing they have just joined has to be somebody who has just joined.
	var needs_new: bool = false
	## Restrict authorship to people who have collected at least once. Nobody
	## flexes about a cheque that has not arrived yet.
	var needs_paid: bool = false
	## The signal this post is the precursor to, if any. Narrows the template
	## search to the one file that speaks for that kind *and* that band.
	var pending: PendingSignal = null
	## Refuse to be dropped. Casting normally fails softly — a week with nobody
	## angry enough to complain simply has no complaint in it — but a tell that
	## fails to find an author is an event arriving unannounced, which DESIGN.md
	## §4.3 rules out. Mandatory requests get a second pass with the mood and
	## archetype filters removed.
	var mandatory: bool = false


var _config: SchemeConfig
var _rng: RandomNumberGenerator
var _sets: Array[PostTemplateSet] = []
## Remaining body indices per set, parallel to `_sets`. Refilled when emptied.
var _bags: Array[PackedInt32Array] = []
## Kind -> indices into `_sets`.
var _by_kind: Dictionary[int, PackedInt32Array] = {}


func _init(scheme_config: SchemeConfig, rng: RandomNumberGenerator,
		content: FeedContent = null) -> void:
	_config = scheme_config
	_rng = rng
	_index(content if content != null else load(POOL_PATH) as FeedContent)


func _index(content: FeedContent) -> void:
	if content == null:
		push_error("FeedComposer: content pool missing at %s" % POOL_PATH)
		return
	for template in content.sets:
		if template == null or template.bodies.is_empty():
			continue
		var slot := _sets.size()
		_sets.append(template)
		_bags.append(PackedInt32Array())
		var key := int(template.kind)
		var indices: PackedInt32Array = _by_kind.get(key, PackedInt32Array())
		indices.append(slot)
		_by_kind[key] = indices


#region Composition

func compose(state: SchemeState, report: WeekReport) -> Array[FeedPost]:
	var posts: Array[FeedPost] = []
	if _sets.is_empty():
		return posts

	var spoken: Array[CastMember] = []
	for request in _plan(state, report):
		if posts.size() >= MAX_POSTS:
			break
		var post := _write(state, report, request, spoken)
		if post != null:
			posts.append(post)
			spoken.append(post.author)
	return posts


## What this week has earned somebody saying, most telling first. Order is
## priority, not chronology: when a week produces more than the feed can hold,
## the thing the player most needs to notice survives the cut.
func _plan(state: SchemeState, report: WeekReport) -> Array[Request]:
	var plan: Array[Request] = []

	if report.outcome != SchemeState.Outcome.RUNNING:
		var ending: Dictionary[String, String] = {
			"count": Fmt.grouped(report.investors),
			"week": str(report.week),
		}
		plan.append(_request(FeedPost.Kind.COLLAPSE, ending))
		plan.append(_request(FeedPost.Kind.COLLAPSE, ending))
		return plan

	# Tells go first, ahead even of a broken promise. Everything else in this
	# function reports a week that has already happened and that the player can
	# reconstruct from the back office; a precursor is the only post that is about
	# next week, and it is worthless the moment it can be crowded out.
	for pending in report.signals_raised:
		plan.append(_tell_request(pending))

	_plan_payouts(plan, state, report)

	if report.has_beat(WeekReport.Beat.PRESS_CALL) \
			or _rng.randf() < state.heat / 260.0:
		plan.append(_request(FeedPost.Kind.PRESS, {}))

	# The engine. How many people are visibly enjoying your money is the same
	# number that recruits for you next week, so the feed going quiet and the
	# recruitment drying up are one event with two faces.
	var flexes := _round_stochastic(state.flex_reach * float(_config.flex_posts_max))
	for _i in flexes:
		plan.append(_request(FeedPost.Kind.FLEX,
			{"item": LUXURIES[_rng.randi() % LUXURIES.size()]}, false, false, true))

	if report.has_beat(WeekReport.Beat.FORUM_SPREADSHEET) \
			or report.has_beat(WeekReport.Beat.RIVAL_COLLAPSE) \
			or _rng.randf() < (65.0 - state.trust) / 160.0:
		plan.append(_request(FeedPost.Kind.DOUBT, {}))

	if report.withdrawers > 0:
		plan.append(_request(FeedPost.Kind.WITHDRAW,
			{"count": Fmt.grouped(report.withdrawers)}))

	if report.has_beat(WeekReport.Beat.WHALE):
		plan.append(_request(FeedPost.Kind.WHALE,
			{"amount": Fmt.money(report.whale_deposit)}))

	if report.recruits > 0:
		var joined: Dictionary[String, String] = {"count": Fmt.grouped(report.recruits)}
		plan.append(_request(FeedPost.Kind.JOINED, joined, false, true))
		if report.recruits >= 6:
			plan.append(_request(FeedPost.Kind.JOINED, joined, false, true))

	if report.marketing > 0.0 and _rng.randf() < 0.12 + state.hype / 500.0:
		plan.append(_request(FeedPost.Kind.HYPE, {}))

	while plan.size() < MIN_POSTS:
		plan.append(_request(FeedPost.Kind.CHATTER, {}))
	return plan


## Everything the payout calendar produced. Broken promises come first because
## they are the loudest thing that can happen to a scheme that is still running.
func _plan_payouts(plan: Array[Request], state: SchemeState, report: WeekReport) -> void:
	var announced := report.has_beat(WeekReport.Beat.PAYOUT_DELAYED) \
		or report.has_beat(WeekReport.Beat.PAYOUT_PART)
	var broken := announced or report.has_beat(WeekReport.Beat.PAYOUT_SHORT)

	if broken:
		plan.append(_request(FeedPost.Kind.BROKEN, {}, true))
		# An announcement is a public admission, so a second voice picks it up.
		if announced:
			plan.append(_request(FeedPost.Kind.BROKEN, {}, true))
	elif report.has_beat(WeekReport.Beat.QUEUE_UNSERVED):
		plan.append(_request(FeedPost.Kind.BROKEN, {}))

	if report.has_beat(WeekReport.Beat.PAYOUT_FULL):
		plan.append(_request(FeedPost.Kind.PAID, {}, true))
	elif not broken and state.deferred_payout > 0.5:
		plan.append(_request(FeedPost.Kind.WAITING, {}, true))


func _request(kind: FeedPost.Kind, slots: Dictionary[String, String],
		needs_due: bool = false, needs_new: bool = false,
		needs_paid: bool = false) -> Request:
	var request := Request.new()
	request.kind = kind
	request.slots = slots
	request.needs_due = needs_due
	request.needs_new = needs_new
	request.needs_paid = needs_paid
	return request


func _tell_request(pending: PendingSignal) -> Request:
	var request := _request(FeedPost.Kind.TELL, {})
	request.pending = pending
	request.mandatory = true
	return request

#endregion


#region Casting and filling

## Finds somebody in the roster willing to say this, and hands them a body.
## Returns null when nobody qualifies — a week where no cast member is angry
## enough to complain simply has no complaint in it, which is correct.
func _write(state: SchemeState, report: WeekReport, request: Request,
		spoken: Array[CastMember]) -> FeedPost:
	var pick := _cast_for(state, request, spoken, false)
	# Nobody in the mood to say it, and it has to be said anyway. Only tells take
	# this branch, and the cost is a slightly out-of-character voice rather than a
	# missing warning — the right trade every time.
	if pick.x < 0 and request.mandatory:
		pick = _cast_for(state, request, spoken, true)
	if pick.x < 0:
		return null

	var chosen := _sets[pick.x]
	var author := state.cast[pick.y]
	var body := _fill(_draw_body(pick.x), report, author, request)
	return FeedPost.make(author, body, request.kind, chosen.tone,
		_engagement(state, author, chosen), report.week)


## Reservoir sample over the (template × willing author) pairs, so one pass picks
## uniformly without building the cross product. Returns (set slot, cast index),
## or (-1, -1) when nobody qualifies. `relaxed` drops the archetype and mood
## filters and is only ever used to rescue a mandatory request.
func _cast_for(state: SchemeState, request: Request, spoken: Array[CastMember],
		relaxed: bool) -> Vector2i:
	var pick := Vector2i(-1, -1)
	var considered := 0

	var candidates: PackedInt32Array = _by_kind.get(int(request.kind), PackedInt32Array())
	for slot in candidates:
		var template := _sets[slot]
		if request.pending != null and not template.speaks_for(request.pending):
			continue
		for i in state.cast.size():
			var member := state.cast[i]
			if not relaxed and not template.accepts(member):
				continue
			if request.needs_due and not member.is_due(state.week):
				continue
			if request.needs_new and member.join_week != state.week:
				continue
			if request.needs_paid \
					and member.join_week + member.interval_weeks > state.week:
				continue
			if spoken.has(member):
				continue
			considered += 1
			if _rng.randi() % considered == 0:
				pick = Vector2i(slot, i)
	return pick


## Draws from the set's shuffle bag: every body in a set is used once before any
## is used twice. Repetition inside a single run is the thing that breaks the
## illusion fastest (DESIGN.md §6).
func _draw_body(slot: int) -> String:
	var bag := _bags[slot]
	if bag.is_empty():
		var refill := PackedInt32Array()
		for i in _sets[slot].bodies.size():
			refill.append(i)
		bag = refill
	var pick := _rng.randi() % bag.size()
	var index := bag[pick]
	bag.remove_at(pick)
	_bags[slot] = bag
	return _sets[slot].bodies[index]


## Fills the template slots. Every default is a fact about the *author* — their
## own cheque, their own stake, their own weeks in — because those are paperwork
## the person holding them is entitled to quote. The scheme's own arithmetic
## never appears here; that is what the back office is for (DESIGN.md §7).
func _fill(body: String, report: WeekReport, author: CastMember,
		request: Request) -> String:
	var elapsed := maxi(report.week - author.join_week, 1)
	var slots: Dictionary[String, String] = {
		"name": author.display_name,
		"handle": author.handle,
		"week": str(report.week),
		"count": Fmt.grouped(maxi(report.recruits, 1)),
		"weeks": "%d week%s" % [elapsed, "" if elapsed == 1 else "s"],
		"item": LUXURIES[_rng.randi() % LUXURIES.size()],
		"amount": Fmt.money(_personal_amount(author, request.kind)),
	}
	slots.merge(request.slots, true)

	var text := body
	for key in slots:
		text = text.replace("{%s}" % key, slots[key])
	return text


## Which of their own numbers this person is quoting. Talking about a payment
## means the cheque; talking about being in, or getting out, means the whole
## stake. Getting this wrong reads as somebody bragging about $89.
func _personal_amount(author: CastMember, kind: FeedPost.Kind) -> float:
	match kind:
		FeedPost.Kind.PAID, FeedPost.Kind.FLEX, FeedPost.Kind.WAITING, \
		FeedPost.Kind.BROKEN:
			var cheque := author.stake * author.rate_per_interval
			if cheque > 1.0:
				return cheque
	return author.stake


## Likes and shares. Loud when hype is high, scaled by who is talking, and noisy
## on purpose — it is an impression of reach, never a readable hype value.
func _engagement(state: SchemeState, author: CastMember, template: PostTemplateSet) -> int:
	var loudness := 0.25 + 0.9 * (state.hype / 100.0)
	var raw := float(author.reach) * loudness * template.engagement_scale \
		* _rng.randf_range(0.55, 1.6) * 0.35
	return maxi(int(raw), 1)

#endregion


func _round_stochastic(value: float) -> int:
	if value <= 0.0:
		return 0
	var whole := floorf(value)
	return int(whole) + (1 if _rng.randf() < value - whole else 0)
