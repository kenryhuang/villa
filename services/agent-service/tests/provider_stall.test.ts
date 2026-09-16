import test from "node:test";
import assert from "node:assert/strict";
import {createServer, type ServerResponse} from "node:http";
import {AgentRegistry} from "../src/agents.ts";
import {OpenAICompatibleProvider} from "../src/provider.ts";
import {ProviderConcurrencyGate} from "../src/provider_concurrency_gate.ts";
import {decodeProviderSse} from "../src/provider_stream.ts";
import type {DecisionRequest} from "../src/protocol.ts";

function fixture(id="stall") {
  const request={protocol_version:3,request_id:id,session_id:"stall-test",session_epoch:1,agent_id:"farmer_ahe",
    trigger:"dialogue",dialogue_input:"你好",game_minute:0,world_revision:1,active_role:"farmer",goals:[],
    allowed_command_tools:["speak","wait"],allowed_read_tools:[],actor_context:{},public_world_state:{},global_public_events:[],
    known_actors:[],own_event_delta:[],market_summary:{},market_view:{},interaction_view:{},agreement_view:{}} as unknown as DecisionRequest;
  const context=AgentRegistry.loadDefault().buildContext(request.agent_id,request,[]);
  context.loop_services={experience:{},memories:[],read:async()=>({})};
  return {request,context};
}
async function upstream(reply:(response:ServerResponse)=>void) {
  const server=createServer((request,response)=>{request.resume();request.on("end",()=>reply(response));});
  await new Promise<void>(resolve=>server.listen(0,"127.0.0.1",resolve));
  const address=server.address();assert.ok(address&&typeof address==="object");
  return {baseUrl:`http://127.0.0.1:${address.port}`,close:async()=>{server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));}};
}
const frame=(content:string)=>`data: ${JSON.stringify({choices:[{delta:{content},finish_reason:null}]})}\n\n`;

test("v3 heartbeat-only upstream times out and frees the slot for the next request",{timeout:3000},async()=>{
  let calls=0;
  const server=await upstream(response=>{
    response.writeHead(200,{"content-type":"text/event-stream"});
    if(++calls===1){
      const timer=setInterval(()=>response.write(": heartbeat\n\n"),10);
      response.once("close",()=>clearInterval(timer));return;
    }
    response.end(`data: ${JSON.stringify({choices:[{delta:{content:"你好"},finish_reason:"stop"}]})}\n\ndata: [DONE]\n\n`);
  });
  try {
    const provider=new OpenAICompatibleProvider({...server,apiKey:"fixture",model:"fixture",timeoutMs:2000,
      streamIdleTimeoutMs:100,loopTimeoutMs:2000,maxConcurrency:1,maxOutputTokens:1200,temperature:0});
    const {request,context}=fixture();const events:any[]=[];
    await assert.rejects(provider.streamDecision(request,context,e=>events.push(e)),/provider_stream_idle_timeout/);
    assert.deepEqual(events.filter(e=>e.type==="loop"&&e.payload.event==="provider.status").map(e=>e.payload.phase),["queued","waiting_provider"]);
    const next=fixture("after-timeout");
    assert.equal((await provider.decide(next.request,next.context)).speech,"你好");
  } finally {await server.close();}
});

test("v3 total loop deadline is not extended by continuous model output",{timeout:3000},async()=>{
  const server=await upstream(response=>{
    response.writeHead(200,{"content-type":"text/event-stream"});
    const timer=setInterval(()=>response.write(frame("正在思考")),10);
    response.once("close",()=>clearInterval(timer));
  });
  try {
    const provider=new OpenAICompatibleProvider({...server,apiKey:"fixture",model:"fixture",timeoutMs:2000,
      streamIdleTimeoutMs:1000,loopTimeoutMs:120,maxConcurrency:1,maxOutputTokens:1200,temperature:0});
    const {request,context}=fixture();let deltas=0;
    await assert.rejects(provider.streamDecision(request,context,e=>{if(e.type==="content")deltas++;}),/agent_loop_timeout/);
    assert.ok(deltas>0);
  } finally {await server.close();}
});

test("memory backlog uses at most one slot and leaves foreground decisions runnable",async()=>{
  const gate=new ProviderConcurrencyGate(3);const stop=new AbortController();let activeMemory=0,peak=0;
  const jobs=Array.from({length:5},()=>gate.run(stop.signal,async signal=>{
    activeMemory++;peak=Math.max(peak,activeMemory);
    try{await new Promise<void>((_,reject)=>signal.addEventListener("abort",()=>reject(signal.reason),{once:true}));}
    finally{activeMemory--;}
  },"maintenance"));
  try {assert.equal(await gate.run(undefined,async()=>"decision"),"decision");assert.equal(peak,1);}
  finally{stop.abort();await Promise.allSettled(jobs);}
});

test("DONE cancels and unlocks an upstream HTTP body that stays open",async()=>{
  let cancelled=false;
  const body=new ReadableStream<Uint8Array>({start(c){c.enqueue(new TextEncoder().encode(frame("完成")+"data: [DONE]\n\n"));},cancel(){cancelled=true;}});
  let chunks=0;for await(const _ of decodeProviderSse(body))chunks++;
  assert.equal(chunks,1);assert.equal(cancelled,true);assert.equal(body.locked,false);
});

test("a single-slot foreground decision preempts memory and memory resumes afterward",async()=>{
  const gate=new ProviderConcurrencyGate(1);const stop=new AbortController();let attempts=0;
  let started!:()=>void;const ready=new Promise<void>(resolve=>started=resolve);
  const memory=gate.run(stop.signal,async signal=>{
    attempts++;
    if(attempts>1)return "memory-saved";
    started();await new Promise<void>((_,reject)=>signal.addEventListener("abort",()=>reject(signal.reason),{once:true}));
  },"maintenance");
  try {
    await ready;
    assert.equal(await gate.run(undefined,async()=>"decision"),"decision");
    assert.equal(await memory,"memory-saved");assert.equal(attempts,2);
  }finally{stop.abort();await Promise.allSettled([memory]);}
});
