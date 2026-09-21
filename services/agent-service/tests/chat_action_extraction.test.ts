import test from "node:test";
import assert from "node:assert/strict";
import {extractionTurns,inspectMovementHandoffs,movementExtractionInstructions} from "../src/chat_action_extraction.ts";
import {chatMessages,importantChatActors} from "../src/chat_context.ts";
import {parseDecisionRequest} from "../src/protocol.ts";
import {AgentRegistry} from "../src/agents.ts";
import {MemoryRepository} from "../src/memory.ts";
import {prepareActionRequest} from "../src/context_channels.ts";

const wire={protocol_version:3,request_id:"yes",session_id:"test",session_epoch:1,agent_id:"farmer_ahe",trigger:"dialogue",dialogue_input:"好",game_minute:1,world_revision:1,active_role:"farmer",goals:[],allowed_command_tools:["move","wait"],resources:{gold:10,inventory:{}},experience_events:[],goal_refs:[]};
function request(){const r=parseDecisionRequest(wire);assert.ok(r.ok);return r.value;}
const places=[{id:"lake",name:"南湖",aliases:["湖边"]},{id:"market",name:"市集"}];
const proposal={event_id:"old-proposal",kind:"ChatMessage",game_minute:0,payload:{speaker:"farmer_ahe",text:"我们去南湖散步吧。"}};
const agreed={place_id:"lake",activity:"walk",status:"agreed",target_actor_id:"player",player_evidence:"好",actor_evidence:"我们去南湖散步吧"};

test("short player acceptance requires a concrete confirmation in this NPC reply",()=>{
  const r=request(),turns=extractionTurns(r,[proposal],"那我去拿件外套。");
  const old=inspectMovementHandoffs([agreed],places,["player",r.agent_id],turns,r.agent_id);
  assert.deepEqual(old.accepted,[]);assert.equal(old.rejected[0].reason,"actor_proposal_or_agreement_evidence_missing");
  assert.equal(turns.length,2);assert.doesNotMatch(JSON.stringify(turns),/南湖/);
  const result=inspectMovementHandoffs([agreed],places,["player",r.agent_id],extractionTurns(r,[proposal],"好，我们去南湖散步吧。"),r.agent_id);
  assert.deepEqual(result.rejected,[]);assert.equal(result.accepted[0].place_id,"lake");assert.equal(result.accepted[0].activity,"walk");
  assert.doesNotMatch(JSON.stringify(result.accepted),/player_evidence|actor_evidence|外套|散步吧/);
});

test("player proposal supplies player agreement without an extra confirmation round",()=>{
  const r=request();r.dialogue_input="我们去市集买东西吧。";
  const turns=extractionTurns(r,[],"行。");
  const result=inspectMovementHandoffs([{...agreed,place_id:"市集",activity:"buy",player_evidence:"我们去市集买东西吧",actor_evidence:"行"}],places,["player"],turns,r.agent_id);
  assert.equal(result.accepted[0]?.activity,"buy");assert.equal(result.accepted[0]?.place_id,"market");assert.equal(result.accepted[0]?.quantity,0);
});

test("agreement evidence must come from this player turn and this NPC, not another room participant",()=>{
  const r=request();r.chat_room={id:"room",turn_id:"turn",participants:[r.agent_id,"lao_li"]};r.dialogue_input="不去了";
  const history=[proposal,{event_id:"old-yes",kind:"ChatMessage",game_minute:0,payload:{speaker:"player",text:"好"}},{event_id:"other",kind:"ChatMessage",game_minute:0,payload:{speaker:"lao_li",text:"我同意"}}];
  const turns=extractionTurns(r,history,"那就算了。");
  assert.equal(inspectMovementHandoffs([agreed],places,["player"],turns,r.agent_id).rejected[0].reason,"player_agreement_evidence_missing");
  r.dialogue_input="好";
  assert.equal(inspectMovementHandoffs([{...agreed,actor_evidence:"我同意"}],places,["player"],extractionTurns(r,history,"嗯。"),r.agent_id).rejected[0].reason,"actor_proposal_or_agreement_evidence_missing");
});

test("extraction contains only current player and current NPC, excluding group and historical replies",()=>{
  const r=request();r.chat_room={id:"room",turn_id:"turn",participants:[r.agent_id,"lao_li"]};
  const turns=extractionTurns(r,[proposal,{event_id:"chat-user:turn",kind:"ChatMessage",game_minute:1,payload:{speaker:"player",text:"好"}},{event_id:"other",kind:"ChatMessage",game_minute:1,payload:{speaker:"lao_li",text:"我留在这里"}}],"出发吧");
  assert.deepEqual(turns,[{speaker:"player",text:"好",current:true},{speaker:r.agent_id,text:"出发吧",current:true}]);
});

test("important character names replace full resident roster and never enter action requests",()=>{
  const parsed=parseDecisionRequest({...wire,chat_focus_actors:[{actor_id:"farmer_ahe",display_name:"阿禾"},{actor_id:"lao_li",display_name:"老李自定义"}]});assert.ok(parsed.ok);const r=parsed.value;
  const actors=[{id:"farmer_ahe",name:"阿禾"},{id:"lao_li",name:"老李",role:"merchant"},{id:"background",name:"BACKGROUND_SENTINEL",soul:{traits:["SOUL_SENTINEL"],values:[],speech_style:"",risk_tolerance:0}}];
  const selected=importantChatActors(r,actors);
  assert.deepEqual(selected,[{id:"farmer_ahe",name:"阿禾"},{id:"lao_li",name:"老李自定义"}]);
  const context=AgentRegistry.loadDefault().buildContext(r.agent_id,r,[]);
  const chat=chatMessages(r,context,[],actors);
  const header=JSON.parse(String(chat[0].content));assert.deepEqual(header.important_characters,[selected[1]]);
  assert.doesNotMatch(JSON.stringify([chat,movementExtractionInstructions(places,selected)]),/BACKGROUND_SENTINEL|SOUL_SENTINEL/);
  assert.match(header.action_agreements,/好\/行\/走吧/);
  const memory=new MemoryRepository(":memory:");try{assert.equal(prepareActionRequest(memory,{...r,trigger:"event"}).chat_focus_actors,undefined);}finally{memory.close();}
  assert.equal(parseDecisionRequest({...wire,chat_focus_actors:[{actor_id:"a",display_name:"A"},{actor_id:"a",display_name:"Again"}]}).ok,false);
});

test("ambiguous destinations and unsupported behavior are diagnosed rather than guessed",()=>{
  const r=request(),turns=extractionTurns(r,[proposal],"出发吧");
  assert.equal(inspectMovementHandoffs([{...agreed,place_id:"温室"}],[{id:"one",name:"温室"},{id:"two",name:"温室"}],["player"],turns,r.agent_id).rejected[0].reason,"ambiguous_place");
  assert.equal(inspectMovementHandoffs([{...agreed,activity:"invented"}],places,["player"],turns,r.agent_id).rejected[0].reason,"unknown_activity");
});
