import test from "node:test";
import assert from "node:assert/strict";
import {createServer} from "node:http";
import {AgentRegistry} from "../src/agents.ts";
import {parseDecisionRequest,type DecisionRequest} from "../src/protocol.ts";
import {LocalChatProvider} from "../src/chat_provider.ts";
import {chatMessages} from "../src/chat_context.ts";
import {prepareActionRequest} from "../src/context_channels.ts";
import {MemoryRepository} from "../src/memory.ts";

function fixture(){
  const parsed=parseDecisionRequest({protocol_version:3,request_id:"stream-chat",session_id:"s",session_epoch:1,agent_id:"farmer_ahe",trigger:"dialogue",dialogue_input:"大家好",
    game_minute:10,world_revision:1,active_role:"farmer",goals:[],allowed_command_tools:["speak","wait"],resources:{gold:111,inventory:{INVENTORY_SENTINEL:1}},experience_events:[],goal_refs:[]});
  assert.ok(parsed.ok);const request=parsed.value;
  const registry=AgentRegistry.loadDefault();return {request,context:registry.buildContext(request.agent_id,request,[]),registry};
}

test("chat context contains full personas, only current participants and bounded room history",()=>{
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
  assert.deepEqual(header.participants,r.chat_participants);
  assert.deepEqual(Object.keys(header).sort(),["background","identity","participants","rules"]);
  assert.doesNotMatch(JSON.stringify(messages),/INVENTORY_SENTINEL|OUTSIDER_SENTINEL|conversation-0"/);
  assert.ok(messages.length<=18);assert.match(JSON.stringify(messages),/conversation-29/);
  const memory=new MemoryRepository(":memory:");
  try{assert.equal(prepareActionRequest(memory,{...r,trigger:"schedule"}).chat_participants,undefined);}finally{memory.close();}
});

test("first token arrives before completion, world queries or JSON extraction; UTF-8 chunks assemble once",{timeout:5000},async()=>{
  let release!:()=>void,first!:()=>void;
  const barrier=new Promise<void>(resolve=>release=resolve),firstToken=new Promise<void>(resolve=>first=resolve);
  const bodies:any[]=[],deltas:string[]=[],reads:any[]=[],events:any[]=[];
  const server=createServer(async(req,res)=>{
    let input="";for await(const chunk of req)input+=chunk;const body=JSON.parse(input);bodies.push(body);
    if(!body.stream){res.setHeader("content-type","application/json");res.end(JSON.stringify({choices:[{finish_reason:"stop",message:{content:'{"handoffs":[],"relationship":null}'}}]}));return;}
    res.setHeader("content-type","text/event-stream");
    const firstChunk=Buffer.from(`data: ${JSON.stringify({id:"stream",choices:[{delta:{content:"你好"},finish_reason:null}]})}\r\n\r\n`);
    const split=firstChunk.indexOf(Buffer.from("你"))+1;
    res.write(firstChunk.subarray(0,split));res.write(firstChunk.subarray(split));
    await barrier;
    res.write(`data: ${JSON.stringify({choices:[{delta:{content:"，很高兴见到你。"},finish_reason:null}]})}\n\n`);
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
    assert.equal(events.filter(e=>e.payload?.event==="chat.first_token").length,1);
    assert.equal(events.filter(e=>e.type==="output").length,2);
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
  });
  await new Promise<void>(resolve=>server.listen(0,"127.0.0.1",resolve));
  try{
    const provider=new LocalChatProvider({baseUrl:`http://127.0.0.1:${(server.address() as any).port}/v1`,apiKey:"local",model:"test",timeoutMs:2000,maxConcurrency:1,maxOutputTokens:800,temperature:.7});
    const {request,context}=fixture();let reads=0;
    const read=async()=>{reads++;return {};};
    await assert.rejects(provider.respond(request,context,[],[],read,()=>{}),/chat_provider_incomplete_reply/);
    mode="cancel";const controller=new AbortController();
    const timings:any[]=[];
    await assert.rejects(provider.respond(request,context,[],[],read,e=>{
      if(e.type==="content")controller.abort();
      if(e.type==="loop" && e.payload.event==="chat.timing")timings.push(e.payload);
    },controller.signal));
    assert.equal(timings.length,1);assert.equal(timings[0].status,"cancelled");assert.equal(timings[0].content_chunks,1);
    assert.equal(reads,0);assert.equal(connections,2);
  }finally{server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));}
});
