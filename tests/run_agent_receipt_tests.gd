extends SceneTree

const LoopState = preload("res://scripts/ai_agent/agent_loop_state.gd")
const Executor = preload("res://scripts/ai_agent/agent_action_executor_router.gd")
var checks := 0
var failures := 0

class FakeScheduler extends RefCounted:
	var _last_dispatched := {}

class FakeFarm extends RefCounted:
	func queue_batch(_intent: Dictionary, _minute: int) -> Array:
		return [{"ok":true}]

class Runtime extends Node:
	var executor = Executor.new()
	var scheduler = FakeScheduler.new()

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func run() -> void:
	var runtime := Runtime.new()
	root.add_child(runtime)
	var intent := {"agent_id":"farmer_ahe","decision_id":"decision","action_id":"plant-1","idempotency_key":"plant-1","tool_name":"plant","arguments":{"plot":0,"seed_item_id":"carrot_seed"}}
	var rejection: Dictionary = runtime.executor._failure(intent,10,"wrong_season")
	check(rejection.get("agent_id") == "farmer_ahe" and rejection.get("tool_name") == "plant","Rejected action retains actor and tool identity")
	var failed: Dictionary = runtime.executor.finalize_queued_action(intent,{"ok":false,"error":"path_blocked"},10)
	check(failed.get("tool_name") == "plant" and failed.get("arguments") == intent.arguments,"Failed queued action retains original command")
	runtime.executor._farm = FakeFarm.new()
	var queued: Array = runtime.executor._queue_visible_farm({"agent_id":"farmer_ahe","decision_id":"queue"},[{"action_id":"till-1","idempotency_key":"till-1","tool_name":"till","arguments":{"plot":1}}],10)
	check(queued[0].get("agent_id") == "farmer_ahe" and queued[0].get("tool_name") == "till","In-progress farm receipt includes actor and tool")
	for source in ["receipts","executor"]:
		var state := LoopState.new()
		var legacy := {"action_id":"old-plant","status":"rejected","failure_code":"wrong_season"}
		state.loops["old"] = {"agent_id":"farmer_ahe","state":"executing","trigger":"schedule","action_ids":["old-plant","skipped"]}
		if source == "receipts": state.loops.old.receipts = {"old-plant":legacy}
		else: runtime.executor._outcomes["old-plant"] = legacy
		state.finish_batches(runtime,11)
		check(state.loops.old.state == "closed" and state.feedback.get("farmer_ahe",{}).get("pending",false),"Legacy rejection closes and schedules recovery via "+source)
		var event: Dictionary = state.events("farmer_ahe")[0]
		check(event.payload.skipped == ["skipped"],"Remaining actions are reported skipped")
		var count := state.events("farmer_ahe").size()
		state.finish_batches(runtime,12)
		check(state.events("farmer_ahe").size() == count,"Repeated ticks do not close or retry batch twice")
	var unknown := LoopState.new()
	unknown.loops.old = {"agent_id":"farmer_ahe","state":"executing","trigger":"schedule","action_ids":["legacy-done"],"receipts":{"legacy-done":{"action_id":"legacy-done","status":"completed"}}}
	unknown.goals.test = {"goal_id":"test","actor_id":"farmer_ahe","description":"grow crops","status":"active","expires_at":100,"review_at":50}
	unknown.finish_batches(runtime,12)
	check(unknown.loops.old.state == "closed" and unknown.feedback.is_empty(),"Unknown legacy tool does not invent useful work or repeat actions")
	runtime.free()
	print("AGENT RECEIPTS: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
