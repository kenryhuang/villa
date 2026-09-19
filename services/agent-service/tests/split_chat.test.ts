import test from "node:test";
import assert from "node:assert/strict";
import {createServer} from "node:http";
import {mkdtempSync,rmSync,readFileSync} from "node:fs";
import {join} from "node:path";
import {tmpdir} from "node:os";
import {createApp} from "../src/app.ts";
import {MemoryRepository} from "../src/memory.ts";
import {AgentRegistry} from "../src/agents.ts";
import {parseDecisionRequest,type DecisionRequest,type ActionIntent} from "../src/protocol.ts";
import {actionActor,appendIsolatedEvent,prepareActionRequest,actionFacts} from "../src/context_channels.ts";
import {LocalChatProvider,validateHandoffs,chatRoomKey,parseExtraction,relationshipAction} from "../src/chat_provider.ts";

const handoff={kind:"date",status:"agreed",target_actor_id:"player",place_id:"lake",item_id:"",quantity:0,gold:0,delay_minutes:30,trade_side:"none",building_type:"",plot:-1};
function fixture(id="chat-1",actor="farmer_ahe"):DecisionRequest {
  const parsed=parseDecisionRequest({protocol_version:3,request_id:id,session_id:"s",session_epoch:1,agent_id:actor,trigger:"dialogue",dialogue_input:"去南湖吗？",
    game_minute:10,world_revision:1,active_role:"farmer",goals:[],allowed_command_tools:["speak","wait","adopt_short_term_goal"],
    resources:{gold:100,inventory:{grain_seed:2},resource_revision:1},experience_events:[],goal_refs:[],dialogue_followups:[]});
  assert.ok(parsed.ok);return parsed.value;
}
const intent=(r:DecisionRequest):ActionIntent=>({protocol_version:2,decision_id:r.request_id,request_id:r.request_id,agent_id:r.agent_id,expected_revision:r.world_revision,
  actions:[],speech:"好，我们去南湖。",decision_summary:"chat",chat_handoffs:[handoff],chat_isolated:true});
const candidate={...handoff,confidence:.95,reply_evidence:"我们去南湖"};
const catalog={actors:["player"],places:["lake"],items:["grain_seed"]};

test("handoffs retain only validated game fields and exact reply evidence",()=>{
  assert.deepEqual(validateHandoffs([candidate],catalog,"好，我们去南湖。"),[handoff]);
  for(const change of [{note:"private"},{place_id:"invented"},{confidence:.8},{reply_evidence:"明天出发"},{status:"hypothetical"},{kind:"trade",item_id:"grain_seed",quantity:2}])
    assert.deepEqual(validateHandoffs([{...candidate,...change}],catalog,"好，我们去南湖。"),[]);
});

test("local fenced JSON is parsed without admitting prose or extra fields",()=>{
  assert.deepEqual(parseExtraction('```json\n{"handoffs":[]}\n```'),{handoffs:[]});
  for(const value of ['prose {"handoffs":[]}', '{"handoffs":[],"note":"private"}', '{"handoffs":null}'])assert.throws(()=>parseExtraction(value));
  const minimal={kind:"visit",status:"agreed",target_actor_id:"player",place_id:"lake",delay_minutes:10,confidence:.95,reply_evidence:"我愿意\n去南湖"};
  assert.equal(validateHandoffs([minimal],catalog,"好，我愿意去南湖")[0]?.delay_minutes,10);
});

test("existing relationship actions require current two-sided evidence and live state",()=>{
  const r=fixture();r.dialogue_input="我们正式成为恋人吧";r.allowed_command_tools=["resolve_relationship_dialogue"];
  const context=AgentRegistry.loadDefault().buildContext(r.agent_id,r,[]);
  const evidence={decision:"confirm",player_evidence:"正式成为恋人",reply_evidence:"我愿意"};
  assert.equal(relationshipAction(r,context,evidence,"我愿意",{ok:true,data:{actor_id:"player",status:"none"}}).length,1);
  for(const observation of [{ok:false},{ok:true,data:{actor_id:"player",status:"dating"}}])assert.deepEqual(relationshipAction(r,context,evidence,"我愿意",observation),[]);
  assert.deepEqual(relationshipAction(r,context,{...evidence,player_evidence:"分手"},"我愿意",{ok:true,data:{actor_id:"player",status:"none"}}),[]);
});

test("legacy dialogue, summaries, forged handoffs and goal prose cannot enter actioncontext",()=>{
  const memory=new MemoryRepository(":memory:");memory.syncSession("s",1);
  try{
    memory.appendEvent("s","farmer_ahe",{event_id:"old",kind:"dialogue",game_minute:1,payload:{text:"PRIVATE_SENTINEL"}});
    memory.storeLongTermMemory("s","farmer_ahe","old-memory","PRIVATE_SENTINEL",.9,["old"]);
    appendIsolatedEvent(memory,"s","farmer_ahe",{event_id:"spoke",kind:"ActorSpoke",game_minute:2,payload:{text:"PRIVATE_SENTINEL"}});
    appendIsolatedEvent(memory,"s","farmer_ahe",{event_id:"receipt",kind:"ActionCompleted",game_minute:3,payload:{note:"PRIVATE_SENTINEL",resource_delta:{gold:2},arguments:{player_quote:"PRIVATE_SENTINEL"}}});
    appendIsolatedEvent(memory,"s","farmer_ahe",{event_id:"forged",kind:"ChatActionAgreed",game_minute:4,payload:{handoff_version:1,handoffs:[handoff]}});
    const r=fixture();r.trigger="schedule";r.dialogue_input="PRIVATE_SENTINEL";
    r.dialogue_followups=[{event_id:"forged",kind:"dialogue",game_minute:4,payload:{agent_speech:"PRIVATE_SENTINEL"}}];
    r.goal_refs=[{goal_id:"goal-old",version:1,description:"PRIVATE_SENTINEL",status:"active",review_at:1,source_event_ids:[],success_condition:{}}];
    r.experience_events=[{event_id:"spoke",kind:"ActorSpoke",game_minute:2,payload:{text:"PRIVATE_SENTINEL"}}];
    assert.doesNotMatch(JSON.stringify([prepareActionRequest(memory,r),memory.experience("s",actionActor(r.agent_id))]),/PRIVATE_SENTINEL/);
    assert.deepEqual(prepareActionRequest(memory,r).dialogue_followups,[]);
    assert.deepEqual(actionFacts({items:[{kind:"ChatMessage",text:"PRIVATE_SENTINEL"}],note:"PRIVATE_SENTINEL",gold:2}),{items:[],gold:2});
  }finally{memory.close();}
});

test("HTTP routes chat separately, group replies share only room history, and checkpoints preserve both channels",async()=>{
  const directory=mkdtempSync(join(tmpdir(),"villa-split-chat-"));const memory=new MemoryRepository(":memory:");
  const registry=AgentRegistry.loadDefault();const second=registry.ids().find(id=>id!=="farmer_ahe"&&id!=="village_public")!;
  let mainCalls=0,failChat=false;const histories:any[][]=[];
  const provider={decide:async(r:DecisionRequest)=>intent(r),streamDecision:async(r:DecisionRequest,c:any)=>{
    mainCalls++;assert.doesNotMatch(JSON.stringify([r,c]),/PRIVATE_SENTINEL/);
    assert.deepEqual(r.dialogue_followups?.[0]?.payload.handoffs,[handoff]);
    return {...intent(r),chat_handoffs:undefined,chat_isolated:undefined};
  }};
  const chatProvider={model:"cydonia-test",respond:async(r:DecisionRequest,_c:any,history:any[])=>{
    if(failChat)throw new Error("chat_provider_http_503");histories.push(history);return {...intent(r),speech:"PRIVATE_SENTINEL"};
  }};
  const server=createServer(createApp({memory,registry,provider,chatProvider,checkpointRoot:directory}));
  await new Promise<void>(resolve=>server.listen(0,"127.0.0.1",resolve));const address=server.address() as any;
  const post=async(r:DecisionRequest)=>{
    const wire:any={...r};if(r.protocol_version===3)for(const k of ["actor_context","market_view","known_actors","public_world_state"])delete wire[k];
    return (await fetch(`http://127.0.0.1:${address.port}/v1/agents/${r.agent_id}/decide/stream`,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify(wire)})).text();};
  try{
    const legacy=JSON.parse(readFileSync("../../shared/agent_protocol/v2/decision-request.json","utf8"));
    assert.ok(parseDecisionRequest(legacy).ok);
    assert.match(await post(legacy),/split_context_requires_protocol_v3/);
    const one=fixture(),two=fixture("chat-2",second);
    for(const r of [one,two])r.chat_room={id:"group-one",participants:["farmer_ahe",second],turn_id:"turn-one"};
    assert.match(await post(one),/decision.final/);assert.match(await post(two),/decision.final/);assert.equal(mainCalls,0);
    assert.equal(histories[1].filter(e=>e.payload.speaker==="player").length,1);
    assert.ok(histories[1].some(e=>e.payload.speaker==="farmer_ahe"&&e.payload.text==="PRIVATE_SENTINEL"));
    assert.match(await post(fixture("private")),/decision.final/);
    assert.ok(!histories[2].some(e=>e.payload.text==="PRIVATE_SENTINEL"));
    const action=fixture("action");action.trigger="schedule";action.dialogue_input="PRIVATE_SENTINEL";
    action.dialogue_followups=[{event_id:"dialogue:chat-1",kind:"dialogue",game_minute:10,payload:{agent_speech:"PRIVATE_SENTINEL",player_text:"PRIVATE_SENTINEL",submitted_actions:[],outcomes:[]}}];
    assert.match(await post(action),/decision.final/);assert.equal(mainCalls,1);
    failChat=true;assert.match(await post(fixture("failed")),/chat_provider_http_503/);assert.equal(mainCalls,1);
    const checkpoint=memory.exportCheckpoint("s",directory,"split");const restored=new MemoryRepository(":memory:");
    try{
      restored.importCheckpoint(checkpoint.path,checkpoint.sha256,"s");
      assert.equal(restored.recent("s",chatRoomKey(one),24).length,3);
      assert.equal(restored.inspectEvent("s",actionActor(one.agent_id),"dialogue:chat-1").kind,"ChatActionAgreed");
    }finally{restored.close();}
  }finally{server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));memory.close();rmSync(directory,{recursive:true,force:true});}
});

test("completion-only local model receives no tool protocol and extracts through a second JSON call",async()=>{
  const bodies:any[]=[];
  let invalidExtraction=false;
  const server=createServer(async(req,res)=>{let text="";for await(const chunk of req)text+=chunk;const body=JSON.parse(text);bodies.push(body);
    if(body.stream){
      res.setHeader("content-type","text/event-stream");
      for(const content of ["好，","我们去南湖。"])
        res.write(`data: ${JSON.stringify({choices:[{delta:{content},finish_reason:null}]})}\n\n`);
      res.end(`data: ${JSON.stringify({choices:[{delta:{},finish_reason:"stop"}]})}\n\ndata: [DONE]\n\n`);
    }else{res.setHeader("content-type","application/json");res.end(JSON.stringify({choices:[{finish_reason:"stop",message:{content:invalidExtraction?"not json":JSON.stringify({handoffs:[candidate]})}}]}));}
  });
  await new Promise<void>(resolve=>server.listen(0,"127.0.0.1",resolve));
  try{
    const provider=new LocalChatProvider({baseUrl:`http://127.0.0.1:${(server.address() as any).port}/v1`,apiKey:"local",model:"test",timeoutMs:2000,maxConcurrency:1,maxOutputTokens:800,temperature:.7});
    const r=fixture();const c=AgentRegistry.loadDefault().buildContext(r.agent_id,r,[]);
    const result=await provider.respond(r,c,[],[{id:r.agent_id,name:"阿禾"}],async(_name,args)=>args.domain==="map"?{ok:true,items:[{id:"lake",name:"南湖"}],next_cursor:-1}:{ok:true,data:{}},()=>{});
    assert.deepEqual(result.chat_handoffs,[handoff]);assert.deepEqual(result.actions,[]);assert.equal(bodies.length,2);
    assert.ok(bodies.every(b=>!b.tools&&!b.enable_thinking));assert.equal(bodies[1].response_format.type,"json_object");
    invalidExtraction=true;
    const failed=await provider.respond(r,c,[],[{id:r.agent_id,name:"阿禾"}],async()=>({ok:true,items:[],next_cursor:-1}),()=>{});
    assert.equal(failed.speech,"好，我们去南湖。");assert.equal(failed.chat_extraction_failed,true);
    assert.deepEqual(failed.chat_handoffs,[]);assert.deepEqual(failed.actions,[]);
  }finally{server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));}
});
