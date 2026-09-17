extends "res://scripts/farm3d/beehive_view.gd"

func configure(farm_session: Farm3DSession) -> void:
	building_kind="waterwheel"
	panel_title="水车 · 岸边提水站"
	pause_text="天然河流或湖泊旁建水车，在4格范围接到温室任一种植床，即自动供水到全部8床。"
	super.configure(farm_session)
	name="WaterwheelView";collect_button.hide()

func refresh() -> void:
	if not is_instance_valid(building):return
	var info := session.production.get_waterwheel_snapshot(building)
	var lines: Array[String]=[
		str({"working":"运转中 · 自动灌溉", "maintenance":"欠维护，已停止供水", "no_water":"未连接天然水域", "construction":"建造中"}.get(info.status,"")),
		"水源：%s；普通农田供水半径：%d格" % [str(info.water_anchor) if info.water_connected else "无",info.radius],
		"正在灌溉 %d 块农田 · 连接 %d 座温室" % [info.irrigated_plots,info.greenhouses.size()]]
	for link in info.connections:
		lines.append("温室 %s：%s（接入口 %d,%d）" % [link.building_id,"8/8床供水" if link.active else "暂停供水",link.gx,link.gz])
	lines.append("\n2×2岸基必须一边紧邻天然水域；不能建在水里，水田和斜角相邻不算。石墩允许缓坡岸基，不占桥梁、树木或钓鱼点。")
	lines.append("配水管自动连接，已包含在设施中，不用另买水渠；温室不会继续向外传水。多台水车可备用，生长加速不叠加。")
	lines.append("建材基准采购价 %d金币；维护折价约%d金币／%d日。下次维护日：%d。" % [info.capital_reference_cost,info.maintenance_reference_cost,info.maintenance_interval_days,info.maintenance_due_day])
	lines.append("价值在节省浇水操作与消耗，不直接产金币或增加收获量。当前不收水费，附近农田共享供水；耕作和收获仍遵守土地归属。断水后可手动浇水，温室季节保护独立生效。")
	details.text="\n".join(lines)
	var quote: Dictionary=info.maintenance
	maintenance_button.text="维护：%s · %d金币" % [_counts(quote.get("materials",{})),int(quote.get("gold_cost",0))]
	maintenance_button.disabled=building.owner_id!="player" or session.production.get_maintenance_state(building) not in ["warning","overdue"]
