extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var trace = preload("res://scripts/ai_agent/agent_session_trace.gd").new()
	root.add_child(trace)
	trace.configure(false, "scroll-regression")
	var window = preload("res://scenes/ui/agent_debug_window.tscn").instantiate()
	root.add_child(window)
	window.configure(trace)
	window.open()
	var view: TextEdit = window.reasoning_view
	var tabs: TabContainer = view.get_parent()
	tabs.current_tab = 1
	var long_record := {"request_id":"long","reasoning":"line\n".repeat(1000)}
	var short_record := {"request_id":"short","reasoning":"line\n".repeat(84)}
	window._render_request(long_record, true)
	await process_frame
	await process_frame
	view.set_line_as_first_visible(930)
	check(view.get_first_visible_line() >= 900, "Long trace scroll reaches line 930")
	window._render_request(long_record, false)
	await process_frame
	await process_frame
	check(view.get_first_visible_line() == 930, "Refresh preserves manual reading position")
	window._render_request(long_record, true)
	await process_frame
	await process_frame
	check(view.get_last_full_visible_line() >= 998, "Follow mode still reaches the end of a long trace")
	# Replace while scrolled deep into a long trace, including a hidden tab.
	for hidden in [false, true]:
		window._render_request(long_record, true)
		await process_frame
		await process_frame
		view.set_line_as_first_visible(930)
		if hidden: tabs.current_tab = 0
		window._render_request(short_record, false)
		await process_frame
		await process_frame
		check(view.get_line_count() == 85, "New trace has 85 lines")
		check(view.get_first_visible_line() < 85, "Restored viewport stays within shorter trace")
		tabs.current_tab = 1
		await process_frame
	# Several renders in one frame must not restore an obsolete long viewport.
	window._render_request(long_record, true)
	window._render_request(short_record, false)
	window._render_request({}, true)
	await process_frame
	await process_frame
	check(view.get_first_visible_line() == 0, "Clear supersedes queued scroll restorations")
	window.queue_free()
	trace.queue_free()
	await process_frame
	print("Agent debug scroll: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
