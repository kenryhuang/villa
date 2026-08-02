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
signal building_placed(building: BuildingInstance)
signal building_removed(building: BuildingInstance)
signal building_preview_moved(gx: int, gz: int, can_place: bool)
signal building_construction_started(building: BuildingInstance)
signal building_construction_stage_changed(building: BuildingInstance, stage: int)
signal building_construction_completed(building: BuildingInstance)

# Economy signals
signal gold_changed(new_gold: int)
signal market_stock_changed(item_id: String, new_stock: int)
signal market_price_changed(item_id: String, new_price: int)
signal market_settled(total_day: int)
signal market_caravan_changed(caravan_id: String, arrived: bool)
signal production_job_started(building: BuildingInstance, recipe_id: String, batches: int)
signal production_job_completed(building: BuildingInstance, recipe_id: String, outputs: Dictionary)
signal production_output_blocked(building: BuildingInstance, recipe_id: String)
signal production_feed_shortage(building: BuildingInstance, item_id: String)
signal production_output_changed(building: BuildingInstance, item_id: String, new_quantity: int)
signal production_input_changed(building: BuildingInstance, item_id: String, new_quantity: int)
signal production_maintenance_changed(building: BuildingInstance, due_day: int)
signal building_economy_opened(building: BuildingInstance, panel_kind: String)
signal building_economy_closed(building: BuildingInstance)
signal building_economy_action_failed(building: BuildingInstance, action: String, reason: String)
signal service_unlocked(kind: String, target_id: String)
signal building_upgrade_changed(building: BuildingInstance, upgrade_id: String, level: int)
signal tool_durability_changed(tool_id: String, current: int, maximum: int)

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
signal order_updated(order_id: String)
signal contract_updated(contract_id: String)
signal economy_notification_changed(notification_id: String, merged: bool)
# Deprecated Task15 compatibility bridge. The configured notification owner and
# HUD never consume this signal; it remains only for isolated legacy panel tests.
signal economy_ui_notification_added(target_type: String, target_id: String)

# Villager signals
signal affinity_changed(villager_id: String, value: int)
signal affinity_level_up(villager_id: String, level: int)

# Exploration signals
signal collectible_found(data: Dictionary)
signal story_fragment_collected(fragment_id: String)
signal puzzle_solved(puzzle_id: String)
signal region_unlocked(region_id: String)
