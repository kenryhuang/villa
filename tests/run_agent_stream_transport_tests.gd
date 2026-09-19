extends SceneTree

const Gateway = preload("res://scripts/ai_agent/agent_gateway.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(20).timeout.connect(func(): push_error("Stream transport test timeout"); quit(1))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func event(name: String, sequence: int, payload: Dictionary) -> Dictionary:
	return {"event": name, "data": {"protocol_version": 2, "stream_id": "transport:stream", "request_id": "transport", "agent_id": "lao_li", "sequence": sequence, "timestamp_msec": 1, "payload": payload}}

func wire(name: String, sequence: int, payload: Dictionary) -> String:
	return "event: %s\ndata: %s\n\n" % [name, JSON.stringify(event(name,sequence,payload).data)]

func chunk(peer: StreamPeerTCP, value: String) -> void:
	var data := value.to_utf8_buffer()
	peer.put_data(("%x\r\n" % data.size()).to_utf8_buffer())
	peer.put_data(data)
	peer.put_data("\r\n".to_utf8_buffer())

func transport(keep_alive: bool, stall_polling := false) -> void:
	var expects_success := keep_alive
	var server := TCPServer.new()
	var port := 18970
	while port < 19000 and server.listen(port,"127.0.0.1") != OK: port += 1
	check(server.is_listening(),"Local SSE fixture listens")
	if not server.is_listening(): return
	var parent := Node.new()
	root.add_child(parent)
	var gateway := Gateway.new()
	parent.add_child(gateway)
	gateway.configure("http://127.0.0.1:%d" % port,"",0,0.15)
	var result := {}
	var received: Array = []
	paused = true
	check(gateway.request_decision("lao_li",{"session_id":"transport","request_id":"transport"},func(ok,response,error): result.merge({"ok":ok,"response":response,"error":error}),func(value): received.append(value)),"Start stream while simulation is paused")
	var peer: StreamPeerTCP
	var started := Time.get_ticks_msec()
	var sent_at := -1
	var beat_at := 0
	var request_bytes := ""
	var stalled := false
	while Time.get_ticks_msec()-started < 1500 and result.is_empty():
		if peer == null and server.is_connection_available(): peer = server.take_connection()
		if peer != null:
			peer.poll()
			if peer.get_available_bytes() > 0: request_bytes += peer.get_data(peer.get_available_bytes())[1].get_string_from_utf8()
			if sent_at < 0 and request_bytes.contains("\r\n\r\n"):
				peer.put_data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\n".to_utf8_buffer())
				chunk(peer,wire("stream.started",1,{}))
				sent_at = Time.get_ticks_msec()
			if keep_alive and sent_at >= 0:
				if Time.get_ticks_msec()-beat_at >= 30:
					chunk(peer,": heartbeat\n\n"); beat_at = Time.get_ticks_msec()
				if Time.get_ticks_msec()-sent_at >= 450:
					chunk(peer,wire("decision.final",2,{"request_id":"transport","actions":[]})+wire("stream.completed",3,{}))
					keep_alive = false
			if stall_polling and sent_at >= 0:
				if not stalled and Time.get_ticks_msec()-sent_at >= 80:
					gateway._stream_client.set_process(false)
					stalled = true
				if Time.get_ticks_msec()-sent_at >= 700: gateway._stream_client.set_process(true)
		await process_frame
	paused = false
	if expects_success:
		check(result.get("ok",false),"Heartbeats and final are received during a pause longer than the idle timeout")
	else:
		check(result.get("error") == "stream_idle_timeout" and sent_at >= 0,"A truly silent connection still times out while paused")
	check(not result.is_empty(),"Transport finishes without requiring resume")
	gateway.cancel_all()
	parent.free()
	if peer != null: peer.disconnect_from_host()
	server.stop()

func run() -> void:
	await transport(true)
	await transport(false)
	await transport(true,true)
	var gateway := Gateway.new()
	root.add_child(gateway)
	gateway.configure("http://127.0.0.1:18970","",0,0.01)
	var result := {}
	gateway.request_decision("lao_li",{"session_id":"transport"},func(ok,response,error): result.merge({"ok":ok,"response":response,"error":error}))
	var client: Node = gateway._stream_client
	client.set_process(false)
	var state: Dictionary = client._streams["lao_li"]
	state.event_queue.push_many([event("decision.final",1,{"request_id":"transport"}),event("stream.completed",2,{})])
	state.last_activity_msec = Time.get_ticks_msec()-1000
	client._poll_stream("lao_li")
	check(result.get("ok",false),"Buffered final is dispatched before idle timeout after a polling stall")
	gateway.free()
	# The always-running transport must not make autonomous actions run while paused.
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	var session: Node = scene.farm_session
	check(not session.auto_save and not session.auto_restore,"Runtime fixture does not access the player save")
	scene.set_process(false); session.season.set_process(false); session.living_world.set_process(false)
	var runtime: Node = session.agent_runtime
	runtime.service_enabled = false; runtime.set_process(false)
	var actor: Node3D = runtime.farm3d_actors.farmer_ahe
	var start := actor.position
	var response := {"protocol_version":2,"request_id":"paused-transport","decision_id":"paused-transport","agent_id":"farmer_ahe","expected_revision":runtime.executor.world_revision,"decision_summary":"move after resume","speech":"",
		"actions":[{"action_id":"paused-transport:0","idempotency_key":"paused-transport:0","tool_version":1,"tool_name":"move","arguments":{"x":start.x+2,"z":start.z}}]}
	paused = true
	check(runtime.gateway.can_process(),"Actual runtime gateway continues during simulation pause")
	runtime._request_triggers["paused-transport"] = "event"
	runtime._handle_response("farmer_ahe",response)
	check(runtime._deferred_responses.size() == 1 and not runtime.activity_system.is_busy("farmer_ahe") and actor.position == start,"Autonomous final is deferred without starting an action during pause")
	paused = false
	runtime._process(0)
	check(runtime._deferred_responses.is_empty() and runtime.activity_system.is_busy("farmer_ahe"),"Resume validates and starts the deferred action")
	scene.free()
	print("STREAM TRANSPORT: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
