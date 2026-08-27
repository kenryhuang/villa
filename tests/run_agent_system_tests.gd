extends SceneTree

const AgentWorldStateTest = preload("res://tests/test_agent_world_state.gd")
const AgentActionExecutionTest = preload("res://tests/test_agent_action_execution.gd")
const AgentRuntimeTest = preload("res://tests/test_agent_runtime.gd")
const AgentMainIntegrationTest = preload("res://tests/test_agent_main_integration.gd")
const AgentClientConfigTest = preload("res://tests/test_agent_client_config.gd")
const AgentStreamingTest = preload("res://tests/test_agent_streaming.gd")
const AgentStreamEventQueueTest = preload("res://tests/test_agent_stream_event_queue.gd")
const AgentDebugWindowTest = preload("res://tests/test_agent_debug_window.gd")
const AgentDialogueUiTest = preload("res://tests/test_agent_dialogue_ui.gd")
const VisibleAgentNpcDialogueTest = preload("res://tests/test_visible_agent_npc_dialogue.gd")
const TestAssertScript = preload("res://tests/test_assert.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var assertions := TestAssertScript.new()
	var config_test := AgentClientConfigTest.new()
	config_test.run(assertions)
	var streaming_test := AgentStreamingTest.new()
	streaming_test.run(assertions)
	var stream_queue_test := AgentStreamEventQueueTest.new()
	stream_queue_test.run(assertions)
	var test := AgentWorldStateTest.new()
	test.run(assertions, self)
	var action_test := AgentActionExecutionTest.new()
	action_test.run(assertions, self)
	var runtime_test := AgentRuntimeTest.new()
	runtime_test.run(assertions, self)
	var integration_test := AgentMainIntegrationTest.new()
	integration_test.run(assertions, self)
	var debug_window_test := AgentDebugWindowTest.new()
	await debug_window_test.run(assertions, self)
	var dialogue_ui_test := AgentDialogueUiTest.new()
	await dialogue_ui_test.run(assertions, self)
	var visible_npc_test := VisibleAgentNpcDialogueTest.new()
	visible_npc_test.run(assertions, self)
	if assertions.failures.is_empty():
		print("PASS: %d Agent system checks" % assertions.checks)
		quit(0)
		return
	for failure in assertions.failures:
		push_error(failure)
	print("FAIL: %d of %d Agent system checks failed" % [assertions.failures.size(), assertions.checks])
	quit(1)
