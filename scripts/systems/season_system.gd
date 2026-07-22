class_name SeasonSystem
extends Node

enum Season { SPRING, SUMMER, AUTUMN, WINTER }

const DAYS_PER_SEASON := 7
const MINUTES_PER_REAL_SECOND := 1.0

var current_season: Season = Season.SPRING
var current_day := 1
var total_days := 1
var hour := 6
var minute := 0

var _accumulator := 0.0
var _event_bus


func _ready() -> void:
	_event_bus = get_node_or_null("/root/EventBus")


func _process(delta: float) -> void:
	_accumulator += delta * MINUTES_PER_REAL_SECOND
	var whole_minutes := int(_accumulator)
	if whole_minutes > 0:
		_accumulator -= whole_minutes
		advance_game_minutes(whole_minutes)


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
