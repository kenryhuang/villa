extends "res://scripts/farm3d/beehive_view.gd"
## Share the existing pause/input, collection, maintenance and save lifecycle.
var feed_one: Button
var feed_five: Button

func configure(farm_session: Farm3DSession) -> void:
	building_kind = "chicken_coop"
	panel_title = "鸡舍 · 每日鲜蛋"
	collect_text = "收取鸡蛋"
	pause_text = "关闭面板后继续养鸡，每天结算一次鸡蛋。"
	super.configure(farm_session)
	name = "ChickenCoopView"
	var box := collect_button.get_parent()
	var row := HBoxContainer.new()
	box.add_child(row)
	box.move_child(row,collect_button.get_index())
	feed_one = _button(row,"添 1 份饲料",func(): add_feed(1))
	feed_five = _button(row,"添 5 份饲料",func(): add_feed(5))
	feed_one.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_five.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _layout() -> void:
	super._layout()
	_body_scroll.custom_minimum_size.y = clampf(size.y-400,80,300)

func refresh() -> void:
	if not is_instance_valid(building): return
	var info := session.production.get_chicken_coop_snapshot(building)
	var states := {"working":"母鸡正在院内活动，等待今日产蛋", "no_feed":"饲料不足，暂不产蛋",
		"full":"蛋篮已满或放不下下一批，请先收蛋", "maintenance":"鸡舍需要维护，暂时停产", "construction":"建造中"}
	var owned := building.owner_id == "player"
	var available := session.inventory.get_item_count(str(info.feed_item))
	details.text = "%s\n\n每日消耗：饲料 ×%d → 鸡蛋 ×%d\n饲料槽：%d 份 · 背包饲料：%d 份\n蛋篮：%d / %d 枚\n\n饲料可在风车加工，也可到市场购买。\n缺料、蛋篮存满或维护期间暂停生产。" % [
		states.get(info.status,""),info.feed_per_day,info.eggs_per_day,info.feed,available,info.eggs,info.capacity]
	if not owned: details.text += "\n\n这座鸡舍属于%s，由主人管理饲料和鸡蛋。" % _owner_name(building.owner_id)
	collect_button.disabled = not owned or int(info.eggs) <= 0
	feed_one.disabled = not owned or available < 1
	feed_five.disabled = not owned or available < 5
	var quote := session.production.get_maintenance_quote(building)
	maintenance_button.text = "维护：%s · %d 金币" % [_counts(quote.get("materials",{})),int(quote.get("gold_cost",0))]
	maintenance_button.disabled = not owned or session.production.get_maintenance_state(building) not in ["warning","overdue"]

func add_feed(quantity: int) -> bool:
	if not is_instance_valid(building) or building.owner_id != "player" or not building.is_construction_complete() or quantity not in [1,5]: return false
	var added := session.production.add_input(building,"animal_feed",quantity,session.inventory)
	feedback.text = "已放入 %d 份饲料。" % quantity if added else "饲料不足，未扣除物品。"
	_save_action(added)
	refresh()
	return added

func _collect() -> void:
	if is_instance_valid(building) and building.owner_id == "player": super._collect()
