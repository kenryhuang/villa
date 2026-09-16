import test from "node:test";
import assert from "node:assert/strict";
import {mkdtempSync,rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {AgentRegistry} from "../src/agents.ts";
import {parseDecisionRequest} from "../src/protocol.ts";
import {AgentStreamAssembler} from "../src/provider_stream.ts";
import {runAgentLoop,DEFAULT_LOOP,compactWorkingMessages,inputEstimate} from "../src/agent_loop.ts";
import {MemoryRepository} from "../src/memory.ts";
import {WorldReadBroker} from "../src/world_read_broker.ts";
import {createServer} from "node:http";
import {createApp} from "../src/app.ts";
import {OpenAICompatibleProvider} from "../src/provider.ts";

function request(){const parsed=parseDecisionRequest({protocol_version:3,request_id:"loop-test",session_id:"save",session_epoch:1,
  agent_id:"farmer_ahe",trigger:"dialogue",game_minute:100,world_revision:5,active_role:"farmer",goals:["earn_stable_profit"],
  allowed_command_tools:["plant","speak","wait","adopt_short_term_goal"],resources:{gold:30,inventory:{grain_seed:2},resource_revision:1},
  experience_events:[],goal_refs:[],dialogue_input:"种植小麦"});assert.ok(parsed.ok);return parsed.value;}
function response(name?:string,args:Record<string,unknown>={},speech=""){
  const a=new AgentStreamAssembler();a.accept({id:"reply",choices:[{index:0,delta:{content:speech,...(name?{tool_calls:[{index:0,id:"call",type:"function",function:{name,arguments:JSON.stringify(args)}}]}:{})},finish_reason:name?"tool_calls":"stop"}]});return a;
}
test("compact request refuses eager data and has no world snapshot in first prompt",async()=>{
  const r=request();const ctx=AgentRegistry.loadDefault().buildContext(r.agent_id,r,[]);let rounds=0;
  const result=await runAgentLoop(r,ctx,{experience:{recent_events:[]},memories:[],read:async()=>{throw new Error("unexpected");}},async(messages,tools)=>{
    rounds++;const user=JSON.parse(String(messages[1].content));assert.equal(user.resources.gold,30);assert.ok(user.identity.soul);
    assert.equal("actor_context" in user,false);assert.equal("market_view" in user,false);
    assert.ok(!tools.some(t=>(t.function as any).name==="plant"));return response(undefined,{},"你好。");},()=>{});
  assert.equal(rounds,1);assert.equal(result.actions.length,0);
  assert.equal(parseDecisionRequest({...r,market_view:{secret:true}}).ok,false);
});
test("Loop discovers domains, reads three rounds, and submits one typed action",async()=>{
  const r=request();r.trigger="schedule";const ctx=AgentRegistry.loadDefault().buildContext(r.agent_id,r,[]);let step=0,reads=0;
  const sequence=[()=>response("discover_tools",{domains:["farm"]}),()=>response("query_world",{domain:"farm",section:"plots"}),
    ()=>response("query_world",{domain:"farm",section:"crops"}),()=>response("plant",{plot:0,seed_item_id:"grain_seed"})];
  const result=await runAgentLoop(r,ctx,{experience:{recent_events:[]},memories:[],read:async()=>{reads++;return {items:[{id:"real",state:"empty"}]};}},async()=>sequence[step++](),()=>{});
  assert.equal(step,4);assert.equal(reads,2);assert.equal(result.actions[0].tool_name,"plant");
});

test("each new Loop refreshes its header and starts without prior discoveries or world observations",async()=>{
  const registry=AgentRegistry.loadDefault(), first=request();let step=0;
  await runAgentLoop(first,registry.buildContext(first.agent_id,first,[]),{
    experience:{recent_events:[{event_id:"old-event"}]},memories:[],
    read:async()=>({ok:true,observation_id:"OLD_PRICE_SENTINEL",data:{price:999}}),
  },async()=>[
    ()=>response("discover_tools",{domains:["market"]}),
    ()=>response("query_world",{domain:"market",section:"detail",id:"bread"}),
    ()=>response(undefined,{},"已经查到。"),
  ][step++](),()=>{});
  const second={...request(),request_id:"next-loop",game_minute:101,resources:{gold:80,inventory:{bread:4},resource_revision:2}};
  await runAgentLoop(second,registry.buildContext(second.agent_id,second,[]),{
    experience:{recent_events:[{event_id:"new-event"}]},memories:[],read:async()=>{throw new Error("no automatic world prefetch");},
  },async(messages,tools)=>{
    assert.equal(messages.length,2);
    const header=JSON.parse(String(messages[1].content));
    assert.equal(header.resources.gold,80);assert.deepEqual(header.resources.inventory,{bread:4});
    assert.deepEqual(header.experience.recent_events,[{event_id:"new-event"}]);
    assert.deepEqual(header.turn.query_catalog,{});
    assert.equal(header.turn.budget.remaining_read_calls,DEFAULT_LOOP.max_read_calls);
    assert.equal(header.turn.budget.remaining_read_rounds,DEFAULT_LOOP.max_read_rounds);
    assert.ok(!JSON.stringify(messages).includes("OLD_PRICE_SENTINEL"));
    assert.ok(!JSON.stringify(messages).includes("continuation_summary"));
    assert.ok(tools.some(t=>(t.function as any).name==="discover_tools"));
    assert.ok(!tools.some(t=>(t.function as any).name==="query_world"));
    return response(undefined,{},"按当前状态继续。");
  },()=>{});
});
test("old working messages compact in complete pairs without changing protected resources",()=>{
  const messages=[{role:"system",content:"identity"},{role:"user",content:JSON.stringify({resources:{gold:12345},recent_events:Array(15).fill({kind:"dialogue"})})},
    {role:"assistant",tool_calls:[{id:"a"}]},{role:"tool",tool_call_id:"a",name:"query_world",content:JSON.stringify({observation_id:"obs",domain_revision:1,service_records:Array(100).fill({x:"old delivered job"}),items:[{x:"detail"}]})}];
  const compacted=compactWorkingMessages(messages);assert.deepEqual(compacted.slice(0,2),messages.slice(0,2));
  assert.ok(inputEstimate(compacted)<inputEstimate(messages));assert.ok(!compacted.some(m=>"tool_call_id"in m));
  const again=compactWorkingMessages([...compacted,{role:"assistant",tool_calls:[{id:"b"}]},{role:"tool",tool_call_id:"b",name:"query_world",content:JSON.stringify({observation_id:"new",items:[{x:1}]})}]);
  const facts=JSON.parse(String(again[2].content)).continuation_summary.observations;
  assert.ok(facts.some((f:any)=>f.observation_id==="new"));
  assert.ok(facts.some((f:any)=>f.observation_id==="obs"),"retains prior structured observation on second compaction");
  const bounded=compactWorkingMessages(messages,inputEstimate(messages.slice(0,2))+400);
  assert.ok(inputEstimate(bounded)<=inputEstimate(messages.slice(0,2))+400);
});
test("15 latest persisted events are independent of old memories and observer IDs",()=>{
  const directory=mkdtempSync(join(tmpdir(),"loop-memory-"));const m=new MemoryRepository(join(directory,"db.sqlite"));
  try{m.syncSession("save",1);
    for(let i=0;i<20;i++)m.appendEvent("save","a",{event_id:`e${i}`,kind:"dialogue",game_minute:20-i,payload:{text:`面包 ${i}`}});
    m.appendEvent("save","b",{event_id:"e19",kind:"dialogue",game_minute:1,payload:{text:"private"}});
    const exp=m.experience("save","a") as any;assert.equal(exp.recent_events.length,15);assert.equal(exp.recent_events[0].event_id,"e5");assert.equal(exp.older_summary.covered_count,5);
    m.storeLongTermMemory("save","a","bread-memory","玩家想购买面包",8,["e0"]);
    assert.ok(m.relevant("save","a","面包需求").length);assert.equal(m.relevant("save","b","面包需求").length,0);
    assert.equal(m.inspectEvent("save","a","e19").payload.text,"面包 19");assert.equal(m.inspectEvent("save","b","e19").payload.text,"private");
    m.syncResources("save","a",1,2,{gold:25});assert.throws(()=>m.syncResources("save","a",1,1,{gold:40}),/stale/);
    const cp=m.exportCheckpoint("save",directory,"checkpoint");m.appendEvent("save","a",{event_id:"future",kind:"dialogue",game_minute:100,payload:{}});
    m.importCheckpoint(cp.path,cp.sha256,"save");assert.equal(m.inspectEvent("save","a","future").found,false);
  }finally{m.close();rmSync(directory,{recursive:true,force:true});}
});
test("world read broker binds actor/request/epoch and cancellation",async()=>{
  const broker=new WorldReadBroker(),r=request();let sent:any;
  const pending=broker.read(r,"query_world",{domain:"farm"},p=>sent=p);
  assert.throws(()=>broker.accept({...sent,agent_id:"other",result:{ok:true}}),/scope/);
  assert.ok(broker.accept({...sent,result:{ok:true,items:[]}}));assert.equal((await pending).ok,true);
  const c=new AbortController();const cancelled=broker.read(r,"query_world",{},()=>{},c.signal);c.abort();await assert.rejects(cancelled,/cancelled/);
});

test("capacity pressure compacts after the normal count limit and keeps quotes",async()=>{
  const r=request();r.trigger="schedule";const ctx=AgentRegistry.loadDefault().buildContext(r.agent_id,r,[]);
  let step=0;const traces:any[]=[];
  const sequence=[()=>response("discover_tools",{domains:["market"]}),
    ()=>response("query_world",{domain:"market",section:"detail",id:"bread"}),
    ()=>response("query_world",{domain:"market",section:"detail",id:"flour"}),()=>response()];
  await runAgentLoop(r,ctx,{experience:{},memories:[],read:async(_n,a)=>({ok:true,observation_id:a.id,
    service_records:{old:"historical-order ".repeat(6000)},data:{item_id:a.id,price:12}})},
    async(messages)=>{
      if(step===3){
        const facts=JSON.parse(String(messages[2].content)).continuation_summary.observations;
        assert.ok(facts.some((f:any)=>f.facts.data?.item_id==="flour"&&f.facts.data.price===12));
      }
      return sequence[step++]();
    },e=>traces.push(e),undefined,{...DEFAULT_LOOP,max_compactions:1});
  const events=traces.filter(e=>e.payload?.event==="context.compacted");
  assert.equal(events.length,2);assert.equal(events[1].payload.reason,"hard_limit_recovery");
  assert.ok(events.every(e=>e.payload.after<=DEFAULT_LOOP.max_input_tokens));
  assert.equal(traces.filter(e=>e.payload?.event==="loop.round").at(-1).payload.reads,3);
});

test("compaction target accounts for the protected header and preserves a usable quote",async()=>{
  const r=request(),ctx=AgentRegistry.loadDefault().buildContext(r.agent_id,r,[]);let step=0;const traces:any[]=[];
  const sequence=[()=>response("discover_tools",{domains:["market"]}),()=>response("query_world",{domain:"market",section:"detail",id:"bread"}),()=>response(undefined,{},"已核实。")];
  await runAgentLoop(r,ctx,{experience:{recent_events:[{event_id:"e",text:"重要经历".repeat(1000)}]},memories:[],read:async()=>({ok:true,data:{fee:12}})},async(messages)=>{
    if(step===2)assert.ok(JSON.stringify(messages).includes('\\"fee\\":12'));
    return sequence[step++]();
  },e=>traces.push(e),undefined,{...DEFAULT_LOOP,compact_at_tokens:9000,compact_target_tokens:6000,max_input_tokens:40000});
  const events=traces.filter(e=>e.payload?.event==="context.compacted");
  assert.ok(events.length);assert.ok(events.every(e=>e.payload.target>e.payload.configured_target&&e.payload.target_met));
});

test("an oversized immutable header fails with capacity diagnostics rather than claiming compaction",async()=>{
  const r=request(),ctx=AgentRegistry.loadDefault().buildContext(r.agent_id,r,[]);const traces:any[]=[];
  await assert.rejects(runAgentLoop(r,ctx,{experience:{text:"x".repeat(100000)},memories:[],read:async()=>({})},
    async()=>{throw new Error("must not send oversized input");},e=>traces.push(e)),/context_capacity_exceeded/);
  const detail=traces.find(e=>e.payload?.event==="context.capacity_exceeded").payload;
  assert.equal(detail.reason,"protected_header_and_tools");assert.ok(detail.protected_input>detail.limit);
});

test("Loop automatically compacts oversized tool history without resetting read budgets",async()=>{
  const r=request(),ctx=AgentRegistry.loadDefault().buildContext(r.agent_id,r,[]);let step=0;const traces:any[]=[];
  const sequence=[()=>response("discover_tools",{domains:["farm"]}),()=>response("query_world",{domain:"farm",section:"plots"}),
    ()=>response("query_world",{domain:"farm",section:"crops"}),()=>response(undefined,{},"我先等等。")];
  await runAgentLoop(r,ctx,{experience:{recent_events:[]},memories:[],read:async()=>({observation_id:"large",items:Array(200).fill({name:"old details of a farm plot",state:"empty"})})},
    async()=>sequence[step++](),event=>traces.push(event),undefined,{...DEFAULT_LOOP,compact_at_tokens:8000,compact_target_tokens:6000,max_input_tokens:16000});
  const compressed=traces.filter(t=>t.type==="loop"&&t.payload.event==="context.compacted");assert.ok(compressed.length>=1);
  assert.ok(compressed.every(t=>t.payload.after<t.payload.before));
  const last=traces.filter(t=>t.type==="loop"&&t.payload.event==="loop.round").at(-1);assert.equal(last.payload.reads,3);
});

test("real service SSE performs lazy Godot read roundtrip before final reply",async()=>{
  const directory=mkdtempSync(join(tmpdir(),"loop-wire-"));const memory=new MemoryRepository(join(directory,"memory.sqlite"));
  let modelCalls=0;const prompts:any[]=[];
  const upstream=createServer(async(req,res)=>{
    const chunks=[];for await(const chunk of req)chunks.push(chunk);const body=JSON.parse(Buffer.concat(chunks).toString());prompts.push(body);
    const actions=[{name:"discover_tools",arguments:JSON.stringify({domains:["farm"]})},{name:"query_world",arguments:JSON.stringify({domain:"farm",section:"plots"})}];
    const action=actions[modelCalls++];
    res.writeHead(200,{"content-type":"text/event-stream"});
    res.end(`data: ${JSON.stringify({id:"wire",choices:[{index:0,delta:action?{tool_calls:[{index:0,id:"wire-call",type:"function",function:action}]}:{content:"这里有一块空地。"},finish_reason:action?"tool_calls":"stop"}]})}\n\ndata: [DONE]\n\n`);
  });
  await new Promise<void>(resolve=>upstream.listen(0,"127.0.0.1",resolve));
  const provider=new OpenAICompatibleProvider({baseUrl:`http://127.0.0.1:${(upstream.address() as any).port}`,apiKey:"test",model:"test",timeoutMs:3000,maxConcurrency:2,maxOutputTokens:500,temperature:0});
  const server=createServer(createApp({memory,registry:AgentRegistry.loadDefault(),provider,checkpointRoot:directory}));
  await new Promise<void>(resolve=>server.listen(0,"127.0.0.1",resolve));
  const base=`http://127.0.0.1:${(server.address() as any).port}`;
  try{
    const full=request();const wire=Object.fromEntries(Object.entries(full).filter(([key])=>!["actor_context","projection_schema_version","allowed_read_tools","public_world_state","global_public_events","known_actors","own_event_delta","market_summary","market_view","interaction_view","agreement_view"].includes(key)));
    const response=await fetch(base+"/v1/agents/farmer_ahe/decide/stream",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify(wire)});
    assert.equal(response.status,200);let buffer="",final:any,readRequests=0;
    const decoder=new TextDecoder();
    for await(const chunk of response.body!){buffer+=decoder.decode(chunk,{stream:true});let end:number;
      while((end=buffer.indexOf("\n\n"))>=0){const entry=buffer.slice(0,end);buffer=buffer.slice(end+2);const data=entry.split("\n").find(l=>l.startsWith("data: "));if(!data)continue;
        const envelope=JSON.parse(data.slice(6));
        if(entry.includes("event: read.request")){readRequests++;const result=await fetch(base+"/v1/reads/result",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({...envelope.payload,result:{ok:true,observation_id:"real-plot",items:[{plot:0,state:"empty"}]}})});assert.equal(result.status,200);}
        if(entry.includes("event: decision.final"))final=envelope.payload;
        assert.ok(!entry.includes("event: stream.error"),entry);
      }
    }
    assert.equal(readRequests,1);assert.equal(modelCalls,3);assert.equal(final.speech,"这里有一块空地。");
    assert.ok(prompts[2].messages.some((m:any)=>m.role==="tool"&&m.content.includes("real-plot")));
    assert.equal(JSON.parse(prompts[0].messages[1].content).resources.gold,30);
    assert.equal(memory.recent("save","farmer_ahe",15).filter(e=>e.kind==="dialogue").length,1);
  }finally{server.closeAllConnections();upstream.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));await new Promise<void>(resolve=>upstream.close(()=>resolve()));memory.close();rmSync(directory,{recursive:true,force:true});}
});
