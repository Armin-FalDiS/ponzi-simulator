class_name GameController
extends Node
## Drives the simulation clock and republishes results on the EventBus.
##
## Deliberately thin: it owns a `SchemeSim`, a `SchemeState`, and a `Timer`.
## All the rules live in the sim; all the presentation lives in the UI.

@export var config: SchemeConfig
## Real seconds per simulated week when autoplay is on.
@export_range(0.2, 5.0, 0.1) var seconds_per_week: float = 1.5
## Set non-zero to make a run reproducible.
@export var rng_seed: int = 0

var state: SchemeState
## Action queued for the coming week. Reset every tick.
var pending_action: SchemeSim.Action = SchemeSim.Action.NONE

var _sim: SchemeSim
var _clock: Timer
var _autoplay: bool = false


func _ready() -> void:
	_clock = Timer.new()
	_clock.name = "WeekClock"
	_clock.wait_time = seconds_per_week
	_clock.autostart = false
	_clock.timeout.connect(advance_week)
	add_child(_clock)


## Starts (or restarts) a run. Call this after listeners are connected so the
## opening position isn't emitted into an empty room.
func start_run() -> void:
	set_autoplay(false)
	_sim = SchemeSim.new(config, rng_seed)
	state = _sim.create_state()
	pending_action = SchemeSim.Action.NONE
	EventBus.run_started.emit(state)


func advance_week() -> void:
	if state == null or not state.is_running():
		return
	var report := _sim.advance(state, pending_action)
	pending_action = SchemeSim.Action.NONE
	EventBus.week_advanced.emit(report)
	if not state.is_running():
		set_autoplay(false)
		EventBus.run_ended.emit(report)


func exit_scam() -> void:
	if state == null or not state.is_running():
		return
	var report := _sim.exit_scam(state)
	set_autoplay(false)
	EventBus.week_advanced.emit(report)
	EventBus.run_ended.emit(report)


func set_autoplay(on: bool) -> void:
	_autoplay = on and state != null and state.is_running()
	if _autoplay:
		_clock.start(seconds_per_week)
	else:
		_clock.stop()


func is_autoplay() -> bool:
	return _autoplay


func action_cost(action: SchemeSim.Action) -> float:
	if state == null or _sim == null:
		return 0.0
	return _sim.action_cost(state, action)


## Heat the current scheme size makes permanent. Surfaced so the HUD can mark it.
func heat_floor() -> float:
	if state == null or _sim == null:
		return -1.0
	return _sim.heat_floor(state)


## The opening position has no `WeekReport` to carry a calendar, so the HUD asks
## for one directly. Still controller-mediated — the UI never holds the sim.
func obligation_forecast() -> Array[float]:
	if state == null or _sim == null:
		return []
	return _sim.obligation_forecast(state, config.forecast_weeks)


## Rewrites the offer new investors will sign. Existing cohorts keep their own
## paperwork, which is the whole point of the terms system.
func set_terms(weekly_rate: float, interval_weeks: int) -> void:
	if state == null:
		return
	state.current_terms.interval_weeks = interval_weeks
	state.current_terms.set_weekly_rate(weekly_rate)
