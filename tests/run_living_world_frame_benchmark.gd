extends SceneTree

var scene: Node
var frames: Array[float] = []
var social_cost: Array[float] = []
var baseline := false
var started := 0
var previous := 0
var warmup := 0
var ended := false

func _initialize() -> void: setup.call_deferred()
func setup() -> void:
	baseline = "--social-baseline" in OS.get_cmdline_user_args()
	scene = load("res://scenes/farm3d/main.tscn").instantiate(); root.add_child(scene)
	var s: Farm3DSession = scene.farm_session
	if s.auto_save or s.auto_restore or s.agent_runtime.service_enabled: push_error("Isolated benchmark required"); quit(1); return
	if not baseline:
		s.save_path = "res://tmp/living-world/P12-economy-rules-137-save.json"
		if not s.load_game(): push_error("Completed populated benchmark save required"); quit(1); return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440, 960)
	s.season.set_process(false)
	if baseline: s.living_world.set_process(false)
	started = Time.get_ticks_usec(); previous = started
	process_frame.connect(sample)

func sample() -> void:
	if ended: return
	var now := Time.get_ticks_usec()
	warmup += 1
	if now - started < 10000000: previous = now; return
	frames.append(float(now - previous) / 1000.0); previous = now
	if not baseline:
		var before := Time.get_ticks_usec()
		scene.farm_session.living_world.advance()
		social_cost.append(float(Time.get_ticks_usec() - before) / 1000.0)
	if now - started < 610000000: return
	ended = true
	frames.sort(); social_cost.sort()
	var f := FileAccess.open("res://tmp/living-world/P12-frames-%s.json" % ("baseline" if baseline else "population"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"mode": "current P0 fixture without social updates" if baseline else "expanded social simulation", "renderer": RenderingServer.get_current_rendering_method(), "resolution": root.size, "device": RenderingServer.get_video_adapter_name(), "duration_seconds": float(now - started) / 1000000.0, "samples": frames.size(), "frame_p50_ms": percentile(frames, .50), "frame_p95_ms": percentile(frames, .95), "social_p95_ms": percentile(social_cost, .95), "population": scene.farm_session.living_world.society.residents.size()}, "  ")); f.close()
	if DisplayServer.get_name() != "headless": root.get_texture().get_image().save_png("res://tmp/living-world/P12-%s.png" % ("baseline" if baseline else "population"))
	print("P12 benchmark ", "baseline" if baseline else "population", " samples=", frames.size(), " p95=", percentile(frames, .95))
	quit(0)

func percentile(values: Array[float], p: float) -> float:
	return 0.0 if values.is_empty() else values[mini(values.size() - 1, int(floor(values.size() * p)))]
