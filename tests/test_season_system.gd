extends RefCounted

const SeasonSystemScript = preload("res://scripts/systems/season_system.gd")


func run(assertions: TestAssert) -> void:
	assertions.near(
		SeasonSystemScript.MINUTES_PER_REAL_SECOND,
		3.6,
		0.001,
		"five real minutes advance one full game day"
	)

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

	var action_clock := SeasonSystemScript.new()
	action_clock.hour = 23
	action_clock.minute = 55
	action_clock.advance_game_minutes(10)
	assertions.equal(action_clock.hour, 6, "ten-minute late action crosses midnight to 06")
	assertions.equal(action_clock.minute, 5, "cross-day action preserves five remaining minutes")
	assertions.equal(action_clock.current_day, 2, "cross-day action advances exactly one day")

	# Debug-friendly next-day advancement still uses the normal clock path.
	var clock5 := SeasonSystemScript.new()
	clock5.hour = 14
	clock5.minute = 35
	assertions.truthy(
		clock5.has_method("advance_to_next_day"),
		"season system exposes normal-path next-day advancement"
	)
	if clock5.has_method("advance_to_next_day"):
		clock5.call("advance_to_next_day")
		assertions.equal(clock5.hour, 6, "next-day advancement lands at 06")
		assertions.equal(clock5.minute, 0, "next-day advancement clears minutes")
		assertions.equal(clock5.current_day, 2, "next-day advancement increments the day once")

	var locked_clock := SeasonSystemScript.new()
	var owner_a := Node.new()
	var owner_b := Node.new()
	assertions.truthy(locked_clock.acquire_action_clock_lock(owner_a), "first action owner acquires a clock lock")
	assertions.truthy(not locked_clock.acquire_action_clock_lock(owner_a), "same owner cannot acquire twice")
	assertions.truthy(locked_clock.acquire_action_clock_lock(owner_b), "second action owner acquires independently")
	locked_clock._process(1.0)
	assertions.equal(locked_clock.minute, 0, "automatic time pauses while any action lock exists")
	locked_clock.advance_game_minutes(10)
	assertions.equal(locked_clock.minute, 10, "explicit successful action advances exactly ten minutes while locked")
	assertions.truthy(locked_clock.release_action_clock_lock(owner_a), "first owner releases its own lock")
	locked_clock._process(1.0)
	assertions.equal(locked_clock.minute, 10, "remaining owner keeps automatic time paused")
	assertions.truthy(locked_clock.release_action_clock_lock(owner_b), "last owner releases its lock")
	assertions.truthy(not locked_clock.release_action_clock_lock(owner_b), "released owner cannot release twice")
	locked_clock._process(1.0)
	assertions.equal(locked_clock.minute, 13, "automatic time resumes after the last lock")

	var invalid_owner := Node.new()
	assertions.truthy(locked_clock.acquire_action_clock_lock(invalid_owner), "temporary owner acquires a lock")
	invalid_owner.free()
	locked_clock.clear_invalid_action_clock_locks()
	locked_clock._process(1.0)
	assertions.equal(locked_clock.minute, 17, "invalid lock owners are cleared before automatic time")
	clock.free()
	clock2.free()
	clock3.free()
	clock4.free()
	action_clock.free()
	clock5.free()
	owner_a.free()
	owner_b.free()
	locked_clock.free()
