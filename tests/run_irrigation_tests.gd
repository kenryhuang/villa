extends SceneTree
func _initialize() -> void:
 run.call_deferred()
func run() -> void:
 var a := preload("res://tests/test_assert.gd").new()
 preload("res://tests/test_building_economy_effects.gd").new().run(a,self)
 var ui := preload("res://tests/test_building_economy_ui.gd").new()
 await ui._test_status_view_data_and_atomic_actions(a,self)
 await ui._test_range_and_modal_lifecycle(a,self)
 ui._cleanup_nodes()
 for failure in a.failures:push_error(failure)
 print("IRRIGATION EFFECTS AND STATUS: %d checks, %d failures" % [a.checks,a.failures.size()])
 quit(0 if a.failures.is_empty() else 1)
