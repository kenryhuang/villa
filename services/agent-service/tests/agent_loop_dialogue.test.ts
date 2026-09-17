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

const honeyTrade={target_actor_id:"player",give:{items:{},gold:60},receive:{items:{honey:5},gold:0},
  expires_in_minutes:30,note:"按约定12金/个收5个蜂蜜，共60金。"};

for (const [name,args] of [
  ["propose_trade",honeyTrade],
  ["counter_trade",{offer_id:"trade-1",give:honeyTrade.give,receive:honeyTrade.receive,expires_in_minutes:30,note:"新的报价"}],
  ["accept_trade",{offer_id:"trade-1"}],
  ["reject_trade",{offer_id:"trade-1",reason_code:"price_too_high"}],
  ["cancel_trade",{offer_id:"trade-1"}],
] as const) {
  test(`tool-only dialogue ${name} preserves the action and supplies pending-state speech`,async()=>{
    const {request}=fixture();request.allowed_command_tools.push(name);
    request.dialogue_input="同意，交易吧";
    const ctx=AgentRegistry.loadDefault().buildContext(request.agent_id,request,[]);
    let rounds=0;const events:any[]=[];let output:AgentStreamAssembler;
    const intent=await runAgentLoop(request,ctx,{experience:{},memories:[],read:async()=>{throw Error("unexpected world read");}},async()=>{
      if(rounds++===0)return response("discover_tools",{domains:["actors"],actions:[name]});
      output=response(name,args);return output;
    },e=>events.push(e));
    assert.equal(rounds,2,"No extra model correction for a legal trade");
    assert.equal(intent.actions.length,1,"Reply does not consume a second action or submit speak");
    assert.equal(intent.actions[0].tool_name,name);assert.deepEqual(intent.actions[0].arguments,args);
    assert.equal(intent.actions[0].idempotency_key,"v2:greeting:0:call");
    assert.match(intent.speech!,/准备/);assert.doesNotMatch(intent.speech!,/已成交|交易成功|已扣除/);
    assert.equal(output!.rawOutput().message.content,"","Raw provider output remains unmodified");
    assert.equal(events.filter(e=>e.payload?.event==="dialogue.reply_fallback").length,1);
    assert.equal(events.filter(e=>e.payload?.event==="loop.validation_failed").length,0);
  });
}

test("trade fallback cannot bypass invalid amounts or the one-action dialogue budget",async()=>{
  for(const multiple of [false,true]){
    const {request}=fixture();request.allowed_command_tools.push("propose_trade");
    const ctx=AgentRegistry.loadDefault().buildContext(request.agent_id,request,[]);
    let rounds=0;const events:any[]=[];
    await assert.rejects(runAgentLoop(request,ctx,{experience:{},memories:[],read:async()=>({})},async()=>{
      if(rounds++===0)return response("discover_tools",{domains:["actors"]});
      if(!multiple)return response("propose_trade",{...honeyTrade,give:{items:{},gold:-60}});
      const output=response("propose_trade",honeyTrade);
      output.accept({choices:[{index:0,delta:{tool_calls:[{index:1,id:"second",function:{name:"propose_trade",arguments:JSON.stringify(honeyTrade)}}]},finish_reason:"tool_calls"}]});
      return output;
    },e=>events.push(e)),multiple?/provider_too_many_tool_calls/:/invalid_action_arguments/);
    assert.equal(events.filter(e=>e.payload?.event==="dialogue.reply_fallback").length,0);
  }
});

test("trade fallback preserves supplied speech and does not narrate background decisions",async()=>{
  for(const dialogue of [true,false]){
    const {request}=fixture();request.allowed_command_tools.push("propose_trade");
    if(!dialogue)request.trigger="event";
    const ctx=AgentRegistry.loadDefault().buildContext(request.agent_id,request,[]);
    let rounds=0;const events:any[]=[];
    const speech=dialogue?"我愿意出60金币买你的5个蜂蜜，请确认报价。":"";
    const intent=await runAgentLoop(request,ctx,{experience:{},memories:[],read:async()=>({})},async()=>{
      if(rounds++===0)return response("discover_tools",{domains:["actors"]});
      return response("propose_trade",honeyTrade,speech);
    },e=>events.push(e));
    assert.equal(intent.speech??"",speech);
    assert.equal(events.filter(e=>e.payload?.event==="dialogue.reply_fallback").length,0);
  }
});
