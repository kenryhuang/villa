extends RefCounted

## Affection belongs to people, not accounts. A proposal is never consent.
const TOOLS := ["resolve_relationship_dialogue", "propose_relationship", "respond_relationship", "end_relationship", "express_support"]
const GAINS := {"trade": 1, "promise_kept": 3, "hosted_activity": 1, "shared_activity": 2, "visit": 2, "companionship": 4, "date": 4, "comfort": 3}
const PERSONAL := ["shared_activity", "visit", "companionship", "date", "comfort"]
const THRESHOLD := 60
const DAILY_CAP := 8
const CONFIG := "res://data/living_world/social_profiles.json"
var world: Node
var profiles: Dictionary
var pairs := {}
var proposals := {}
var processed := {}
var results := {}
var daily := {}
var event_cursor := 0
## Ephemeral provenance, bound only while executing the current dialogue reply.
var dialogue := {}

func configure(owner: Node) -> void:
	world = owner
	profiles = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	event_cursor = world.session.agent_runtime.event_store.get_last_sequence()

func person(id: String) -> bool:
	return id == "player" or world.society.config.residents.any(func(r): return r.id == id)

func profile(id: String) -> Dictionary:
	if world.character_overrides.has(id): return world.character_overrides[id].soul.social_profile.duplicate(true)
	return profiles.defaults.merged(profiles.actors.get(id, {}), true).duplicate(true) if person(id) else {}

func pair_key(a: String, b: String) -> String:
	return "|".join([a, b] if a < b else [b, a])

func _pair(a: String, b: String) -> Dictionary:
	var key := pair_key(a, b)
	if pairs.has(key): return pairs[key]
	return {"participants": [a, b] if a < b else [b, a], "affinity": {a: 0, b: 0}, "shared_counts": {}, "status": "none", "version": 1, "since": -1, "cooldown_until": 0}

func partner(actor: String) -> String:
	for p in pairs.values():
		if p.status == "dating" and actor in p.participants:
			return p.participants[1] if p.participants[0] == actor else p.participants[0]
	return ""

func eligibility(a: String, b: String) -> String:
	if a == b or not person(a) or not person(b): return "invalid_person"
	for id in [a, b]:
		var p := profile(id)
		if int(p.age) < 18: return "adults_only"
		if int(p.romance_interest) <= 0: return "not_seeking_romance"
		if not partner(id).is_empty(): return "already_in_relationship"
	var pair := _pair(a, b)
	if world.minute() < int(pair.cooldown_until): return "respect_relationship_cooldown"
	if int(pair.affinity[a]) < THRESHOLD or int(pair.affinity[b]) < THRESHOLD: return "affinity_too_low"
	var shared := 0
	for kind in PERSONAL: shared += int(pair.shared_counts.get(kind, 0))
	if shared < 3: return "personal_time_required"
	return ""

func date_blocker(a: String, b: String) -> String:
	if a == b or not person(a) or not person(b): return "invalid_person"
	for id in [a,b]:
		if int(profile(id).age) < 18: return "adults_only"
		if int(profile(id).romance_interest) <= 0: return "not_seeking_romance"
		if not partner(id).is_empty() and partner(id) not in [a,b]: return "already_in_relationship"
	if world.minute() < int(_pair(a,b).cooldown_until): return "respect_relationship_cooldown"
	return ""

func view(actor: String, target: String) -> Dictionary:
	if not person(actor) or not person(target) or actor == target: return {"error": "invalid_person"}
	var p := _pair(actor, target)
	var score := int(p.affinity[actor])
	var label := "恋人" if p.status == "dating" else ("亲密朋友" if score >= 55 else "朋友" if score >= 30 else "熟悉" if score >= 15 else "相识")
	var gender := str(profile(target).gender)
	if p.status == "dating" and gender in ["female", "male"]: label = "女朋友" if gender == "female" else "男朋友"
	return {"actor_id": target, "affinity": score, "mutual_affinity": int(p.affinity[target]), "trust": world.session.agent_runtime.agreement_system.get_relationship(actor, target),
		"status": p.status, "label": label, "shared_counts": p.shared_counts.duplicate(true), "version": p.version,
		"proposal_blocker": eligibility(actor, target), "date_blocker": date_blocker(actor,target), "dating_threshold": THRESHOLD, "requires_explicit_acceptance": true}

func context(actor: String) -> Dictionary:
	return {"profile": profile(actor), "partner_id": partner(actor), "relationships": pairs.values().filter(func(p): return actor in p.participants).map(func(p): return view(actor, p.participants[1] if p.participants[0] == actor else p.participants[0])),
		"proposals": offers(actor), "romance_need": snappedf(float(world.society.residents.get(actor, {}).get("needs", {}).get("companionship", 0)) * int(profile(actor).get("romance_interest", 0)) / 100.0, .1),
		"rules": "好感0..100；真实成交、履约、共同活动、陪伴和安慰积累好感，同一对每天最多8点、同类最多2次。双方单身即可自愿约会了解彼此，无需先确立恋人身份；已确认的恋人也可继续约会。双方好感至少60且有3次私人相处才可确认恋人，对话表达和回应即可，没有专门关系按钮；玩家明确的当轮意愿通过resolve_relationship_dialogue记录。尊重拒绝，一天内不重复追求。分手任一方可提出。陪伴/约会使用start_leisure，安慰使用express_support；不要用空口承诺刷好感。"}

func offers(actor: String) -> Array:
	return proposals.values().filter(func(p): return actor in [p.proposer_id, p.recipient_id]).map(func(p): return p.duplicate(true))

func award(a: String, b: String, kind: String, source: String, minute: int = -1) -> bool:
	if a == b or not person(a) or not person(b) or not GAINS.has(kind) or source.is_empty(): return false
	var key := pair_key(a, b) + ":" + source
	if processed.has(key): return false
	processed[key] = true
	if minute < 0: minute = world.minute()
	var day_key := "%d:%s" % [minute / 1080, pair_key(a, b)]
	var used: Dictionary = daily.get(day_key, {"total": 0, "kinds": {}})
	if int(used.total) >= DAILY_CAP or int(used.kinds.get(kind, 0)) >= 2: return false
	var gain := mini(int(GAINS[kind]), DAILY_CAP - int(used.total))
	used.total = int(used.total) + gain
	used.kinds[kind] = int(used.kinds.get(kind, 0)) + 1
	daily[day_key] = used
	var pair := _pair(a, b)
	# Comfort mainly changes the recipient's affection for the supporter.
	pair.affinity[a] = mini(100, int(pair.affinity[a]) + (mini(1, gain) if kind == "comfort" else gain))
	pair.affinity[b] = mini(100, int(pair.affinity[b]) + gain)
	pair.shared_counts[kind] = int(pair.shared_counts.get(kind, 0)) + 1
	pair.version += 1
	pairs[pair_key(a, b)] = pair
	_event("AffectionChanged", source + ":" + pair_key(a, b), [a, b], {"kind": kind, "gain": gain, "affinity": pair.affinity.duplicate(true), "source": source}, false)
	return true

func advance() -> void:
	var store = world.session.agent_runtime.event_store
	for e in store.get_events_after(event_cursor):
		event_cursor = maxi(event_cursor, int(e.global_sequence))
		var p: Dictionary = e.payload
		if e.event_type == "TradeSettled": award(str(p.proposer_id), str(p.recipient_id), "trade", e.event_id, int(e.game_minute))
		elif e.event_type == "AgreementCompleted":
			var members: Array = e.visibility.actor_ids
			for i in members.size():
				for j in range(i + 1, members.size()): award(members[i], members[j], "promise_kept", e.event_id, int(e.game_minute))
	for proposal in proposals.values():
		if proposal.status == "proposed" and world.minute() >= int(proposal.expires_at):
			proposal.status = "expired"; proposal.version += 1
			_event("RelationshipProposalExpired", proposal.proposal_id + ":expired", [proposal.proposer_id, proposal.recipient_id], proposal)
		elif proposal.status == "proposed" and proposal.recipient_id != "player" and proposal.recipient_id not in world.society.focus and world.minute() >= int(proposal.created_at) + 60:
			# Background residents have their own authored preferences; focus NPCs
			# respond through their LLM; player choices come from actual dialogue.
			var target := str(proposal.recipient_id)
			var preference := profile(target)
			var willing: bool = int(preference.romance_interest) >= 40 and int(_pair(target, proposal.proposer_id).affinity[target]) >= int(preference.get("accept_affinity_threshold", 65)) and eligibility(target, proposal.proposer_id).is_empty()
			_respond(target, {"proposal_id": proposal.proposal_id, "version": proposal.version, "accept": willing})

static func valid_command(tool: String, a: Dictionary) -> bool:
	var id_ok: bool = a.get("target_actor_id") is String and a.target_actor_id.length() in range(1, 161)
	match tool:
		"resolve_relationship_dialogue": return a.size() == 3 and a.get("player_quote") is String and a.player_quote.length() in range(1, 8001) and a.get("decision") in ["confirm", "decline", "end"] and a.get("note") is String and a.note.length() in range(1,501)
		"propose_relationship": return a.size() == 2 and id_ok and a.get("note") is String and a.note.length() in range(1, 501)
		"end_relationship": return a.size() == 2 and id_ok and a.get("reason") is String and a.reason.length() in range(1, 501)
		"express_support": return a.size() == 2 and id_ok and a.get("text") is String and a.text.length() in range(1, 501)
		"respond_relationship": return a.size() == 3 and a.get("proposal_id") is String and a.proposal_id.length() in range(1, 161) and preload("res://scripts/systems/npc_project_system.gd")._count(a.get("version"),1,1000000) and a.get("accept") is bool
	return false

func command(actor: String, tool: String, a: Dictionary, key: String, player_confirmed := false) -> Dictionary:
	if not person(actor) or not valid_command(tool, a) or key.is_empty(): return {"ok": false, "error": "invalid_relationship_command"}
	if actor == "player" and not player_confirmed: return {"ok": false, "error": "player_confirmation_required"}
	var intent := {"actor": actor, "tool": tool, "arguments": a.duplicate(true)}
	if results.has(key): return results[key].result.duplicate(true) if results[key].intent == intent else {"ok": false, "error": "idempotency_conflict"}
	advance()
	var result: Dictionary
	match tool:
		"resolve_relationship_dialogue": result = _resolve_dialogue(actor,a,key)
		"propose_relationship": result = _propose(actor, a, key)
		"respond_relationship": result = _respond(actor, a)
		"end_relationship": result = _end(actor, a)
		"express_support": result = _support(actor, a, key)
	if result.get("ok", false): result.mutated = true
	results[key] = {"intent": intent, "result": result.duplicate(true)}
	return result

func _resolve_dialogue(actor: String, a: Dictionary, key: String) -> Dictionary:
	if actor == "player" or dialogue.get("actor") != actor or str(dialogue.get("request_id", "")).is_empty() or str(dialogue.get("text", "")).strip_edges() != str(a.player_quote).strip_edges():
		return {"ok":false,"error":"current_player_dialogue_required"}
	if a.decision == "end": return _end("player", {"target_actor_id":actor,"reason":a.player_quote})
	# A current-dialogue reminder of an existing relationship is a no-op.
	# Do not open another proposal, increase affinity or emit confirmation again.
	if a.decision == "confirm" and partner(actor) == "player":
		return {"ok":true,"already_confirmed":true,"message":"双方已经是恋人，无需重复确认。"}
	var pending: Array = offers(actor).filter(func(p): return p.status == "proposed" and "player" in [p.proposer_id,p.recipient_id])
	if not pending.is_empty():
		var p: Dictionary = pending[-1]
		return _respond(str(p.recipient_id), {"proposal_id":p.proposal_id,"version":p.version,"accept":a.decision == "confirm"})
	if a.decision == "decline":
		var pair := _pair(actor,"player")
		pair.cooldown_until = world.minute() + 1080
		pairs[pair_key(actor,"player")] = pair
		_event("RelationshipDeclined",key,[actor,"player"],{"note":a.note,"player_quote":a.player_quote})
		return {"ok":true,"message":"已在对话中说明暂不确定恋人关系。"}
	# The quote carries the player's explicit request; this tool call is the
	# NPC's independent acceptance, with the same affection/exclusivity checks.
	var proposed := _propose("player", {"target_actor_id":actor,"note":a.player_quote.left(500)},key)
	if not proposed.ok: return proposed
	return _respond(actor, {"proposal_id":proposed.proposal_id,"version":1,"accept":true})

func _propose(actor: String, a: Dictionary, key: String) -> Dictionary:
	var target := str(a.target_actor_id)
	var reason := eligibility(actor, target)
	if not reason.is_empty(): return {"ok": false, "error": reason}
	if proposals.values().any(func(p): return p.status == "proposed" and pair_key(p.proposer_id, p.recipient_id) == pair_key(actor, target)): return {"ok": false, "error": "relationship_proposal_pending"}
	var id := "romance-" + key.sha256_text().substr(0, 24)
	var p := {"proposal_id": id, "interaction_id": id, "proposer_id": actor, "recipient_id": target, "status": "proposed", "version": 1, "note": a.note, "created_at": world.minute(), "expires_at": world.minute() + 1080}
	proposals[id] = p
	_event("RelationshipProposed", id, [actor, target], p)
	return {"ok": true, "proposal_id": id, "message": "交往意愿已表达，等待对方明确接受；目前还不是恋人。"}

func _respond(actor: String, a: Dictionary) -> Dictionary:
	var p: Dictionary = proposals.get(a.proposal_id, {})
	if p.is_empty() or (p.recipient_id != actor and (p.proposer_id != actor or a.accept)): return {"ok": false, "error": "not_relationship_recipient"}
	if p.status != "proposed" or int(p.version) != int(a.version): return {"ok": false, "error": "stale_relationship_proposal"}
	if p.proposer_id == actor:
		p.status = "cancelled"; p.version += 1
		_event("RelationshipProposalWithdrawn", p.proposal_id + ":withdrawn", [actor, p.recipient_id], p)
		return {"ok": true, "message": "已撤回交往邀请。"}
	var pair := _pair(p.proposer_id, actor)
	if a.accept:
		var reason := eligibility(p.proposer_id, actor)
		if not reason.is_empty(): return {"ok": false, "error": reason}
		pair.status = "dating"; pair.since = world.minute(); pair.version += 1
		p.status = "accepted"
	else:
		p.status = "rejected"
		pair.cooldown_until = world.minute() + 1080
	p.version += 1
	pairs[pair_key(p.proposer_id, actor)] = pair
	_event("RelationshipConfirmed" if a.accept else "RelationshipDeclined", p.proposal_id + ":" + str(p.version), [p.proposer_id, actor], p)
	return {"ok": true, "message": "双方已确认恋爱关系。" if a.accept else "已婉拒交往，尊重对方选择，不扣好感。"}

func _end(actor: String, a: Dictionary) -> Dictionary:
	if partner(actor) != a.target_actor_id: return {"ok": false, "error": "not_dating"}
	var p := _pair(actor, a.target_actor_id)
	p.status = "former_partners"; p.version += 1; p.cooldown_until = world.minute() + 1080
	_event("RelationshipEnded", pair_key(actor, a.target_actor_id) + ":" + str(p.version), [actor, a.target_actor_id], {"reason": a.reason})
	return {"ok": true, "message": "恋爱关系已结束，保留共同经历，尊重双方边界。"}

func _support(actor: String, a: Dictionary, key: String) -> Dictionary:
	var target := str(a.target_actor_id)
	if actor == target or not person(target): return {"ok": false, "error": "invalid_person"}
	var left := world.actor(actor) as Node3D
	var right := world.actor(target) as Node3D
	if left == null or right == null or left.global_position.distance_to(right.global_position) > 4: return {"ok": false, "error": "support_requires_nearby_person"}
	var rewarded := award(actor, target, "comfort", "support:" + key)
	if rewarded: world.society.relieve_needs(target, {"companionship": 10, "social": 10}, "received_comfort")
	_event("EmotionalSupportReceived", "support:" + key, [actor, target], {"speaker": actor, "recipient": target, "text": a.text, "affection_awarded": rewarded})
	return {"ok": true, "message": "%s对%s说：%s" % [world.actor_name(actor), world.actor_name(target), a.text]}

func _event(kind: String, source: String, actors: Array, payload: Dictionary, wake := true) -> void:
	var runtime: Node = world.session.agent_runtime
	for actor in actors:
		if actor == "player": continue
		runtime.loop_state.record(actor, {"event_id": "social:" + source.sha256_text().substr(0, 24), "kind": kind, "game_minute": world.minute(), "payload": payload.duplicate(true)})
		if wake: runtime.loop_state.feedback[actor] = {"ready_at": world.minute(), "pending": true, "count": 0}

func to_dict() -> Dictionary:
	return {"version": 1, "pairs": pairs.duplicate(true), "proposals": proposals.duplicate(true), "processed": processed.duplicate(), "results": results.duplicate(true), "daily": daily.duplicate(true), "event_cursor": event_cursor}

func restore(value: Dictionary) -> void:
	pairs = value.get("pairs", {}).duplicate(true); proposals = value.get("proposals", {}).duplicate(true)
	processed = value.get("processed", {}).duplicate(); results = value.get("results", {}).duplicate(true); daily = value.get("daily", {}).duplicate(true)
	event_cursor = int(value.get("event_cursor", world.session.agent_runtime.event_store.get_last_sequence()))

func validate(value: Variant, profile_overrides: Variant = null) -> bool:
	var overrides: Dictionary = world.character_overrides if profile_overrides == null else profile_overrides
	if not value is Dictionary or value.size() != 7 or value.get("version") != 1 or not world.integer(value.get("event_cursor")) or value.event_cursor < 0: return false
	for field in ["pairs", "proposals", "processed", "results", "daily"]:
		if not value.get(field) is Dictionary: return false
	var partners := {}
	for key in value.pairs:
		var p: Variant = value.pairs[key]
		if not p is Dictionary or not p.get("participants") is Array or p.participants.size() != 2: return false
		var a: Variant = p.participants[0]; var b: Variant = p.participants[1]
		if not a is String or not b is String or a == b or not person(a) or not person(b) or key != pair_key(a, b): return false
		if p.get("status") not in ["none", "dating", "former_partners"] or not p.get("affinity") is Dictionary or p.affinity.size() != 2 or not p.get("shared_counts") is Dictionary: return false
		for id in [a, b]:
			if not world.integer(p.affinity.get(id)) or p.affinity[id] < 0 or p.affinity[id] > 100: return false
			if p.status == "dating":
				var base_profile: Dictionary = profiles.defaults.merged(profiles.actors.get(id,{}),true)
				var social: Dictionary = overrides.get(id,{}).get("soul",{}).get("social_profile",base_profile)
				if partners.has(id) or int(social.age) < 18: return false
				partners[id] = true
		for field in ["version", "since", "cooldown_until"]:
			if not world.integer(p.get(field)) or p[field] < (-1 if field == "since" else 0): return false
		for kind in p.shared_counts:
			if not GAINS.has(kind) or not world.integer(p.shared_counts[kind]) or p.shared_counts[kind] < 0: return false
	for id in value.proposals:
		var p: Variant = value.proposals[id]
		if not p is Dictionary or p.get("proposal_id") != id or p.get("interaction_id") != id or not p.get("proposer_id") is String or not p.get("recipient_id") is String: return false
		if not person(p.proposer_id) or not person(p.recipient_id) or p.proposer_id == p.recipient_id or p.get("status") not in ["proposed", "accepted", "rejected", "expired", "cancelled"] or not p.get("note") is String: return false
		for field in ["version", "created_at", "expires_at"]:
			if not world.integer(p.get(field)) or p[field] < 0: return false
	for key in value.daily:
		var d: Variant = value.daily[key]
		if not d is Dictionary or not world.integer(d.get("total")) or d.total < 0 or d.total > DAILY_CAP or not d.get("kinds") is Dictionary: return false
		for kind in d.kinds:
			if not GAINS.has(kind) or not world.integer(d.kinds[kind]) or d.kinds[kind] < 0 or d.kinds[kind] > 2: return false
	for key in value.processed:
		if not key is String or value.processed[key] != true: return false
	for key in value.results:
		if not key is String or not value.results[key] is Dictionary: return false
		var record: Dictionary = value.results[key]
		if not record.get("intent") is Dictionary or not record.get("result") is Dictionary or not record.result.get("ok") is bool: return false
		if not record.intent.get("actor") is String or not person(record.intent.actor) or not record.intent.get("tool") is String or not record.intent.get("arguments") is Dictionary or not valid_command(record.intent.tool, record.intent.arguments): return false
	return true
