class_name SeasonSystem
extends Node

enum Season { SPRING, SUMMER, AUTUMN, WINTER }

const DAYS_PER_SEASON := 7
const REAL_SECONDS_PER_DAY := 300.0
const GAME_MINUTES_PER_DAY := 18.0 * 60.0
const MINUTES_PER_REAL_SECOND := GAME_MINUTES_PER_DAY / REAL_SECONDS_PER_DAY

var current_season: Season = Season.SPRING
var current_day := 1
var total_days := 1
var hour := 6
var minute := 0

var _accumulator := 0.0
var _event_bus
var _action_clock_locks: Dictionary = {}


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")


func _process(delta: float) -> void:
	clear_invalid_action_clock_locks()
	if not _action_clock_locks.is_empty():
		return
	_accumulator += delta * MINUTES_PER_REAL_SECOND
	var whole_minutes := int(_accumulator)
	if whole_minutes > 0:
		_accumulator -= whole_minutes
		advance_game_minutes(whole_minutes)


func acquire_action_clock_lock(owner: Object) -> bool:
	if owner == null or not is_instance_valid(owner):
		return false
	var owner_id := owner.get_instance_id()
	if _action_clock_locks.has(owner_id):
		return false
	_action_clock_locks[owner_id] = weakref(owner)
	return true


func release_action_clock_lock(owner: Object) -> bool:
	if owner == null:
		return false
	var owner_id := owner.get_instance_id()
	if not _action_clock_locks.has(owner_id):
		return false
	_action_clock_locks.erase(owner_id)
	return true


func clear_invalid_action_clock_locks() -> void:
	var invalid_ids: Array[int] = []
	for owner_id in _action_clock_locks:
		var owner_ref := _action_clock_locks[owner_id] as WeakRef
		if owner_ref == null or owner_ref.get_ref() == null:
			invalid_ids.append(int(owner_id))
	for owner_id in invalid_ids:
		_action_clock_locks.erase(owner_id)


func _exit_tree() -> void:
	_action_clock_locks.clear()


func advance_game_minutes(minutes_to_add: int) -> void:
	for _unused in range(maxi(0, minutes_to_add)):
		minute += 1
		if minute >= 60:
			minute = 0
			hour += 1
		if hour >= 24:
			hour = 6
			current_day += 1
			total_days += 1
			if current_day > DAYS_PER_SEASON:
				current_day = 1
				current_season = (current_season + 1) % 4 as Season
				if _event_bus:
					_event_bus.season_changed.emit(current_season)
			if _event_bus:
				_event_bus.day_changed.emit(total_days)
		if _event_bus:
			_event_bus.time_changed.emit(hour, minute)


func advance_to_next_day() -> void:
	var minutes_until_next_day := (24 - hour) * 60 - minute
	advance_game_minutes(maxi(1, minutes_until_next_day))
