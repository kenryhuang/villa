import test from "node:test";
import assert from "node:assert/strict";
import {AgentRegistry} from "../src/agents.ts";
import {AgentStreamAssembler} from "../src/provider_stream.ts";
import {runAgentLoop} from "../src/agent_loop.ts";
import type {DecisionRequest} from "../src/protocol.ts";
import {MemoryRepository} from "../src/memory.ts";

function fixture(){
  const request={protocol_version:3,request_id:"greeting",session_id:"test",session_epoch:1,agent_id:"farmer_ahe",trigger:"dialogue",
    dialogue_input:"hello",game_minute:50,world_revision:1,active_role:"farmer",goals:["earn_stable_profit"],
    allowed_command_tools:["harvest","plant","wait","speak","adopt_short_term_goal"],allowed_read_tools:[],actor_context:{},public_world_state:{},global_public_events:[],known_actors:[],own_event_delta:[],market_summary:{},market_view:{},interaction_view:{},agreement_view:{},resources:{gold:50},experience_events:[]} as unknown as DecisionRequest;
  return {request,ctx:AgentRegistry.loadDefault().buildContext(request.agent_id,request,[])};
}
function response(name?:string,args:Record<string,unknown>={},text=""){
  const a=new AgentStreamAssembler();a.accept({choices:[{index:0,delta:{content:text,...(name?{tool_calls:[{index:0,id:"call",type:"function",function:{name,arguments:JSON.stringify(args)}}]}:{})},finish_reason:name?"tool_calls":"stop"}]});return a;
}
test("hello with mature crops cannot submit autonomous harvesting during dialogue",async()=>{
  const {request,ctx}=fixture();let round=0;const traces:any[]=[];
  const intent=await runAgentLoop(request,ctx,{experience:{recent_events:[{kind:"CropMatured",payload:{plot:1}}]},memories:[],read:async()=>({})},async(messages,tools)=>{
    assert.ok(!tools.some(t=>["harvest","plant"].includes((t.function as any).name)));
    assert.ok(JSON.parse(String(messages[0].content)).dialogue_rules.includes("当前玩家消息"));
    if(round++===0)return response("harvest",{plot:1}); // Actual latest trace: hello -> harvest.
    assert.ok(String(messages.at(-1)!.content).includes("dialogue_action_not_allowed"));
    return response(undefined,{},"你好！今天过得怎么样？");
  },e=>traces.push(e));
  assert.equal(intent.speech,"你好！今天过得怎么样？");assert.deepEqual(intent.actions,[]);assert.equal(round,2);
});
test("dialogue discovery omits farming commands and action-only replies get one correction",async()=>{
  const {request,ctx}=fixture();let round=0;
  const goal={description:"了解玩家需要什么",source_event_ids:[],ttl_minutes:60,review_in_minutes:30};
  const intent=await runAgentLoop(request,ctx,{experience:{},memories:[],read:async()=>({})},async(messages)=>{
    if(round++===0)return response("discover_tools",{domains:["farm","goals"]});
    if(round===2){const catalog=JSON.parse(String(messages.at(-1)!.content));assert.ok(!catalog.available_actions.includes("harvest"));return response("adopt_short_term_goal",goal);}
    assert.ok(String(messages.at(-1)!.content).includes("dialogue_reply_required"));
    return response("adopt_short_term_goal",goal,"我会留意你的需求。");
  },()=>{});
  assert.equal(round,3);assert.equal(intent.actions.length,1);assert.equal(intent.speech,"我会留意你的需求。");
});
test("recent event excerpts keep the exact failure reason and trade diagnostics",()=>{
  const m=new MemoryRepository(":memory:");
  try{
    m.appendEvent("save","afu_shui",{event_id:"failed-supply",kind:"ActionFailed",game_minute:1,payload:{action_id:"x".repeat(180),
      tool_name:"prepare_supplies",status:"rejected",failure_code:"market_stock_unavailable",failure_details:{gold:58,buy_total:206,market_stock:0}}});
    const event=(m.experience("save","afu_shui").recent_events as any[])[0];
    assert.equal(event.payload.failure_code,"market_stock_unavailable");assert.equal(event.payload.failure_details.gold,58);
    assert.equal(event.payload.failure_details.market_stock,0);assert.equal(event.payload.details_available,true);
  }finally{m.close();}
});

test("dialogue can discover market supply, inspect shortage, then register a non-binding request",async()=>{
  const {request}=fixture();
  request.allowed_command_tools.push("request_supply");
  const ctx=AgentRegistry.loadDefault().buildContext(request.agent_id,request,[]);
  let round=0;const reads:string[]=[];
  const intent=await runAgentLoop(request,ctx,{experience:{},memories:[],read:async(name,args)=>{
    reads.push(name);assert.equal(name,"query_world");assert.equal(args.section,"supply");
    return {item_id:"grain_seed",incoming:0,reason:"supplier_empty"};
  }},async(messages,tools)=>{
    if(round++===0)return response("discover_tools",{domains:["market"]});
    assert.ok(tools.some(t=>(t.function as any).name==="request_supply"));
    if(round===2)return response("query_world",{domain:"market",section:"supply",id:"grain_seed"});
    assert.ok(String(messages.at(-1)!.content).includes("supplier_empty"));
    return response("request_supply",{item_id:"grain_seed",quantity:4},"我会登记四份种子的补货需求，实际到货后再购买。");
  },()=>{});
  assert.deepEqual(reads,["query_world"]);assert.equal(round,3);
  assert.equal(intent.actions.length,1);assert.equal(intent.actions[0].tool_name,"request_supply");
  assert.deepEqual(intent.actions[0].arguments,{item_id:"grain_seed",quantity:4});
});
