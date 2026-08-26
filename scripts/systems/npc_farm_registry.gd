extends RefCounted

const VERSION := 1
const VALID_STATES := ["untilled", "tilled", "planted"]

var _farms: Dictionary = {}


func configure_farm(agent_id: String, plot_count: int) -> bool:
	if agent_id.is_empty() or plot_count <= 0 or plot_count > 100 or _farms.has(agent_id):
		return false
	var plots: Array[Dictionary] = []
	for index in range(plot_count):
		plots.append(_empty_plot(index, "untilled"))
	_farms[agent_id] = plots
	return true


func till(agent_id: String, plot_index: int) -> bool:
	var plot: Dictionary = _plot_ref(agent_id, plot_index)
	if plot.is_empty() or plot.state != "untilled":
		return false
	plot.state = "tilled"
	return true


func plant(
	agent_id: String,
	plot_index: int,
	crop_item_id: String,
	planted_minute: int,
	mature_minute: int,
	yield_quantity: int
) -> bool:
	var plot: Dictionary = _plot_ref(agent_id, plot_index)
	if (
		plot.is_empty() or plot.state != "tilled" or crop_item_id.is_empty()
		or planted_minute < 0 or mature_minute <= planted_minute or yield_quantity <= 0
	):
		return false
	plot.state = "planted"
	plot.crop_item_id = crop_item_id
	plot.planted_minute = planted_minute
	plot.mature_minute = mature_minute
	plot.yield_quantity = yield_quantity
	return true


func harvest(agent_id: String, plot_index: int, game_minute: int) -> Dictionary:
	var plot: Dictionary = _plot_ref(agent_id, plot_index)
	if plot.is_empty() or plot.state != "planted" or game_minute < int(plot.mature_minute):
		return {}
	var result := {"item_id": str(plot.crop_item_id), "quantity": int(plot.yield_quantity)}
	var id := int(plot.plot_index)
	var plots: Array = _farms[agent_id]
	plots[plot_index] = _empty_plot(id, "tilled")
	return result


func get_plot(agent_id: String, plot_index: int) -> Dictionary:
	return _plot_ref(agent_id, plot_index).duplicate(true)


func to_dict() -> Dictionary:
	return {"version": VERSION, "farms": _farms.duplicate(true)}


func from_dict(value: Dictionary) -> bool:
	if value.get("version") != VERSION or not value.get("farms") is Dictionary:
		return false
	var candidates: Dictionary = {}
	for agent_id_value in (value.farms as Dictionary).keys():
		var agent_id := str(agent_id_value)
		var plots_value: Variant = value.farms[agent_id_value]
		if agent_id.is_empty() or not plots_value is Array or (plots_value as Array).is_empty():
			return false
		var plots: Array[Dictionary] = []
		for plot_value in plots_value:
			if not _valid_plot(plot_value, plots.size()):
				return false
			plots.append((plot_value as Dictionary).duplicate(true))
		candidates[agent_id] = plots
	_farms = candidates
	return true


func _plot_ref(agent_id: String, plot_index: int) -> Dictionary:
	if not _farms.has(agent_id):
		return {}
	var plots: Array = _farms[agent_id]
	if plot_index < 0 or plot_index >= plots.size():
		return {}
	return plots[plot_index]


func _empty_plot(index: int, state: String) -> Dictionary:
	return {"plot_index": index, "state": state, "crop_item_id": "", "planted_minute": 0, "mature_minute": 0, "yield_quantity": 0}


func _valid_plot(value: Variant, expected_index: int) -> bool:
	if not value is Dictionary:
		return false
	var plot := value as Dictionary
	return (
		int(plot.get("plot_index", -1)) == expected_index
		and VALID_STATES.has(str(plot.get("state", "")))
		and typeof(plot.get("crop_item_id")) == TYPE_STRING
		and int(plot.get("planted_minute", -1)) >= 0
		and int(plot.get("mature_minute", -1)) >= 0
		and int(plot.get("yield_quantity", -1)) >= 0
	)
