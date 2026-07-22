extends RefCounted

const SeasonSystemScript = preload("res://scripts/systems/season_system.gd")


func run(assertions: TestAssert) -> void:
	# Basic midnight rollover
	var clock := SeasonSystemScript.new()
	clock.hour = 23
	clock.minute = 59
	clock.advance_game_minutes(1)
	assertions.equal(clock.hour, 6, "midnight resets to 06")
	assertions.equal(clock.current_day, 2, "day advances")

	# Season rollover
	clock.current_day = 7
	clock.current_season = clock.Season.SPRING
	clock.hour = 23
	clock.minute = 59
	clock.advance_game_minutes(1)
	assertions.equal(clock.current_day, 1, "season day wraps")
	assertions.equal(clock.current_season, clock.Season.SUMMER, "season advances")

	# Minute signal count
	var clock2 := SeasonSystemScript.new()
	clock2.hour = 10
	clock2.minute = 0
	clock2.advance_game_minutes(5)
	assertions.equal(clock2.hour, 10, "hour unchanged after 5 minutes")
	assertions.equal(clock2.minute, 5, "minute is 5")

	# No negative minutes
	var clock3 := SeasonSystemScript.new()
	clock3.advance_game_minutes(-5)
	assertions.equal(clock3.hour, 6, "negative minutes don't change hour")
	assertions.equal(clock3.minute, 0, "negative minutes don't change minute")

	# Full day cycle
	var clock4 := SeasonSystemScript.new()
	clock4.hour = 6
	clock4.minute = 0
	clock4.advance_game_minutes(18 * 60)  # 18 hours to reach midnight
	assertions.equal(clock4.hour, 6, "18 hours from 6:00 wraps to next day 6:00")
	assertions.equal(clock4.current_day, 2, "day advanced after full cycle")
