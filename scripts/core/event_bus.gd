extends Node

# Signals are consumed through this Autoload from other scripts. Godot's
# per-file analysis cannot see those injected/cross-script uses.
@warning_ignore_start("unused_signal")

# Farming signals
signal cell_state_changed(gx: int, gz: int, new_state: int)
signal cell_watered(gx: int, gz: int)
signal crop_planted(gx: int, gz: int, crop_id: String)
signal crop_grew(gx: int, gz: int, stage: int)
signal crop_matured(gx: int, gz: int)
signal crop_harvested(gx: int, gz: int, crop_id: String)

# Economy signals
signal gold_changed(new_gold: int)

# Time signals
signal season_changed(new_season: int)
signal day_changed(total_day: int)
signal time_changed(hour: int, minute: int)

# Player signals
signal stamina_changed(new_stamina: int)
signal level_changed(new_level: int)
signal exp_gained(amount: int)

# Inventory signals
signal item_added(item_id: String, quantity: int)
signal item_removed(item_id: String, quantity: int)

# Order signals
signal order_generated(order_index: int)
signal order_completed(order_index: int)

# Villager signals
signal affinity_changed(villager_id: String, value: int)
signal affinity_level_up(villager_id: String, level: int)

# Exploration signals
signal collectible_found(data: Dictionary)
signal story_fragment_collected(fragment_id: String)
signal puzzle_solved(puzzle_id: String)
signal region_unlocked(region_id: String)
