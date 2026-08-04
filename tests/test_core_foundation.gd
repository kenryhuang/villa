extends RefCounted

const GridCellScript = preload("res://scripts/data/grid_cell.gd")
const CropInstanceScript = preload("res://scripts/data/crop_instance.gd")
const CropDataScript = preload("res://scripts/data/crop_data.gd")
const PlayerStateScript = preload("res://scripts/data/player_state.gd")


func _make_crop(growth_days: int, stage_count: int):
	var crop = CropDataScript.new()
	crop.crop_id = "test_crop"
	crop.crop_name = "Test Crop"
	crop.growth_days = growth_days
	for i in range(stage_count):
		crop.stage_textures.append("res://stage_%d.png" % i)
	return crop


func run(assertions: TestAssert) -> void:
	assertions.truthy(
		FileAccess.file_exists("res://.worktrees/.gdignore"),
		"Godot ignores nested Git worktrees so global class names do not collide"
	)

	# GridCell world position
	var cell = GridCellScript.new()
	cell.gx = 0
	cell.gz = 0
	cell.terrain_height = 2.5
	assertions.equal(cell.world_position(), Vector2(-17.5, -13.5), "grid origin maps to center")
	assertions.equal(cell.world_position_3d(), Vector3(-17.5, 2.5, -13.5), "3d position includes terrain")

	# CropInstance growth
	var crop = CropInstanceScript.new()
	crop.crop_data = _make_crop(3, 4)
	crop.is_watered_today = true
	assertions.truthy(not crop.advance_growth(), "first growth is not mature")
	assertions.near(crop.growth_progress, 1.5, 0.001, "watered growth advances one and a half days")
	assertions.equal(crop.get_current_stage(), 1, "stage follows progress")

	# CropInstance mature
	crop.is_watered_today = true
	assertions.truthy(crop.advance_growth(), "second watered growth reaches 3.0 = mature")
	assertions.near(crop.growth_progress, 3.0, 0.001, "two watered advances reach 3.0")

	# PlayerState stamina
	var ps = PlayerStateScript.new()
	assertions.equal(ps.stamina, 100, "initial stamina is 100")
	assertions.equal(ps.max_stamina, 100, "initial max_stamina is 100")
	assertions.truthy(ps.set_stamina(50), "set_stamina changes value")
	assertions.equal(ps.stamina, 50, "stamina is 50 after set")
	assertions.truthy(not ps.set_stamina(50), "set_stamina same value returns false")
	assertions.truthy(ps.set_stamina(-10), "set_stamina clamps to 0")
	assertions.equal(ps.stamina, 0, "stamina clamped to 0")
	assertions.truthy(ps.set_stamina(200), "set_stamina clamps to max")
	assertions.equal(ps.stamina, 100, "stamina clamped to max_stamina")

	# PlayerState exp and level
	var ps2 = PlayerStateScript.new()
	assertions.equal(ps2.level, 1, "initial level is 1")
	assertions.equal(ps2.exp, 0, "initial exp is 0")
	assertions.truthy(not ps2.add_exp(50), "50 exp does not level up")
	assertions.equal(ps2.exp, 50, "exp is 50")
	assertions.truthy(ps2.add_exp(60), "110 total exp levels up to 2")
	assertions.equal(ps2.level, 2, "level is 2")
	assertions.equal(ps2.exp, 110, "exp is 110")
	assertions.near(ps2.get_exp_progress(), 0.0667, 0.01, "exp progress between level 2 and 3")
