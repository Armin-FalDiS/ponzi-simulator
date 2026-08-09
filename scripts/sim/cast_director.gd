class_name CastDirector
extends RefCounted
## Decides who is visible. Spawns named people as money arrives, moves their
## moods, retires the ones who cash out, and rotates the roster so it stays at
## about a dozen faces.
##
## **Rotation is by join week, and that is the whole point** (DESIGN.md §4.4).
## The founding cohort is your sister-in-law and your barber; the finite family
## name pool runs out after the first few weeks, and the oldest face is always
## the one evicted when a new one arrives. So the game gets steadily less
## personal the more successful you are, with no scripting and no timeline — it
## falls out of one eviction rule.
##
## Pure `RefCounted` like the rest of the sim. The roster is data on
## `SchemeState`; every rule about it is here.

## Names for the people who knew you before there was a fund. Deliberately
## finite: once it empties, every new face is a stranger, and it never refills.
## The handle carries the relationship so `CastMember` needs no extra field.
const FAMILY_CAST: Array[String] = [
	"Deb Halloran|aunt_deb",
	"Ray Osei|ray_cuts_hair",
	"Marta Ferreira|marta_nextdoor",
	"Kev Brennan|kev_from_school",
	"Susan Adeyemi|mum",
	"Tony Vasquez|tone_the_brother",
	"Ines Kowalski|ines_bestman",
	"Gary Whitlock|gaz_five_a_side",
	"Nadia Hart|nads_cousin",
	"Phil Okonkwo|phil_upstairs",
	"Bea Lindqvist|bea_godmother",
	"Dan Achterberg|dan_wedding_dj",
]

const FIRST_NAMES: Array[String] = [
	"Alex", "Priya", "Marcus", "Ola", "Henrietta", "Jozef", "Camille", "Ade",
	"Rosa", "Duncan", "Yuki", "Tomas", "Grace", "Sanjay", "Lena", "Ibrahim",
	"Clara", "Nate", "Aoife", "Mikhail", "Bianca", "Karl", "Sunmi", "Theo",
	"Farida", "Owen", "Elke", "Rashid", "Joan", "Piotr", "Amara", "Vince",
]

const LAST_NAMES: Array[String] = [
	"Baptiste", "Nkemdirim", "Rasmussen", "Oyelaran", "Castellano", "Whitmore",
	"Duarte", "Halvorsen", "Attah", "Marchetti", "Petrov", "Sandoval",
	"Lindgren", "Bassey", "Ferraro", "Novotny", "Ashworth", "Yilmaz",
	"Delacroix", "Mbeki", "Ronaldsson", "Quintero", "Harkness", "Sowande",
]

const JOURNALIST_CAST: Array[String] = [
	"Imogen Pryce|pryce_on_markets",
	"Desmond Iyer|desiyer_reports",
	"Hana Mikkelsen|hmikkelsen",
	"Robert Nwachukwu|bobby_bylines",
]

const CRANK_CAST: Array[String] = [
	"anon|ledger_goblin",
	"D.|actual_due_diligence",
	"Fraudwatch|the_spreadsheet_guy",
	"K. Salter|numbersdontcare",
]

const INFLUENCER_CAST: Array[String] = [
	"Sasha Vance|sashabuildswealth",
	"Deniz Aktaş|denizmoneytalks",
	"Milo Fenwick|fenwickfinance",
	"Ruby Okafor|rubyreturns",
]

## Where each archetype's mood settles before trust and events move it.
const MOOD_BIAS: Array[float] = [0.30, 0.40, -0.15, 0.15, 0.30, -0.75, -0.90]
## How fast a mood travels toward its target. Low enough that one bad week
## leaves a mark for several.
const MOOD_INERTIA := 0.35

var _config: SchemeConfig
var _rng: RandomNumberGenerator
## Family names not yet handed out. Shrinks and never grows.
var _family_pool: Array[String] = []
var _stranger_serial: int = 0
var _last_avg_stake: float = 0.0


func _init(scheme_config: SchemeConfig, rng: RandomNumberGenerator) -> void:
	_config = scheme_config
	_rng = rng
	_family_pool = FAMILY_CAST.duplicate()


## Opening roster: the people who got you started, and nobody else. The roster
## grows to full size only as the scheme does.
func seed_cast(state: SchemeState) -> void:
	state.cast.clear()
	_last_avg_stake = state.avg_stake()
	for _i in maxi(state.investors(), 1):
		state.cast.append(_spawn_investor(state, 0, _pick_investor_archetype()))


## One week of casting. Runs after the economy has resolved, so it is reacting to
## facts rather than predicting them.
func update(state: SchemeState, report: WeekReport) -> void:
	_age_stakes(state)
	_move_moods(state, report)
	_retire(state, report)
	_update_onlookers(state)
	_intake(state, report)
	_rotate(state)


#region Weekly steps

## Reinvested returns inflate what everybody believes they hold, and a
## withdrawal round deflates it. Rather than tracking each person's paperwork
## separately, ride the scheme's own average — the cast is a sample of the book,
## not a second copy of it.
func _age_stakes(state: SchemeState) -> void:
	var current := state.avg_stake()
	if _last_avg_stake <= 0.0:
		_last_avg_stake = current
		return
	var growth := clampf(current / _last_avg_stake, 0.5, 2.0)
	_last_avg_stake = current
	if is_equal_approx(growth, 1.0):
		return
	for member in state.cast:
		if member.is_investor():
			member.stake *= growth


func _move_moods(state: SchemeState, report: WeekReport) -> void:
	var settled := report.has_beat(WeekReport.Beat.PAYOUT_FULL)
	var broken := report.has_beat(WeekReport.Beat.PAYOUT_DELAYED) \
		or report.has_beat(WeekReport.Beat.PAYOUT_PART) \
		or report.has_beat(WeekReport.Beat.PAYOUT_SHORT)
	var owed_from_before := state.deferred_payout > 0.5

	for member in state.cast:
		var target := MOOD_BIAS[int(member.archetype)] + 1.4 * (state.trust / 100.0) - 0.55
		member.mood = lerpf(member.mood, clampf(target, -1.0, 1.0), MOOD_INERTIA)
		# Being personally short-changed outweighs any amount of general mood.
		if member.is_due(state.week):
			if broken:
				member.mood -= 0.55
			elif settled:
				member.mood += 0.30
		if owed_from_before and member.is_investor():
			member.mood -= 0.12
		member.mood = clampf(member.mood, -1.0, 1.0)


## The roster is a sample of the book, so it loses people at the same rate the
## book does. The unhappiest go first — the people posting about withdrawing are
## the people who were already posting about being unhappy.
func _retire(state: SchemeState, report: WeekReport) -> void:
	if report.withdrawers <= 0:
		return
	var before := report.investors + report.withdrawers
	var share := float(report.withdrawers) / float(maxi(before, 1))
	var on_screen := _investor_count(state)
	var leaving := mini(_round_stochastic(share * float(on_screen)), maxi(on_screen - 2, 0))
	for _i in leaving:
		var worst := -1
		for i in state.cast.size():
			if not state.cast[i].is_investor():
				continue
			if worst < 0 or state.cast[i].mood < state.cast[worst].mood:
				worst = i
		if worst < 0:
			return
		state.cast.remove_at(worst)


## Onlookers hold a seat only while the thing they care about is true. A
## journalist in the roster *is* the heat readout, so they must arrive and leave
## on heat alone and never linger for flavour.
func _update_onlookers(state: SchemeState) -> void:
	_hold_seat(state, CastMember.Archetype.JOURNALIST, JOURNALIST_CAST,
		state.heat >= _config.cast_journalist_heat,
		state.heat < _config.cast_journalist_heat - 12.0)
	_hold_seat(state, CastMember.Archetype.CRANK, CRANK_CAST,
		state.solvency() < 0.45 and state.week > 5, state.solvency() > 0.60)
	_hold_seat(state, CastMember.Archetype.INFLUENCER, INFLUENCER_CAST,
		state.hype >= _config.cast_influencer_hype,
		state.hype < _config.cast_influencer_hype - 12.0)


func _hold_seat(state: SchemeState, archetype: CastMember.Archetype,
		pool: Array[String], wants_in: bool, wants_out: bool) -> void:
	var seat := _find_archetype(state, archetype)
	if seat < 0 and wants_in:
		state.cast.append(_spawn_onlooker(state, archetype, pool))
	elif seat >= 0 and wants_out:
		state.cast.remove_at(seat)


func _intake(state: SchemeState, report: WeekReport) -> void:
	if report.has_beat(WeekReport.Beat.WHALE):
		var whale := _spawn_investor(state, state.week, CastMember.Archetype.WHALE)
		whale.stake = maxf(report.whale_deposit, whale.stake)
		state.cast.append(whale)
	if report.recruits <= 0:
		return
	for _i in mini(report.recruits, _config.cast_intake):
		state.cast.append(_spawn_investor(state, state.week, _pick_investor_archetype()))


## The eviction that carries the emotional arc: when the roster is full, the
## person who has been there longest leaves it. Nothing else needs to know about
## the arc for the arc to happen.
func _rotate(state: SchemeState) -> void:
	while state.cast.size() > _config.cast_size:
		var oldest := -1
		for i in state.cast.size():
			if not state.cast[i].is_investor():
				continue
			if oldest < 0 or state.cast[i].join_week < state.cast[oldest].join_week:
				oldest = i
		if oldest < 0:
			return
		state.cast.remove_at(oldest)

#endregion


#region Casting

func _spawn_investor(state: SchemeState, week: int,
		archetype: CastMember.Archetype) -> CastMember:
	var member := CastMember.new()
	member.archetype = archetype
	_name_member(member, state)

	member.join_week = week
	member.interval_weeks = state.current_terms.interval_weeks
	member.rate_per_interval = state.current_terms.rate_per_interval
	member.avatar_tint = state.cast.size() + _stranger_serial
	member.mood = clampf(MOOD_BIAS[int(member.archetype)] + 0.35
		+ _rng.randf_range(-0.15, 0.15), -1.0, 1.0)

	var base := maxf(state.avg_stake(), _config.avg_deposit)
	match member.archetype:
		CastMember.Archetype.WHALE:
			member.stake = base * _rng.randf_range(4.0, 9.0)
			member.reach = _rng.randi_range(300, 1600)
		_:
			member.stake = base * _rng.randf_range(0.5, 1.8)
			member.reach = _rng.randi_range(25, 320)
	return member


## Family first, and only while the pool lasts. Once it is empty every new face
## is somebody you have never met, which is exactly the arc.
func _name_member(member: CastMember, state: SchemeState) -> void:
	if member.archetype == CastMember.Archetype.FAMILY and not _family_pool.is_empty():
		_apply_name(member, _family_pool.pop_at(_rng.randi() % _family_pool.size()))
		return
	if member.archetype == CastMember.Archetype.FAMILY:
		member.archetype = CastMember.Archetype.BELIEVER

	_stranger_serial += 1
	var first := FIRST_NAMES[_rng.randi() % FIRST_NAMES.size()]
	var last := LAST_NAMES[_rng.randi() % LAST_NAMES.size()]
	# Three Castellanos on screen at once reads as a bug, not a coincidence — and
	# the avatar is initials, so a shared surname also means a duplicate face.
	for _retry in 5:
		if not _surname_taken(state, last):
			break
		last = LAST_NAMES[_rng.randi() % LAST_NAMES.size()]
	member.display_name = "%s %s" % [first, last]
	member.handle = "@%s%s%d" % [first.to_lower(), last.substr(0, 1).to_lower(),
		10 + (_stranger_serial * 7 + state.week) % 89]


func _surname_taken(state: SchemeState, last: String) -> bool:
	for member in state.cast:
		if member.display_name.ends_with(" " + last):
			return true
	return false


func _spawn_onlooker(state: SchemeState, archetype: CastMember.Archetype,
		pool: Array[String]) -> CastMember:
	var member := CastMember.new()
	member.archetype = archetype
	_apply_name(member, pool[_rng.randi() % pool.size()])
	member.join_week = state.week
	member.stake = 0.0
	member.avatar_tint = int(archetype) * 3 + 5
	member.mood = MOOD_BIAS[int(archetype)]
	member.reach = _rng.randi_range(2200, 14000) if archetype != CastMember.Archetype.CRANK \
		else _rng.randi_range(400, 2500)
	return member


func _apply_name(member: CastMember, entry: String) -> void:
	var parts := entry.split("|")
	member.display_name = parts[0]
	member.handle = "@" + parts[1] if parts.size() > 1 else "@" + parts[0].to_lower()


## Family while there is family left, then mostly believers, with a steady
## trickle of sceptics and the occasional whale.
func _pick_investor_archetype() -> CastMember.Archetype:
	if not _family_pool.is_empty() and _rng.randf() < 0.75:
		return CastMember.Archetype.FAMILY
	var roll := _rng.randf()
	if roll < 0.62:
		return CastMember.Archetype.BELIEVER
	if roll < 0.92:
		return CastMember.Archetype.SCEPTIC
	return CastMember.Archetype.WHALE

#endregion


func _investor_count(state: SchemeState) -> int:
	var total := 0
	for member in state.cast:
		if member.is_investor():
			total += 1
	return total


func _find_archetype(state: SchemeState, archetype: CastMember.Archetype) -> int:
	for i in state.cast.size():
		if state.cast[i].archetype == archetype:
			return i
	return -1


func _round_stochastic(value: float) -> int:
	if value <= 0.0:
		return 0
	var whole := floorf(value)
	return int(whole) + (1 if _rng.randf() < value - whole else 0)
