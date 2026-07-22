extends Node

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
