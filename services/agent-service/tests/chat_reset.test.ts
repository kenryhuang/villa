import test from "node:test";
import assert from "node:assert/strict";
import {createServer} from "node:http";
import {mkdtempSync,rmSync} from "node:fs";
import {join} from "node:path";
import {tmpdir} from "node:os";
import {createApp} from "../src/app.ts";
import {AgentRegistry} from "../src/agents.ts";
import {MemoryRepository,type MemoryEvent} from "../src/memory.ts";
import {chatRoomKey,chatGenerationScope} from "../src/chat_provider.ts";
import {actionActor} from "../src/context_channels.ts";
import type {DecisionRequest,ActionIntent} from "../src/protocol.ts";

test("reset isolates private/group context, persists in checkpoints, and fences late replies and handoffs",{timeout:10000},async()=>{
  const memory=new MemoryRepository(":memory:"),registry=AgentRegistry.loadDefault();
  const directory=mkdtempSync(join(tmpdir(),"villa-chat-reset-"));
  const histories=new Map<string,MemoryEvent[]>();
  let release!:()=>void,entered!:()=>void;
  const blocked=new Promise<void>(resolve=>release=resolve),waiting=new Promise<void>(resolve=>entered=resolve);
  const reply=(r:DecisionRequest):ActionIntent=>({protocol_version:2,decision_id:r.request_id,request_id:r.request_id,agent_id:r.agent_id,expected_revision:r.world_revision,actions:[],speech:`reply-${r.request_id}`,decision_summary:"chat",chat_isolated:true});
  const server=createServer(createApp({memory,registry,checkpointRoot:directory,
    provider:{decide:async r=>reply(r),streamDecision:async r=>reply(r)},
    chatProvider:{model:"test",respond:async(r,_context,history)=>{
      histories.set(r.request_id,history);
      if(r.request_id==="late"){entered();await blocked;return {...reply(r),chat_handoffs:[{kind:"visit",status:"agreed",target_actor_id:"player"}]};}
      return reply(r);
    }}}));
  await new Promise<void>(resolve=>server.listen(0,"127.0.0.1",resolve));
  const base=`http://127.0.0.1:${(server.address() as any).port}`;
  const post=async(path:string,body:unknown)=>fetch(base+path,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify(body)});
  const request=(id:string,actor="farmer_ahe",room?:DecisionRequest["chat_room"]):DecisionRequest=>({protocol_version:3,request_id:id,session_id:"reset-test",session_epoch:1,agent_id:actor,trigger:"dialogue",dialogue_input:`message-${id}`,game_minute:10,world_revision:1,active_role:"farmer",goals:[],allowed_command_tools:["wait","speak"],resources:{},experience_events:[],goal_refs:[],...(room?{chat_room:room}:{})} as DecisionRequest);
  const chat=async(r:DecisionRequest)=>(await post(`/v1/agents/${r.agent_id}/decide/stream`,r)).text();
  const reset=async(id:string,room?:DecisionRequest["chat_room"])=>{
    const response=await post("/v1/chat/reset",{session_id:"reset-test",session_epoch:1,agent_id:"farmer_ahe",game_minute:10,reset_id:id,...(room?{chat_room:room}:{})});
    assert.equal(response.status,200);return response.json() as Promise<{generation:string}>;
  };
  try{
    const room={id:"group",participants:["farmer_ahe","lao_li"],turn_id:"old"};
    await chat(request("old"));await chat(request("other","lao_li"));await chat(request("group-old","farmer_ahe",room));
    memory.appendEvent("reset-test",actionActor("farmer_ahe"),{event_id:"work",kind:"ActionCompleted",game_minute:10,payload:{gold:1}});
    const generation=(await reset("first")).generation;
    await chat(request("fresh"));
    assert.deepEqual(histories.get("fresh")!.map(e=>e.payload.text),["message-fresh"]);
    await chat(request("other-next","lao_li"));assert.ok(histories.get("other-next")!.some(e=>e.payload.text==="message-other"));
    await chat(request("group-next","farmer_ahe",{...room,turn_id:"next"}));assert.ok(histories.get("group-next")!.some(e=>e.payload.text==="message-group-old"));
    assert.equal((await reset("first")).generation,generation);
    await chat(request("after-retry"));assert.ok(histories.get("after-retry")!.some(e=>e.payload.text==="message-fresh"));
    await reset("group-reset",room);
    const freshRoom={...room,turn_id:"fresh-group"};
    await chat(request("group-fresh","farmer_ahe",freshRoom));
    assert.equal(histories.get("group-fresh")!.length,1);
    const second=request("group-second","lao_li",freshRoom);second.dialogue_input="message-group-fresh";
    await chat(second);assert.equal(histories.get("group-second")!.length,2);
    assert.ok(memory.inspectEvent("reset-test",actionActor("farmer_ahe"),"work").found);
    const old=chatRoomKey(request("old"));
    assert.ok(memory.inspectEvent("reset-test",old,"chat-user:old").found);
    const checkpoint=memory.exportCheckpoint("reset-test",directory,"reset");
    const restored=new MemoryRepository(":memory:");
    try{
      restored.importCheckpoint(checkpoint.path,checkpoint.sha256,"reset-test");
      assert.equal(restored.chatContextGeneration("reset-test",old),generation);
      const active=chatGenerationScope(old,generation);
      assert.deepEqual(restored.recent("reset-test",active,6),memory.recent("reset-test",active,6));
    }finally{restored.close();}
    const late=chat(request("late"));await waiting;
    await reset("race-reset");release();
    const stale=await late;assert.match(stale,/chat_context_reset/);assert.doesNotMatch(stale,/event: decision.final/);
    assert.equal(memory.inspectEvent("reset-test",actionActor("farmer_ahe"),"dialogue:late").found,false);
    await chat(request("after-race"));assert.deepEqual(histories.get("after-race")!.map(e=>e.payload.text),["message-after-race"]);
    const invalid=await post("/v1/chat/reset",{session_id:"reset-test",session_epoch:1,agent_id:"farmer_ahe",game_minute:10,reset_id:"bad",chat_room:{...room,participants:["village_public"]}});
    assert.equal(invalid.status,400);
  }finally{release();server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));memory.close();rmSync(directory,{recursive:true,force:true});}
});
