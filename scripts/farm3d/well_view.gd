extends "res://scripts/farm3d/beehive_view.gd"

func configure(farm_session: Farm3DSession) -> void:
	building_kind="well"
	panel_title="水井 · 内陆灌溉水源"
	pause_text="先建水井，再将水车的一条边贴着水井放置；水车自动接管温室灌溉。"
	super.configure(farm_session)
	name="WellView";collect_button.hide()

func refresh() -> void:
	if not is_instance_valid(building): return
	var info := session.production.get_well_snapshot(building)
	var lines: Array[String] = [str({"available":"水源可用","maintenance":"水井维护中或已逾期，暂停供水","construction":"建造中，暂不能取水"}.get(info.status,"")),
		"占地1×1格；建造消耗木材10、石头20。无需靠近河流或湖泊。",
		"水井 → 紧邻水车 → 温室：水车的15×15格范围接到任一种植床后，即灌溉整座温室8床。",
		"水井本身不自动浇地。只支持边相邻，斜角不接通；无需额外铺管，也不收水费。"]
	for wheel in info.waterwheels:
		lines.append("水车（%d，%d）：%s · 连接%d座温室" % [wheel.gx,wheel.gz,"正在从本井取水" if wheel.using_this_well and wheel.status=="working" else "未从本井供水",wheel.greenhouses.size()])
	if info.waterwheels.is_empty(): lines.append("还没有相邻水车。请在井旁预留2×2格建造空间。")
	lines.append("建材基准采购价%d金币；维护折价约%d金币／%d日。下次维护日：%d。" % [info.capital_reference_cost,info.maintenance_reference_cost,info.maintenance_interval_days,info.maintenance_due_day])
	lines.append("井和水车都要保持维护。断供后可手动浇水，温室仍保留季节保护。当前地下水不模拟枯竭，抽水不另耗燃料。")
	details.text="\n".join(lines)
	var quote: Dictionary=info.maintenance
	maintenance_button.text="维护水井：%s · %d金币" % [_counts(quote.get("materials",{})),int(quote.get("gold_cost",0))]
	maintenance_button.disabled=building.owner_id!="player" or session.production.get_maintenance_state(building) not in ["warning","overdue"]
