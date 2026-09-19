import test from "node:test";
import assert from "node:assert/strict";
import {createServer} from "node:http";
import {AgentRegistry} from "../src/agents.ts";
import {parseDecisionRequest,parseActionIntent,type DecisionRequest} from "../src/protocol.ts";
import {LocalChatProvider} from "../src/chat_provider.ts";
import {chatMessages,CHAT_HISTORY_MESSAGES,CHAT_HISTORY_CHARS} from "../src/chat_context.ts";
import {prepareActionRequest} from "../src/context_channels.ts";
import {MemoryRepository} from "../src/memory.ts";

function fixture(){
  const parsed=parseDecisionRequest({protocol_version:3,request_id:"stream-chat",session_id:"s",session_epoch:1,agent_id:"farmer_ahe",trigger:"dialogue",dialogue_input:"大家好",
    game_minute:10,world_revision:1,active_role:"farmer",goals:[],allowed_command_tools:["speak","wait"],resources:{gold:111,inventory:{INVENTORY_SENTINEL:1}},experience_events:[],goal_refs:[]});
  assert.ok(parsed.ok);const request=parsed.value;
  const registry=AgentRegistry.loadDefault();return {request,context:registry.buildContext(request.agent_id,request,[]),registry};
}

test("chat context keeps own persona, no other character profiles and only recent natural-text history",()=>{
  const {request:r,context:c,registry}=fixture();
  const p={actor_id:"player",display_name:"玩家自定义",role:"player",soul:registry.get("farmer_ahe")!.soul,relationship:{status:"dating" as const,label:"恋人",affinity:80,mutual_affinity:80,version:2}};
  r.chat_room={id:"group",turn_id:"turn",participants:["farmer_ahe","resident_yun"]};
  r.chat_participants=[p,{...p,actor_id:"resident_yun",display_name:"伊可存档名",role:"merchant",soul:registry.get("resident_yun")!.soul}];
  const wire:any={...r};for(const k of ["actor_context","market_view","known_actors","public_world_state"])delete wire[k];
  assert.ok(parseDecisionRequest(wire).ok);
  assert.equal(parseDecisionRequest({...wire,chat_participants:[p,{...p,actor_id:"not-in-room"}]}).ok,false);
  const history=Array.from({length:30},(_,i)=>({event_id:String(i),kind:"ChatMessage",game_minute:i,payload:{speaker:"player",text:`conversation-${i}`}}));
  const messages=chatMessages(r,c,history,[{id:"outsider",name:"OUTSIDER_SENTINEL"}]);
  const header=JSON.parse(String(messages[0].content));
  assert.deepEqual(header.identity.soul,c.agent.soul);
  assert.equal(header.player,"玩家自定义");
  assert.equal(header.participants,undefined);
  assert.doesNotMatch(String(messages[0].content),/伊可存档名|mutual_affinity/);
  assert.deepEqual(Object.keys(header).sort(),["background","identity","player","rules"]);
  assert.doesNotMatch(JSON.stringify(messages),/INVENTORY_SENTINEL|OUTSIDER_SENTINEL|conversation-0"/);
  assert.ok(messages.length<=CHAT_HISTORY_MESSAGES+1);assert.match(JSON.stringify(messages),/conversation-29/);
  assert.equal(messages.at(-1)?.content,"大家好");
  const memory=new MemoryRepository(":memory:");
  try{assert.equal(prepareActionRequest(memory,{...r,trigger:"schedule"}).chat_participants,undefined);}finally{memory.close();}
});

test("history budget reserves current player turn, preserves group ordering, and never splits old replies",()=>{
  const {request:r,context:c}=fixture();
  r.chat_room={id:"room",turn_id:"turn",participants:[r.agent_id,"resident_yun"]};
  r.dialogue_input="本轮".repeat(400);
  const history=[
    {event_id:"old-user",kind:"ChatMessage",game_minute:1,payload:{speaker:"player",text:"OLD_USER"}},
    {event_id:"old-reply",kind:"ChatMessage",game_minute:1,payload:{speaker:r.agent_id,text:"OLD_REPLY".repeat(250)}},
    {event_id:"chat-user:turn",kind:"ChatMessage",game_minute:2,payload:{speaker:"player",text:r.dialogue_input}},
    {event_id:"group-reply",kind:"ChatMessage",game_minute:2,payload:{speaker:"resident_yun",text:"本轮已经听到了"}},
  ];
  const messages=chatMessages(r,c,history,[{id:"resident_yun",name:"伊可"}]);
  assert.deepEqual(messages.slice(1).map(m=>m.content),[r.dialogue_input,"【伊可】\n本轮已经听到了"]);
  assert.ok(messages.slice(1).reduce((n,m)=>n+String(m.content).length,0)<=CHAT_HISTORY_CHARS);
  assert.doesNotMatch(JSON.stringify(messages),/OLD_REPLY|OLD_USER/);
  const own=chatMessages(r,c,[{event_id:"reply",kind:"ChatMessage",game_minute:1,payload:{speaker:r.agent_id,text:"自然的回复"}}],[]);
  assert.deepEqual(own[1],{role:"assistant",content:"自然的回复"});
});

test("first token arrives before completion, world queries or JSON extraction; UTF-8 chunks assemble once",{timeout:5000},async()=>{
  let release!:()=>void,first!:()=>void;
  const barrier=new Promise<void>(resolve=>release=resolve),firstToken=new Promise<void>(resolve=>first=resolve);
  const bodies:any[]=[],deltas:string[]=[],reads:any[]=[],events:any[]=[];
  const tail="，春天的花田很漂亮。".repeat(70)+"🌷";
  const server=createServer(async(req,res)=>{
    let input="";for await(const chunk of req)input+=chunk;const body=JSON.parse(input);bodies.push(body);
    if(!body.stream){res.setHeader("content-type","application/json");res.end(JSON.stringify({model:"cydonia-resolved",choices:[{finish_reason:"stop",message:{content:'{"handoffs":[],"relationship":null}'}}]}));return;}
    res.setHeader("content-type","text/event-stream");
    const firstChunk=Buffer.from(`data: ${JSON.stringify({id:"stream",model:"cydonia-resolved",choices:[{delta:{content:"你好"},finish_reason:null}]})}\r\n\r\n`);
    const split=firstChunk.indexOf(Buffer.from("你"))+1;
    res.write(firstChunk.subarray(0,split));res.write(firstChunk.subarray(split));
    await barrier;
    res.write(`data: ${JSON.stringify({choices:[{delta:{content:tail},finish_reason:null}]})}\n\n`);
    res.end(`data: ${JSON.stringify({choices:[{delta:{},finish_reason:"stop"}],usage:{completion_tokens:10}})}\n\ndata: [DONE]\n\n`);
  });
  await new Promise<void>(resolve=>server.listen(0,"127.0.0.1",resolve));
  try{
    const provider=new LocalChatProvider({baseUrl:`http://127.0.0.1:${(server.address() as any).port}/v1`,apiKey:"local",model:"cydonia-test",timeoutMs:2000,maxConcurrency:1,maxOutputTokens:800,temperature:.7});
    const {request,context}=fixture();let finished=false;
    const pending=provider.respond(request,context,[],[],async(_name,args)=>{reads.push(args);return {ok:true,items:[],next_cursor:-1};},event=>{
      events.push(event);if(event.type==="content"){deltas.push(event.delta);first();}
    }).then(value=>{finished=true;return value;});
    await firstToken;
    assert.deepEqual(deltas,["你好"]);assert.equal(finished,false);assert.equal(bodies.length,1);assert.deepEqual(reads,[]);
    assert.doesNotMatch(JSON.stringify(bodies[0]),/INVENTORY_SENTINEL/);
    release();const reply=await pending;
    assert.equal(reply.speech,deltas.join(""));assert.equal(deltas.length,2);assert.equal(bodies[1].stream,false);
    assert.equal(reply.speech,"你好"+tail);
    assert.ok(reply.speech!.length>500 && parseActionIntent(reply,[]).ok);
    assert.equal(parseActionIntent({...reply,chat_isolated:false},[]).ok,false);
    assert.equal(events.filter(e=>e.payload?.event==="chat.first_token").length,1);
    assert.equal(events.filter(e=>e.type==="output").length,2);
    assert.deepEqual(events.filter(e=>e.type==="output").map(e=>e.output.model),["cydonia-resolved","cydonia-resolved"]);
    const routes=events.filter(e=>e.payload?.event==="provider.route").map(e=>e.payload);
    assert.deepEqual(routes.map(r=>r.phase),["dialogue","extract_actions"]);
    assert.ok(routes.every(r=>r.model==="cydonia-test" && r.endpoint.endsWith("/v1/chat/completions")));
    assert.ok(events.some(e=>e.payload?.event==="provider.response_model" && e.payload.model==="cydonia-resolved"));
    const timings=events.filter(e=>e.payload?.event==="chat.timing").map(e=>e.payload);
    assert.deepEqual(timings.map(t=>[t.phase,t.status]),[["dialogue","completed"],["extract_actions","completed"]]);
    assert.equal(timings[0].content_chunks,2);
    assert.equal(timings[0].content_characters,reply.speech!.length);
    assert.ok(timings[0].first_token_ms>=0);
    assert.equal(timings[1].first_token_ms,null);
  }finally{release();server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));}
});

test("disconnected or cancelled streams never produce an action handoff",{timeout:5000},async()=>{
  let mode="disconnect",connections=0;
  const server=createServer(async(req,res)=>{for await(const _chunk of req){}connections++;
    res.setHeader("content-type","text/event-stream");
    res.write(`data: ${JSON.stringify({choices:[{delta:{content:"还没说完"},finish_reason:null}]})}\n\n`);
    if(mode==="disconnect")res.end();
    if(mode==="length")res.end(`data: ${JSON.stringify({choices:[{delta:{},finish_reason:"length"}]})}\n\ndata: [DONE]\n\n`);
  });
  await new Promise<void>(resolve=>server.listen(0,"127.0.0.1",resolve));
  try{
    const provider=new LocalChatProvider({baseUrl:`http://127.0.0.1:${(server.address() as any).port}/v1`,apiKey:"local",model:"test",timeoutMs:2000,maxConcurrency:1,maxOutputTokens:800,temperature:.7});
    const {request,context}=fixture();let reads=0;
    const read=async()=>{reads++;return {};};
    await assert.rejects(provider.respond(request,context,[],[],read,()=>{}),/chat_provider_incomplete_reply/);
    mode="length";
    await assert.rejects(provider.respond(request,context,[],[],read,()=>{}),/chat_provider_output_limit/);
    mode="cancel";const controller=new AbortController();
    const timings:any[]=[];
    await assert.rejects(provider.respond(request,context,[],[],read,e=>{
      if(e.type==="content")controller.abort();
      if(e.type==="loop" && e.payload.event==="chat.timing")timings.push(e.payload);
    },controller.signal));
    assert.equal(timings.length,1);assert.equal(timings[0].status,"cancelled");assert.equal(timings[0].content_chunks,1);
    assert.equal(reads,0);assert.equal(connections,3);
  }finally{server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));}
});
