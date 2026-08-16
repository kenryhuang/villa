class_name CropData
extends Resource

const ENVIRONMENTS := [&"outdoor_or_greenhouse", &"greenhouse_only"]
const LIFECYCLE_TYPES := [&"annual", &"annual_regrow", &"bush", &"tree", &"vine"]

@export var crop_id := ""
@export var plant_item_id := ""
@export var name := ""
@export var crop_name := ""
@export var category := ""
@export_enum("outdoor_or_greenhouse", "greenhouse_only") var environment := "outdoor_or_greenhouse"
@export_enum("annual", "annual_regrow", "bush", "tree", "vine") var lifecycle_type := "annual"
@export var growth_days := 3
@export var seasons: Array[int] = []
@export var seed_price := 0
@export var sell_price := 0
@export var exp_reward := 0
@export var seed_drop_chance := 0.2
@export var stage_textures: Array[String] = []
@export var stage_scenes: Array[String] = []
@export var water_required := 1
@export_range(1, 999, 1) var yield_min := 1
@export_range(1, 999, 1) var yield_max := 1
@export_range(0, 999, 1) var regrow_days := 0
@export var tags: Array[String] = []
@export_enum("annual", "bush", "tree", "vine") var growth_form := "annual"


func is_valid() -> bool:
	if crop_id.strip_edges().is_empty() or plant_item_id.strip_edges().is_empty():
		return false
	if environment not in ENVIRONMENTS or lifecycle_type not in LIFECYCLE_TYPES:
		return false
	if growth_days <= 0:
		return false
	if yield_min <= 0 or yield_max < yield_min or regrow_days < 0 or regrow_days > growth_days:
		return false
	if lifecycle_type == "annual" and regrow_days != 0:
		return false
	if lifecycle_type != "annual" and regrow_days <= 0:
		return false
	if (environment == "greenhouse_only") != ("greenhouse_only" in tags):
		return false
	if lifecycle_type in ["annual", "annual_regrow"]:
		if growth_form != "annual":
			return false
	elif growth_form != lifecycle_type:
		return false
	var seen_seasons := {}
	for season in seasons:
		if season < 0 or season > 3 or seen_seasons.has(season):
			return false
		seen_seasons[season] = true
	var seen_tags := {}
	for tag in tags:
		var normalized := tag.strip_edges()
		if normalized.is_empty() or normalized != tag or seen_tags.has(tag):
			return false
		seen_tags[tag] = true
	return true
