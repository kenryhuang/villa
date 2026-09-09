extends RefCounted

# Rebuildable static map data, never player progress. Source changes invalidate
# both caches; exported builds without source files simply compute the map.
const SOURCES := [
	"res://scripts/farm3d/terrain_profile.gd", "res://scripts/farm3d/golf_course_data.gd",
	"res://scripts/farm3d/flat_grid.gd", "res://scripts/farm3d/farm_minimap.gd",
	"res://scripts/systems/grid_system.gd", "res://scripts/data/grid_cell.gd",
	"res://scripts/farm3d/terrain_cache.gd",
]
static var directory := "res://data/cache/farm3d"
static var _signature := ""

static func signature() -> String:
	if not _signature.is_empty(): return _signature
	var sources := "farm3d-static-v1|" + str(Engine.get_version_info().hex)
	for path in SOURCES:
		if not FileAccess.file_exists(path): return ""
		sources += "|" + FileAccess.get_sha256(path)
	_signature = sources.sha256_text()
	return _signature

static func read(kind: String) -> Dictionary:
	if kind not in ["grid", "minimap"] or signature().is_empty(): return {}
	var path := directory.path_join(kind + ".cache")
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 33 or file.get_length() > 16000000: return {}
	var expected := file.get_buffer(32)
	var bytes := file.get_buffer(file.get_length() - 32)
	if expected != _digest(bytes): return {}
	var packet: Variant = bytes_to_var(bytes)
	if not packet is Dictionary or packet.get("signature") != signature() or not packet.get("data") is Dictionary: return {}
	return packet.data

static func write(kind: String, data: Dictionary) -> void:
	if kind not in ["grid", "minimap"] or signature().is_empty(): return
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return
	var path := directory.path_join(kind + ".cache")
	var temporary := path + ".tmp-" + str(OS.get_process_id())
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return
	var bytes := var_to_bytes({"signature": signature(), "data": data})
	file.store_buffer(_digest(bytes))
	file.store_buffer(bytes)
	var ok := file.get_error() == OK
	file.close()
	if ok: DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path))
	if FileAccess.file_exists(temporary): DirAccess.remove_absolute(temporary)

static func _digest(bytes: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish()
