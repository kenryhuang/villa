class_name BuildingMaintenanceCard
extends VBoxContainer

const REPAIR_DURATION_SECONDS := 3.0

@onready var state_dot: ColorRect = $Header/StateDot
@onready var state_label: Label = $Header/StateLabel
@onready var deadline_label: Label = $DeadlineLabel
@onready var costs: HBoxContainer = $Costs
@onready var gold_label: Label = $Costs/GoldLabel
@onready var wood_label: Label = $Costs/WoodLabel
@onready var stone_label: Label = $Costs/StoneLabel
@onready var repair_progress: ProgressBar = $RepairProgress
@onready var action_button: Button = $ActionButton
@onready var feedback_label: Label = $FeedbackLabel

var maintenance_state := "normal"
var _production: ProductionSystem
var _inventory: InventorySystem
var _progression: EconomyProgressionSystem
var _building_ref: WeakRef


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not action_button.pressed.is_connected(_on_action_pressed):
		action_button.pressed.connect(_on_action_pressed)
	set_process(false)


func configure(
	production: ProductionSystem,
	inventory: InventorySystem,
	progression: EconomyProgressionSystem
) -> bool:
	if production == null or inventory == null or progression == null:
		return false
	_production = production
	_inventory = inventory
	_progression = progression
	refresh()
	return true


func show_building(building: BuildingInstance) -> void:
	_building_ref = weakref(building) if building != null else null
	feedback_label.text = "" if is_node_ready() else ""
	refresh()


func refresh() -> void:
	if not is_node_ready():
		return
	var building := _building()
	if building == null or _production == null or _inventory == null or _progression == null:
		visible = false
		set_process(false)
		return
	visible = true
	var snapshot := _production.get_building_snapshot(building)
	maintenance_state = str(snapshot.get("maintenance_state", "normal"))
	var days_remaining := int(snapshot.get("maintenance_days_remaining", -1))
	var remaining_seconds := float(snapshot.get("repair_remaining_seconds", 0.0))
	var quote := _progression.get_maintenance_quote(building)
	var wallet := get_node_or_null("/root/GameState")
	var gold_owned := int(wallet.gold) if wallet != null else 0
	var gold_needed := int(quote.get("gold_cost", 0))
	var materials := quote.get("materials", {}) as Dictionary
	var wood_owned := _inventory.get_item_count("wood")
	var stone_owned := _inventory.get_item_count("stone")
	var wood_needed := int(materials.get("wood", 0))
	var stone_needed := int(materials.get("stone", 0))
	_set_cost_label(gold_label, "金币", gold_owned, gold_needed)
	_set_cost_label(wood_label, "木材", wood_owned, wood_needed)
	_set_cost_label(stone_label, "石材", stone_owned, stone_needed)
	var affordable := (
		gold_owned >= gold_needed
		and wood_owned >= wood_needed
		and stone_owned >= stone_needed
		and not quote.is_empty()
	)
	match maintenance_state:
		"warning":
			state_dot.color = Color("d39b35")
			state_label.text = "维护预警"
			deadline_label.text = "明天需要维护，当前仍可生产"
			action_button.text = "提前维修"
			action_button.visible = true
			action_button.disabled = not affordable
			repair_progress.visible = false
		"overdue":
			state_dot.color = Color("c95f52")
			state_label.text = "破损停产"
			deadline_label.text = "建筑破损，生产已暂停"
			action_button.text = "开始维修"
			action_button.visible = true
			action_button.disabled = not affordable
			repair_progress.visible = false
		"repairing":
			state_dot.color = Color("568bc5")
			state_label.text = "维修中"
			deadline_label.text = "维修中 %.1f 秒" % remaining_seconds
			action_button.text = "维修中"
			action_button.visible = true
			action_button.disabled = true
			repair_progress.visible = true
			repair_progress.value = REPAIR_DURATION_SECONDS - remaining_seconds
		_:
			state_dot.color = Color("579f6c")
			state_label.text = "状态正常"
			deadline_label.text = "距维护还有 %d 天" % maxi(days_remaining, 0)
			action_button.visible = false
			repair_progress.visible = false
	set_process(maintenance_state == "repairing")
	if action_button.visible and action_button.disabled and maintenance_state != "repairing":
		feedback_label.text = _missing_text(
			gold_owned, gold_needed, wood_owned, wood_needed, stone_owned, stone_needed
		)
	elif maintenance_state != "repairing" and feedback_label.text.begins_with("还缺"):
		feedback_label.text = ""


func _on_action_pressed() -> void:
	refresh()
	if action_button.disabled:
		return
	var building := _building()
	if building == null or not _progression.maintain(building):
		feedback_label.text = "建筑状态已变化，请刷新"
		refresh()
		return
	feedback_label.text = "维修已开始"
	refresh()


func _process(_delta: float) -> void:
	if maintenance_state == "repairing":
		refresh()


func _building() -> BuildingInstance:
	if _building_ref == null:
		return null
	var value = _building_ref.get_ref()
	return value as BuildingInstance if value != null and is_instance_valid(value) else null


func _set_cost_label(label: Label, title: String, owned: int, needed: int) -> void:
	label.text = "%s %d/%d" % [title, owned, needed]
	label.modulate = Color("b64f48") if owned < needed else Color("5e6f5a")


func _missing_text(
	gold_owned: int,
	gold_needed: int,
	wood_owned: int,
	wood_needed: int,
	stone_owned: int,
	stone_needed: int
) -> String:
	var missing: Array[String] = []
	if gold_owned < gold_needed:
		missing.append("金币 %d" % (gold_needed - gold_owned))
	if wood_owned < wood_needed:
		missing.append("木材 %d" % (wood_needed - wood_owned))
	if stone_owned < stone_needed:
		missing.append("石材 %d" % (stone_needed - stone_owned))
	return "还缺%s" % "、".join(missing)
