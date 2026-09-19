extends SceneTree

var checks := 0
var failures := 0
var s: Node
var w: Node
var r: Node

func _initialize() -> void:
	create_timer(150).timeout.connect(func(): push_error("Social/navigation timeout"); quit(1))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func action(key: String, kind: String, actor := "xiao_hua") -> Dictionary:
	return {"action_id":key,"idempotency_key":key,"tool_name":"start_leisure","arguments":{"activity":kind,"partner_id":actor}}

func finish_activity(key: String) -> void:
	var id := "leisure-" + key.sha256_text().substr(0,24)
	var a: Dictionary = w.work.activities[id]
	a.status = "working"; a.worked = w.work.activity_minutes(a.kind)
	w.work._advance_activity(a)
	check(a.status == "completed","Actual work completion: " + key)

func run() -> void:
	var scene: Node = load("res://scenes/farm3d/main.tscn").instantiate()
	root.add_child(scene)
	s = scene.farm_session; w = s.living_world; r = s.agent_runtime
	scene.set_process(false); s.season.set_process(false); w.set_process(false); r.set_process(false)
	s.save_path = "user://social_navigation_test.json"
	check(not s.auto_save and not s.auto_restore,"Test is isolated from player save")
	w.assets.apply("xiao_hua",{"bread":5},0)
	# Reproduce the trace: multiple time-consuming leisure actions in one batch.
	var intent := {"agent_id":"xiao_hua","decision_id":"sequential","request_id":"sequential","expected_revision":r.executor.world_revision,
		"actions":[action("first-rest","rest"),action("then-eat","eat"),action("then-sleep","sleep")]}
	var outcomes: Array = r.executor.execute_batch(intent,w.minute())
	check(outcomes.size() == 1 and outcomes[0].status == "in_progress","First activity stays in_progress; later actions do not conflict")
	check(r.executor.has_pending_continuation("xiao_hua"),"Remaining batch waits for actual work")
	var query: Dictionary = r.world_queries.read(r,"xiao_hua","query_world",{"domain":"self","section":"activity"})
	check(query.data.activity.schedule.activities[0].remaining_work_minutes == 60,"Live query exposes active activity and remaining work")
	check(s.save_game() and s.load_game(),"Active activity plus continuation survives full save/reload")
	finish_activity("first-rest")
	outcomes = r.executor.complete_due(w.minute())
	check(outcomes.size() == 2 and outcomes[0].status == "completed" and outcomes[1].status == "in_progress","Completion resumes exactly the next action")
	finish_activity("then-eat")
	outcomes = r.executor.complete_due(w.minute())
	check(outcomes.size() == 2 and outcomes[1].arguments.activity == "sleep","Third action starts only after eating")
	finish_activity("then-sleep")
	outcomes = r.executor.complete_due(w.minute())
	check(outcomes.size() == 1 and outcomes[0].status == "completed" and not w.work.occupied("xiao_hua"),"Final completion releases schedule")
	check(r.executor.complete_due(w.minute()).is_empty(),"Completion is emitted once")
	# Expiration must cancel continuation rather than executing the next step.
	intent.decision_id = "cancelled"; intent.actions = [action("expired","rest"),action("never-start","sleep")]
	r.executor.execute_batch(intent,w.minute())
	w.work.activities["leisure-"+"expired".sha256_text().substr(0,24)].deadline = w.minute()
	w.work.advance()
	outcomes = r.executor.complete_due(w.minute())
	check(outcomes.size() == 1 and outcomes[0].status == "failed" and outcomes[0].failure_code == "activity_deadline" and not r.executor._outcomes.has("never-start"),"Failed activity stops dependent actions with an actionable reason")
	# Map names are actual navigation data, not fabricated lake-center coordinates.
	for name in ["南湖","湖边","高尔夫","农庄","森林","峡谷","平原","市集","合作社","旅店"]:
		var found: Dictionary = r.world_queries.read(r,"xiao_hua","query_map",{"query":name})
		check(found.ok and found.items.size() == 1,"Resolve place name: " + name)
		if found.items.size() != 1: continue
		var place: Dictionary = found.items[0]
		check(not place.position.is_empty() and place.reachable and place.navigation_action.get("tool_name") == "move","Reachable move action: " + name)
		if not place.position.is_empty(): check(s.grid.is_navigation_cell_walkable(s.grid.world_to_grid(place.position.x,place.position.z)),"Dry walkable landing: " + name)
	var lake: Dictionary = r.world_queries.read(r,"xiao_hua","query_world",{"domain":"map","id":"南湖"}).items[0]
	check(lake.id == "lake" and lake.position.z < 90,"Exact Chinese id resolves lake north shore")
	var all: Dictionary = r.world_queries.read(r,"xiao_hua","query_map",{})
	check(all.total_matches > 10 and all.next_cursor == 10,"Place catalog paginates")
	var move := {"agent_id":"xiao_hua","decision_id":"map-move","action_id":"map-move","idempotency_key":"map-move","tool_name":"move","arguments":lake.navigation_action.arguments}
	check(r.executor.execute(move,w.minute()).status == "in_progress","Returned navigation arguments execute through existing move")
	# Affection: real evidence, per-day cap, idempotency and org filtering.
	var rel = w.relationships
	var trade := {"agent_id":"farmer_ahe","tool_name":"propose_trade","action_id":"affection-offer","decision_id":"affection-offer","idempotency_key":"affection-offer",
		"arguments":{"target_actor_id":"lao_li","give":{"items":{"grain":1},"gold":0},"receive":{"items":{},"gold":1},"expires_in_minutes":60,"note":"公平交易"}}
	w.assets.apply("farmer_ahe",{"grain":2},0)
	var offered: Dictionary = r.interaction_system.execute(trade,w.minute())
	check(offered.ok,"Create real trade offer for affection regression")
	rel.advance()
	check(rel.view("farmer_ahe","lao_li").affinity == 0,"Merely offering a trade gives no affection")
	if offered.ok:
		var settled: Dictionary = r.interaction_system.execute({"agent_id":"lao_li","tool_name":"accept_trade","action_id":"affection-accept","decision_id":"affection-accept","idempotency_key":"affection-accept","arguments":{"offer_id":offered.offer_id}},w.minute())
		check(settled.ok,"Real counterpart settles trade")
		rel.advance(); rel.advance()
		check(rel.view("farmer_ahe","lao_li").affinity == 1,"Settled event awards once even after repeated advance")
	var left: Node3D = w.actor("lao_li")
	var right: Node3D = w.actor("farmer_ahe")
	left.position = Vector3(-10.5,0,-10.5); right.position = left.position + Vector3(1,0,0)
	check(w.work.start_activity("lao_li","actual-company","companionship","farmer_ahe").ok,"Schedule actual companionship")
	check(rel.view("farmer_ahe","lao_li").affinity == 1,"Queued companionship does not award early")
	var together: Dictionary = w.work.activities["actual-company"]
	together.status = "working"; together.worked = 60
	w.work._advance_activity(together)
	check(together.status == "completed" and rel.view("farmer_ahe","lao_li").affinity == 5,"Completed physical companionship gains affection")
	check(w.work.start_activity("lao_li","single-date","date","farmer_ahe").ok,"Two singles can actually start a date without a confirmed relationship")
	together = w.work.activities["single-date"]; together.status = "working"; together.worked = 60
	w.work._advance_activity(together)
	check(together.status == "completed" and rel.partner("lao_li").is_empty(),"Dating is not automatic formal confirmation")
	check(rel.award("xiao_hua","player","trade","trade-proof"),"Actual trade evidence gains affection")
	check(not rel.award("xiao_hua","player","trade","trade-proof"),"Replay cannot award twice")
	check(not rel.award("xiao_hua","village_inn","trade","org-trade"),"Organization accounts do not get romance scores")
	check(rel.award("xiao_hua","player","comfort","comfort-proof") and rel.view("player","xiao_hua").affinity == 4,"Recipient gains affection from comfort")
	rel.award("xiao_hua","player","companionship","company-proof")
	check(not rel.award("xiao_hua","player","promise_kept","cap-proof"),"Daily cap prevents repetitive farming")
	check(rel.date_blocker("xiao_hua","player").is_empty() and rel.eligibility("xiao_hua","player") == "affinity_too_low","Single people can date before formal relationship threshold")
	# Build real shared history across days rather than directly setting scores.
	for day in range(1,12):
		rel.award("xiao_hua","player","companionship","company-a-%d"%day,day*1080)
		rel.award("xiao_hua","player","companionship","company-b-%d"%day,day*1080)
	var args := {"player_quote":"我想和你正式成为恋人，你愿意吗？","decision":"confirm","note":"我也愿意和你认真交往。"}
	check(not rel.command("xiao_hua","resolve_relationship_dialogue",args,"no-dialogue").ok,"Background loop cannot supply player consent")
	r._build_loop_request("xiao_hua","romance-talk","dialogue",w.minute(),args.player_quote)
	r._handle_response("xiao_hua",{"protocol_version":2,"agent_id":"xiao_hua","request_id":"romance-talk","decision_id":"real-dialogue","expected_revision":r.executor.world_revision,"decision_summary":"双方确认关系","speech":"我也愿意认真和你交往。","actions":[{"action_id":"real-dialogue","idempotency_key":"real-dialogue","tool_name":"resolve_relationship_dialogue","tool_version":1,"arguments":args}]})
	if r.executor._outcomes.get("real-dialogue",{}).get("status") != "completed": print("DIALOGUE DIAG ",r.executor._outcomes.get("real-dialogue",{})," loop=",r.loop_state.loops.get("romance-talk")," pending=",r.loop_state.pending.get("xiao_hua",{}).get("decision-rejected:romance-talk"))
	check(r.executor._outcomes.get("real-dialogue",{}).get("status") == "completed" and rel.dialogue.is_empty(),"Runtime binds actual player utterance only during the dialogue action")
	check(rel.partner("player") == "xiao_hua" and rel.view("player","xiao_hua").label == "女朋友","Confirmed relation is available to subsequent dialogue")
	var before_repeat: Dictionary = rel.pairs.duplicate(true)
	var before_proposals: Dictionary = rel.proposals.duplicate(true)
	var before_sequence: int = r.event_store.get_last_sequence()
	rel.dialogue = {"actor":"xiao_hua","request_id":"reminder","text":args.player_quote}
	var repeated: Dictionary = rel.command("xiao_hua","resolve_relationship_dialogue",args,"repeat-confirmation")
	check(repeated.get("already_confirmed",false) and repeated.ok,"Repeated confirmation acknowledges the existing relationship")
	check(rel.pairs==before_repeat and rel.proposals==before_proposals and r.event_store.get_last_sequence()==before_sequence,"Repeated confirmation adds no proposal, affinity, version or event")
	rel.dialogue = {}
	check(not rel.command("xiao_hua","resolve_relationship_dialogue",args,"repeat-without-dialogue").ok,"Already dating still does not authorize background player dialogue")
	check(not rel.date_blocker("xiao_hua","afu_shui").is_empty(),"Existing partner prevents dating a third person")
	check(r.get_player_interactions("xiao_hua").all(func(p): return p.interaction_type != "romance"),"No dedicated romance card or button")
	check(rel.validate(rel.to_dict()),"Relationship persistence validates")
	var saved: Dictionary = rel.to_dict()
	rel.restore({}); rel.restore(saved)
	check(rel.partner("player") == "xiao_hua" and rel.to_dict() == saved,"Scores, experiences and relationship survive reload")
	args = {"player_quote":"我们分手吧。","decision":"end","note":"尊重你的选择。"}
	rel.dialogue = {"actor":"xiao_hua","request_id":"end-talk","text":args.player_quote}
	check(rel.command("xiao_hua","resolve_relationship_dialogue",args,"end-dialogue").ok and rel.partner("player").is_empty(),"Player can end relationship through dialogue")
	rel.dialogue = {}
	for day in range(1,10):
		rel.award("afu_shui","resident_mei","companionship","npc-a-%d"%day,day*1080)
		rel.award("afu_shui","resident_mei","companionship","npc-b-%d"%day,day*1080)
	var proposal: Dictionary = rel.command("afu_shui","propose_relationship",{"target_actor_id":"resident_mei","note":"你愿意和我认真交往吗？"},"npc-proposal")
	check(proposal.ok and rel.partner("afu_shui").is_empty(),"NPC proposal never auto-confirms")
	if proposal.ok:
		check(not rel.command("resident_yun","respond_relationship",{"proposal_id":proposal.proposal_id,"version":1,"accept":true},"wrong-recipient").ok,"Third person cannot accept someone else's proposal")
		check(rel.command("resident_mei","respond_relationship",{"proposal_id":proposal.proposal_id,"version":1,"accept":true},"npc-response").ok,"NPC recipient independently accepts")
		check(rel.partner("afu_shui") == "resident_mei","NPC relationship is persistent")
	check(rel.validate(JSON.parse_string(JSON.stringify(rel.to_dict()))),"JSON numeric decoding preserves valid relationship receipts")
	check(s.save_game() and s.load_game(),"Full world save retains social data and pending map movement")
	var old_society: Dictionary = w.society.to_dict()
	old_society.residents.farmer_ahe.name = "阿禾"
	w.society.restore(old_society)
	check(w.actor_name("farmer_ahe") == "阿园", "Old resident display name adopts authored rename without replacing save")
	check(w.relationships.profile("farmer_ahe").age == 22 and w.relationships.profile("farmer_ahe").gender == "female", "Relationship system uses updated adult character profile")
	var old: Dictionary = w.to_dict(); old.version = 7; old.erase("relationships"); old.erase("character_overrides")
	check(w.validate(old),"World save before relationship feature still validates")
	scene.free()
	print("SOCIAL NAVIGATION: %d checks, %d failures" % [checks,failures])
	quit(0 if failures == 0 else 1)
