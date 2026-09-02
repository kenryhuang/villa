extends RefCounted

const AgreementScript = preload("res://scripts/ai_agent/agent_agreement_system.gd")
const InteractionScript = preload("res://scripts/ai_agent/agent_interaction_system.gd")
const EventStoreScript = preload("res://scripts/ai_agent/agent_world_event_store.gd")
const ProjectorScript = preload("res://scripts/ai_agent/agent_world_projector.gd")
const InboxScript = preload("res://scripts/ai_agent/agent_perception_inbox.gd")
const MarketScript = preload("res://scripts/systems/market_system.gd")
const EconomyScript = preload("res://scripts/systems/npc_economy_system.gd")
const GameDataScript = preload("res://scripts/core/game_data.gd")


func run(assertions: TestAssert) -> void:
	var market := MarketScript.new()
	var economy := EconomyScript.new()
	market.configure(GameDataScript.get_market_items())
	economy.configure(market, GameDataScript.get_npc_economy_profiles(), GameDataScript.get_population_demand_profiles())
	var inbox := InboxScript.new()
	var projector := ProjectorScript.new()
	projector.configure(["farmer_ahe", "lao_li", "xuezhe_lin"], [
		{"actor_id": "farmer_ahe", "actor_type": "npc", "display_name": "阿禾", "public_role": "farmer", "region_id": "farm"},
		{"actor_id": "lao_li", "actor_type": "npc", "display_name": "老李", "public_role": "merchant", "region_id": "farm"},
		{"actor_id": "xuezhe_lin", "actor_type": "npc", "display_name": "学者林", "public_role": "explorer", "region_id": "hills"},
		{"actor_id": "player", "actor_type": "player", "display_name": "玩家", "public_role": "player", "region_id": "farm"},
	], inbox)
	var store := EventStoreScript.new()
	var interactions := InteractionScript.new()
	interactions.configure(economy, store, projector, Callable(), market)
	var wakes: Array[String] = []
	var agreements := AgreementScript.new()
	assertions.truthy(agreements.configure(economy, interactions, store, projector, func(agent_id: String, _priority: int, _minute: int): wakes.append(agent_id)), "agreement system configures from deterministic templates")

	var terms := _terms(["lao_li"], 120)
	var proposal := agreements.execute(_command("propose_cooperation", "farmer_ahe", "agreement-propose", terms), 200)
	assertions.truthy(proposal.ok, "known cooperation template can be proposed")
	var agreement_id := str(proposal.agreement_id)
	assertions.equal(agreements.get_agreement(agreement_id, "xuezhe_lin"), {}, "agreement terms are visible only to participants")
	assertions.equal(agreements.get_agreement(agreement_id, "farmer_ahe").terms_version, 1, "proposal starts at terms version one")
	var revised := terms.duplicate(true)
	revised.deadline_minutes = 180
	revised.erase("participants")
	revised.erase("objective_id")
	var counter := agreements.execute(_command("counter_cooperation", "lao_li", "agreement-counter", {"agreement_id": agreement_id, "revised_terms": revised, "note": "多留一点时间"}), 201)
	assertions.truthy(counter.ok, "participant can create a versioned counterproposal")
	assertions.equal(agreements.get_agreement(agreement_id, "farmer_ahe").terms_version, 2, "counter increments terms version")
	assertions.equal(agreements.get_agreement(agreement_id, "farmer_ahe").accepted_by, ["lao_li"], "counter resets acceptance to countering participant")

	var farmer = economy.get_npc_state("farmer_ahe")
	var merchant = economy.get_npc_state("lao_li")
	var farmer_gold_before := int(farmer.gold)
	var merchant_gold_before := int(merchant.gold)
	var farmer_seed_before := int(farmer.inventory.carrot_seed)
	var merchant_salt_before := int(merchant.inventory.salt)
	var activated := agreements.execute(_command("accept_cooperation", "farmer_ahe", "agreement-accept", {"agreement_id": agreement_id, "terms_version": 2}), 202)
	assertions.truthy(activated.ok, "last participant acceptance activates agreement")
	assertions.equal(agreements.get_agreement(agreement_id, "lao_li").status, "active", "all-party acceptance activates current version")
	assertions.equal(interactions.available_item("farmer_ahe", "carrot_seed"), farmer_seed_before - 1, "activation locks farmer resource commitment")
	assertions.equal(interactions.available_item("lao_li", "salt"), merchant_salt_before - 1, "activation locks merchant resource commitment")

	assertions.equal(agreements.record_action_outcome({"status": "completed", "agent_id": "farmer_ahe", "tool_name": "harvest", "action_id": "harvest-1"}, 210).size(), 1, "verified harvest advances configured milestone")
	var completion_events := agreements.record_action_outcome({"status": "completed", "agent_id": "lao_li", "tool_name": "sell", "action_id": "sell-1"}, 211)
	assertions.truthy(completion_events.size() >= 2, "final verified action completes and settles agreement atomically")
	assertions.equal(agreements.get_agreement(agreement_id, "farmer_ahe").status, "completed", "deterministic milestones complete agreement")
	assertions.equal(int(farmer.inventory.carrot_seed), farmer_seed_before - 1, "completion consumes committed farmer item")
	assertions.equal(int(merchant.inventory.salt), merchant_salt_before - 1, "completion consumes committed merchant item")
	assertions.equal(int(farmer.gold), farmer_gold_before + 51, "odd reward remainder deterministically goes to proposer")
	assertions.equal(int(merchant.gold), merchant_gold_before + 50, "integer reward split gives other equal-weight participant floor share")
	assertions.truthy(agreements.get_relationship("farmer_ahe", "lao_li") > 0, "successful cooperation improves deterministic relationship")

	var deadline := agreements.execute(_command("propose_cooperation", "farmer_ahe", "agreement-deadline", _terms(["lao_li"], 60)), 300)
	agreements.execute(_command("accept_cooperation", "lao_li", "agreement-deadline-accept", {"agreement_id": str(deadline.agreement_id), "terms_version": 1}), 301)
	var available_while_locked := interactions.available_item("farmer_ahe", "carrot_seed")
	assertions.equal(agreements.expire_due(359).size(), 0, "active agreement remains before deadline")
	assertions.equal(agreements.expire_due(360).size(), 1, "deadline deterministically fails incomplete agreement")
	assertions.equal(agreements.get_agreement(str(deadline.agreement_id), "farmer_ahe").status, "failed", "deadline produces failed terminal state")
	assertions.equal(interactions.available_item("farmer_ahe", "carrot_seed"), available_while_locked + 1, "deadline failure follows full refund/unlock policy")

	var cancellable := agreements.execute(_command("propose_cooperation", "farmer_ahe", "agreement-cancel", _terms(["lao_li"], 60)), 400)
	agreements.execute(_command("accept_cooperation", "lao_li", "agreement-cancel-accept", {"agreement_id": str(cancellable.agreement_id), "terms_version": 1}), 401)
	assertions.truthy(agreements.execute(_command("cancel_cooperation", "farmer_ahe", "agreement-cancel-do", {"agreement_id": str(cancellable.agreement_id), "reason_code": "plans_changed"}), 402).ok, "proposer can cancel under template policy")
	assertions.equal(agreements.get_agreement(str(cancellable.agreement_id), "lao_li").status, "cancelled", "cancellation is terminal")

	var player_terms := _terms(["player"], 120)
	(player_terms.commitments as Array)[1] = {"participant_id": "player", "items": {}, "gold": 0}
	var player_agreement := agreements.execute(_command("propose_cooperation", "farmer_ahe", "agreement-player", player_terms), 500)
	assertions.equal(agreements.get_agreement(str(player_agreement.agreement_id), "farmer_ahe").status, "proposed", "Player participation never auto-accepts")
	assertions.equal(agreements.execute(_command("accept_cooperation", "farmer_ahe", "agreement-player-fake", {"agreement_id": str(player_agreement.agreement_id), "terms_version": 1}), 501).error, "already_accepted", "NPC text path cannot accept for Player")
	assertions.truthy(agreements.execute(_command("accept_cooperation", "player", "agreement-player-manual", {"agreement_id": str(player_agreement.agreement_id), "terms_version": 1, "player_confirmed": true}), 502).ok, "explicit Player command manually accepts current terms")

	assertions.truthy(wakes.has("lao_li"), "proposal and lifecycle changes urgently wake participants")
	market.free()
	economy.free()


func _terms(other_participants: Array[String], deadline_minutes: int) -> Dictionary:
	var participants: Array[String] = other_participants.duplicate()
	var commitments: Array[Dictionary] = [{"participant_id": "farmer_ahe", "items": {"carrot_seed": 1}, "gold": 0}]
	var reward_split := {"farmer_ahe": 1}
	for participant in other_participants:
		commitments.append({"participant_id": participant, "items": {"salt": 1} if participant == "lao_li" else {}, "gold": 0})
		reward_split[participant] = 1
	return {"objective_id": "joint_crop_supply", "participants": participants, "commitments": commitments, "reward_split": reward_split, "deadline_minutes": deadline_minutes, "note": "按模板合作"}


func _command(tool_name: String, agent_id: String, key: String, arguments: Dictionary) -> Dictionary:
	return {"tool_name": tool_name, "agent_id": agent_id, "idempotency_key": key, "action_id": key, "decision_id": "decision-" + key, "arguments": arguments}
