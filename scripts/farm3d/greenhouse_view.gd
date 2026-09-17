extends "res://scripts/farm3d/beehive_view.gd"

func configure(farm_session: Farm3DSession) -> void:
	building_kind = "greenhouse"
	panel_title = "温室 · 四季育苗园"
	pause_text = "关闭面板后，在外围8个玻璃种植床上开垦、播种、浇水和收获。"
	super.configure(farm_session)
	name = "GreenhouseView"
	collect_button.hide()

func refresh() -> void:
	if not is_instance_valid(building): return
	var info := session.production.get_greenhouse_snapshot(building)
	var state: String = {"working":"全年种植 · 温室增产生效", "maintenance":"维护暂停：作物保留，暂不生长", "construction":"正在建造"}.get(info.status,"")
	var lines: Array[String] = [state,"种植位 %d · 我可用 %d · 已种 %d · 成熟 %d" % [info.total,info.usable,info.planted,info.mature],
		"供水："+("水车管道已接通，全部8床自动灌溉（%d个水源）" % info.water_sources.size() if info.water_connected else "未接水车，请浇水；已有水田仍保持灌溉"),
		"全年可种，产量为露天基准的1.5～2倍（整数结算）。浇水或灌溉后生长速度1.5倍，未浇水为1倍。"]
	for i in info.plots.size():
		var plot: Dictionary = info.plots[i]
		var crop := "空床" if str(plot.crop_id).is_empty() else str(GameData.get_item(plot.crop_id).get("name",plot.crop_id))
		var timing := "已成熟" if plot.mature else ("约%d分钟" % int(plot.remaining_minutes) if int(plot.remaining_minutes)>=0 else "")
		if not plot.usable: timing = "不可使用／他人土地"
		lines.append("%d号床：%s %s%s" % [i+1,crop,timing," · 自动灌溉" if plot.automatic_water else ""])
		if not str(plot.crop_id).is_empty():
			lines.append("  生长速度×%.1f · 预计收获%d个（露天基准%d个）" % [plot.growth_multiplier,plot.expected_yield,plot.outdoor_yield])
	lines.append("\n建材基准采购价：%d金币；维护折价约%d金币／%d日。" % [info.capital_reference_cost,info.maintenance_reference_cost,info.maintenance_interval_days])
	lines.append("收益来自实际作物销售。按市场需求选择反季节作物，避免集中种植后卖不出去。预计成熟时间按当前浇水条件计算，预计产量按当前温室状态结算；欠维护时暂停生长和增产。")
	lines.append("当前为自营种植，尚未开放温室租赁；收获沿用地块所有权。")
	details.text = "\n".join(lines)
	var quote: Dictionary = info.maintenance
	maintenance_button.text = "维护：%s · %d金币" % [_counts(quote.get("materials",{})),int(quote.get("gold_cost",0))]
	maintenance_button.disabled = building.owner_id != "player" or session.production.get_maintenance_state(building) not in ["warning","overdue"]
