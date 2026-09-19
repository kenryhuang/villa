import test from "node:test";
import assert from "node:assert/strict";
import {AgentRegistry} from "../src/agents.ts";
import {parseDecisionRequest} from "../src/protocol.ts";
import {AgentStreamAssembler} from "../src/provider_stream.ts";
import {runAgentLoop,compactWorkingMessages} from "../src/agent_loop.ts";

const exchange=(speech="好，等聊完我就去溪边。")=>({event_id:"dialogue:talk-1",kind:"dialogue",game_minute:100,
  payload:{player_text:"聊完去溪边看看吧。",agent_speech:speech,submitted_actions:[],outcomes:[]}});
function request(trigger="event",followups=[exchange()]) {
  const parsed=parseDecisionRequest({protocol_version:3,request_id:"next-loop",session_id:"save",session_epoch:1,
    agent_id:"farmer_ahe",trigger,game_minute:101,world_revision:8,active_role:"farmer",goals:[],
    allowed_command_tools:["move","speak","wait","adopt_short_term_goal"],resources:{gold:70,inventory:{},resource_revision:9},
    experience_events:[],goal_refs:[],dialogue_followups:followups,...(trigger==="dialogue"?{dialogue_input:"去溪边吗？"}:{})});
  assert.ok(parsed.ok);return parsed.value;
}
function output(name?:string,args={},speech="") {
  const value=new AgentStreamAssembler();
  value.accept({id:"reply",choices:[{index:0,delta:{content:speech,...(name?{tool_calls:[{index:0,id:"call",type:"function",function:{name,arguments:JSON.stringify(args)}}]}:{})},finish_reason:name?"tool_calls":"stop"}]});
  return value;
}
test("accepted dialogue is protected context; background discovers fresh destination and emits a real move",async()=>{
  const r=request(),ctx=AgentRegistry.loadDefault().buildContext(r.agent_id,r,[]);let rounds=0,reads=0;
  const result=await runAgentLoop(r,ctx,{experience:{recent_events:[]},memories:[],read:async(name,args)=>{
    reads++;assert.equal(name,"query_world");assert.equal(args.domain,"map");
    return {ok:true,observation_id:"current-map",items:[{id:"creek",x:12,z:7}]};
  }},async(messages,tools)=>{
    const header=JSON.parse(String(messages[1].content));
    assert.deepEqual(header.turn.dialogue_followups,[exchange()]);assert.equal(header.resources.gold,70);
    assert.match(String(messages[0].content),/返回具体动作工具调用/);
    const compacted=compactWorkingMessages(messages,1000);
    assert.deepEqual(compacted.slice(0,2),messages.slice(0,2),"compaction cannot drop the unreviewed agreement");
    rounds++;
    if(rounds===1){
      assert.ok(!tools.some(t=>(t.function as any).name==="move"));
      return output("discover_tools",{domains:["map"],actions:["move"]});
    }
    if(rounds===2)return output("query_world",{domain:"map",section:"overview"});
    assert.match(String(messages.at(-1)?.content),/current-map/);
    return output("move",{x:12,z:7});
  },()=>{});
  assert.equal(reads,1);assert.equal(rounds,3);assert.deepEqual(result.actions.map(a=>[a.tool_name,a.arguments]),[["move",{x:12,z:7}]]);
});
test("dialogue can persist an agreed plan immediately without discovering movement tools",async()=>{
  const r=request("dialogue",[]),ctx=AgentRegistry.loadDefault().buildContext(r.agent_id,r,[]);
  const result=await runAgentLoop(r,ctx,{experience:{},memories:[],read:async()=>{throw Error("no prefetch");}},async(messages,tools)=>{
    assert.ok(tools.some(t=>(t.function as any).name==="adopt_short_term_goal"));
    const header=JSON.parse(String(messages[1].content));assert.equal(header.turn.dialogue_event_id,"dialogue:next-loop");
    return output("adopt_short_term_goal",{description:"对话结束后去溪边，先查地图确认目的地。",source_event_ids:[header.turn.dialogue_event_id],ttl_minutes:180,review_in_minutes:1},"好，聊完我就去溪边。");
  },()=>{});
  assert.equal(result.actions[0].tool_name,"adopt_short_term_goal");assert.equal(result.actions.length,1);
});
test("refusals and greetings are reviewable conversation, never automatically converted to commands",async()=>{
  for(const speech of ["不去，我今天有其他安排。","你好，今天心情不错。"]){
    const r=request("event",[exchange(speech)]),ctx=AgentRegistry.loadDefault().buildContext(r.agent_id,r,[]);
    const result=await runAgentLoop(r,ctx,{experience:{},memories:[],read:async()=>{throw Error("unexpected read");}},async(messages)=>{
      assert.match(String(messages[0].content),/玩家单方面请求无需动作/);return output();
    },()=>{});
    assert.deepEqual(result.actions,[]);
  }
});
test("dialogue movement is corrected into a deferred goal instead of dispatching a stale trip",async()=>{
  const r=request("dialogue",[]),ctx=AgentRegistry.loadDefault().buildContext(r.agent_id,r,[]);let rounds=0;
  const result=await runAgentLoop(r,ctx,{experience:{},memories:[],read:async()=>({})},async(messages,tools)=>{
    assert.ok(!tools.some(t=>(t.function as any).name==="move"));
    if(rounds++===0)return output("move",{x:12,z:7},"我这就过去。");
    assert.match(String(messages.at(-1)?.content),/dialogue_action_not_allowed/);
    return output("adopt_short_term_goal",{description:"聊完去溪边。",source_event_ids:["dialogue:next-loop"],ttl_minutes:180,review_in_minutes:1},"好，聊完再去。");
  },()=>{});
  assert.equal(rounds,2);assert.deepEqual(result.actions.map(a=>a.tool_name),["adopt_short_term_goal"]);
});
test("handoff protocol is bounded and validates provenance and dialogue payloads",()=>{
  const r=request();const wire={...r};
  for(const key of ["actor_context","market_view","known_actors","public_world_state"])delete (wire as any)[key];
  assert.ok(parseDecisionRequest({...wire,dialogue_followups:undefined}).ok,"old v3 clients remain compatible");
  assert.equal(parseDecisionRequest({...wire,dialogue_followups:Array(6).fill(exchange())}).ok,false);
  assert.equal(parseDecisionRequest({...wire,dialogue_followups:[{...exchange(),game_minute:-1}]}).ok,false);
  assert.equal(parseDecisionRequest({...wire,dialogue_followups:[{...exchange(),payload:{...exchange().payload,player_text:"x".repeat(1001)}}]}).ok,false);
});
