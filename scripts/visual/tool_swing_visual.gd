class_name ToolSwingVisual
extends Node3D

const ACTION_DURATION := 1.2
const PREPARE_END := 0.25
const STRIKE_END := 0.55
const IMPACT_END := 0.70
const AXE_ACTION_DURATION := 3.0
const AXE_SWING_CYCLE := 0.72
const AXE_PREPARE_END := 0.10
const AXE_STRIKE_END := 0.24
const AXE_IMPACT_END := 0.34
const AXE_RAISED_ANGLE := deg_to_rad(-20.0)
const AXE_IMPACT_ANGLE := deg_to_rad(-112.0)
const PICKAXE_RAISED_ANGLE := deg_to_rad(-5.0)
const PICKAXE_PREPARED_ANGLE := deg_to_rad(-35.0)
const PICKAXE_IMPACT_ANGLE := deg_to_rad(-95.0)
const CANCEL_RECOVERY_DURATION := 0.14
const DEFAULT_TOOL_PIXEL_SIZE := 0.0035
const AXE_PIXEL_SIZE := DEFAULT_TOOL_PIXEL_SIZE * 0.5
const PICKAXE_PIXEL_SIZE := AXE_PIXEL_SIZE
const TOOL_PIVOT_SHADER_PATH := "res://assets/buildings/construction/construction_hammer.gdshader"
const TOOL_TEXTURES := {
	"axe": "res://assets/ui/action_icons/axe.png",
	"pickaxe": "res://assets/ui/action_icons/pickaxe.png",
}

var _tool_id := ""
var _cancel_tween: Tween
var _tool_head_from_handle := Vector2.ZERO
var _tool_screen_offset := Vector2.ZERO


func _init() -> void:
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	var sprite := Sprite3D.new()
	sprite.name = "ToolSprite"
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.shaded = false
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.pixel_size = DEFAULT_TOOL_PIXEL_SIZE
	sprite.position = Vector3.ZERO
	pivot.add_child(sprite)
	visible = false


func play_tool(tool_id: String) -> bool:
	if not TOOL_TEXTURES.has(tool_id):
		return false
	var texture := load(str(TOOL_TEXTURES[tool_id])) as Texture2D
	if texture == null:
		return false
	if _cancel_tween != null and _cancel_tween.is_valid():
		_cancel_tween.kill()
	_tool_id = tool_id
	var sprite := get_node("Pivot/ToolSprite") as Sprite3D
	sprite.texture = texture
	if tool_id == "axe":
		_configure_axe_pivot(sprite, texture)
	elif tool_id == "pickaxe":
		_configure_pickaxe_pivot(sprite, texture)
	else:
		sprite.material_override = null
		sprite.pixel_size = DEFAULT_TOOL_PIXEL_SIZE
		sprite.position = Vector3(0.0, 0.38, 0.0)
	visible = true
	set_action_progress(0.0)
	return true


func set_action_progress(progress: float) -> void:
	var elapsed := clampf(progress, 0.0, 1.0) * ACTION_DURATION
	var prepare_end := PREPARE_END
	var strike_end := STRIKE_END
	var impact_end := IMPACT_END
	var cycle_duration := ACTION_DURATION
	var raised_angle := PICKAXE_RAISED_ANGLE if _tool_id == "pickaxe" else AXE_RAISED_ANGLE
	var prepared_angle := PICKAXE_PREPARED_ANGLE if _tool_id == "pickaxe" else deg_to_rad(-42.0)
	var impact_angle := PICKAXE_IMPACT_ANGLE if _tool_id == "pickaxe" else AXE_IMPACT_ANGLE
	if _tool_id == "axe":
		elapsed = fmod(clampf(progress, 0.0, 1.0) * AXE_ACTION_DURATION, AXE_SWING_CYCLE)
		prepare_end = AXE_PREPARE_END
		strike_end = AXE_STRIKE_END
		impact_end = AXE_IMPACT_END
		cycle_duration = AXE_SWING_CYCLE
	var rotation_value := 0.0
	if elapsed < prepare_end:
		rotation_value = lerpf(raised_angle, prepared_angle, elapsed / prepare_end)
	elif elapsed < strike_end:
		rotation_value = lerpf(
			prepared_angle,
			impact_angle,
			(elapsed - prepare_end) / (strike_end - prepare_end)
		)
	elif elapsed < impact_end:
		rotation_value = impact_angle
	else:
		rotation_value = lerpf(
			impact_angle,
			raised_angle,
			(elapsed - impact_end) / (cycle_duration - impact_end)
		)
	_apply_rotation(rotation_value)


func get_phase_at(elapsed: float) -> String:
	var phase_elapsed := maxf(elapsed, 0.0)
	var prepare_end := PREPARE_END
	var strike_end := STRIKE_END
	var impact_end := IMPACT_END
	if _tool_id == "axe":
		phase_elapsed = fmod(phase_elapsed, AXE_SWING_CYCLE)
		prepare_end = AXE_PREPARE_END
		strike_end = AXE_STRIKE_END
		impact_end = AXE_IMPACT_END
	if phase_elapsed < prepare_end:
		return "prepare"
	if phase_elapsed < strike_end:
		return "strike"
	if phase_elapsed < impact_end:
		return "impact"
	return "recover"


func cancel_tool() -> void:
	if not visible:
		_tool_id = ""
		return
	if not is_inside_tree():
		_finish_cancel()
		return
	if _cancel_tween != null and _cancel_tween.is_valid():
		_cancel_tween.kill()
	_cancel_tween = create_tween()
	_cancel_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_cancel_tween.tween_method(
		_apply_rotation,
		(get_node("Pivot") as Node3D).rotation.z,
		PICKAXE_RAISED_ANGLE if _tool_id == "pickaxe" else AXE_RAISED_ANGLE,
		CANCEL_RECOVERY_DURATION
	)
	_cancel_tween.tween_callback(_finish_cancel)


func get_cancel_recovery_duration() -> float:
	return CANCEL_RECOVERY_DURATION


func _finish_cancel() -> void:
	visible = false
	_tool_id = ""


func get_tool_id() -> String:
	return _tool_id


func get_axe_head_screen_offset() -> Vector2:
	return _rotated_offset(
		_tool_head_from_handle,
		(get_node("Pivot") as Node3D).rotation.z
	) + _tool_screen_offset


func get_pickaxe_head_screen_offset() -> Vector2:
	return _rotated_offset(
		_tool_head_from_handle,
		(get_node("Pivot") as Node3D).rotation.z
	) + _tool_screen_offset


func _apply_rotation(value: float) -> void:
	(get_node("Pivot") as Node3D).rotation.z = value
	var material := (get_node("Pivot/ToolSprite") as Sprite3D).material_override as ShaderMaterial
	if _tool_id in ["axe", "pickaxe"] and material != null:
		material.set_shader_parameter("strike_angle", value)


func _configure_axe_pivot(sprite: Sprite3D, texture: Texture2D) -> void:
	_configure_painted_pivot(
		sprite,
		texture,
		AXE_PIXEL_SIZE,
		AXE_RAISED_ANGLE,
		AXE_IMPACT_ANGLE,
		_painted_head_center_uv(texture),
		true
	)


func _configure_pickaxe_pivot(sprite: Sprite3D, texture: Texture2D) -> void:
	_configure_painted_pivot(
		sprite,
		texture,
		PICKAXE_PIXEL_SIZE,
		PICKAXE_RAISED_ANGLE,
		PICKAXE_IMPACT_ANGLE,
		_painted_pickaxe_head_center_uv(texture),
		false
	)


func _configure_painted_pivot(
	sprite: Sprite3D,
	texture: Texture2D,
	pixel_size: float,
	raised_angle: float,
	impact_angle: float,
	head_uv: Vector2,
	reflect_across_handle: bool
) -> void:
	sprite.pixel_size = pixel_size
	var shader := load(TOOL_PIVOT_SHADER_PATH) as Shader
	if shader == null:
		sprite.material_override = null
		return
	var sprite_height := float(texture.get_height()) * sprite.pixel_size
	var handle_uv := _painted_handle_pivot_uv(texture)
	_tool_head_from_handle = Vector2(
		(head_uv.x - handle_uv.x) * sprite_height,
		(handle_uv.y - head_uv.y) * sprite_height
	)
	_tool_screen_offset = -_rotated_offset(_tool_head_from_handle, impact_angle)
	var material := ShaderMaterial.new()
	material.shader = shader
	material.render_priority = 10
	material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("sprite_height", sprite_height)
	material.set_shader_parameter("pivot_uv", handle_uv)
	material.set_shader_parameter("screen_offset", _tool_screen_offset)
	material.set_shader_parameter(
		"reflection_axis",
		_tool_head_from_handle.normalized() if reflect_across_handle else Vector2.ZERO
	)
	material.set_shader_parameter("strike_angle", raised_angle)
	sprite.position = Vector3.ZERO
	sprite.material_override = material


static func _painted_handle_pivot_uv(texture: Texture2D) -> Vector2:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Vector2(0.75, 0.95)
	var bounds := image.get_used_rect()
	if not bounds.has_area():
		return Vector2(0.75, 0.95)
	var band_height := maxi(4, ceili(float(bounds.size.y) * 0.05))
	var band_start := maxi(bounds.position.y, bounds.end.y - band_height)
	var weighted_x := 0.0
	var total_alpha := 0.0
	var last_painted_y := bounds.end.y - 1
	for y in range(band_start, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var alpha := image.get_pixel(x, y).a
			if alpha <= 0.10:
				continue
			weighted_x += float(x) * alpha
			total_alpha += alpha
	return Vector2(
		(weighted_x / total_alpha) / float(maxi(image.get_width() - 1, 1)) if total_alpha > 0.0 else 0.75,
		float(last_painted_y) / float(maxi(image.get_height() - 1, 1))
	)


static func _painted_head_center_uv(texture: Texture2D) -> Vector2:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Vector2(0.32, 0.30)
	var bounds := image.get_used_rect()
	if not bounds.has_area():
		return Vector2(0.32, 0.30)
	var head_max_x := bounds.position.x + ceili(float(bounds.size.x) * 0.68)
	var head_max_y := bounds.position.y + ceili(float(bounds.size.y) * 0.52)
	var weighted := Vector2.ZERO
	var total_alpha := 0.0
	for y in range(bounds.position.y, mini(head_max_y, bounds.end.y)):
		for x in range(bounds.position.x, mini(head_max_x, bounds.end.x)):
			var alpha := image.get_pixel(x, y).a
			if alpha <= 0.10:
				continue
			weighted += Vector2(x, y) * alpha
			total_alpha += alpha
	if total_alpha <= 0.0:
		return Vector2(0.32, 0.30)
	var center := weighted / total_alpha
	return Vector2(
		center.x / float(maxi(image.get_width() - 1, 1)),
		center.y / float(maxi(image.get_height() - 1, 1))
	)


static func _painted_pickaxe_head_center_uv(texture: Texture2D) -> Vector2:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Vector2(0.52, 0.25)
	var bounds := image.get_used_rect()
	if not bounds.has_area():
		return Vector2(0.52, 0.25)
	var head_max_y := bounds.position.y + ceili(float(bounds.size.y) * 0.52)
	var weighted := Vector2.ZERO
	var total_alpha := 0.0
	for y in range(bounds.position.y, mini(head_max_y, bounds.end.y)):
		for x in range(bounds.position.x, bounds.end.x):
			var alpha := image.get_pixel(x, y).a
			if alpha <= 0.10:
				continue
			weighted += Vector2(x, y) * alpha
			total_alpha += alpha
	if total_alpha <= 0.0:
		return Vector2(0.52, 0.25)
	var center := weighted / total_alpha
	return Vector2(
		center.x / float(maxi(image.get_width() - 1, 1)),
		center.y / float(maxi(image.get_height() - 1, 1))
	)


static func _rotated_offset(value: Vector2, angle: float) -> Vector2:
	var cosine := cos(angle)
	var sine := sin(angle)
	return Vector2(
		value.x * cosine - value.y * sine,
		value.x * sine + value.y * cosine
	)
