import test from "node:test";
import assert from "node:assert/strict";
import {createServer} from "node:http";
import {mkdtempSync,rmSync} from "node:fs";
import {tmpdir} from "node:os";
import {join} from "node:path";
import {MemoryRepository,type MemoryEvent} from "../src/memory.ts";
import {AgentRegistry} from "../src/agents.ts";
import {prepareChatContext} from "../src/chat_summary.ts";
import {LocalChatProvider,chatRoomKey,chatGenerationScope,type ChatPort} from "../src/chat_provider.ts";
import {CHAT_HISTORY_MESSAGES,CHAT_SUMMARY_CHARS,chatMessages} from "../src/chat_context.ts";
import {createApp} from "../src/app.ts";
import {parseDecisionRequest,type DecisionRequest,type ActionIntent} from "../src/protocol.ts";

const request=(id:string):DecisionRequest=>({protocol_version:3,request_id:id,session_id:"summary",session_epoch:1,agent_id:"farmer_ahe",trigger:"dialogue",dialogue_input:`问题-${id}`,game_minute:10,world_revision:1,active_role:"farmer",goals:[],allowed_command_tools:["wait","speak"],resources:{},experience_events:[],goal_refs:[]} as DecisionRequest);
const reply=(r:DecisionRequest):ActionIntent=>({protocol_version:2,decision_id:r.request_id,request_id:r.request_id,agent_id:r.agent_id,expected_revision:r.world_revision,actions:[],speech:`答复-${r.request_id}`,decision_summary:"chat",chat_isolated:true});
const message=(id:string,speaker:string,text:string,minute=10):MemoryEvent=>({event_id:id,kind:"ChatMessage",game_minute:minute,payload:{speaker,text}});

test("HTTP chat rolls old messages into a bounded summary, retaining eight recent messages across many turns",async()=>{
  const memory=new MemoryRepository(":memory:"),registry=AgentRegistry.loadDefault();
  const sources:string[]=[],windows:any[]=[],summaries:string[]=[];
  const directory=mkdtempSync(join(tmpdir(),"villa-chat-summary-"));
  const chat:ChatPort={model:"test",summarize:async(previous,events)=>{
    for(const event of events){assert.ok(!sources.includes(event.event_id));sources.push(event.event_id);}
    if(summaries.length)assert.equal(previous,summaries.at(-1));
    const summary=`已讨论并回答${sources.length}条历史消息；玩家喜欢种花。`;summaries.push(summary);return summary;
  },respond:async(r,c,history,actors,_read,_emit,_signal,summary)=>{
    windows.push({history,summary,messages:chatMessages(r,c,history,actors,summary)});return reply(r);
  }};
  const server=createServer(createApp({memory,registry,chatProvider:chat,checkpointRoot:directory,provider:{decide:async r=>reply(r),streamDecision:async r=>reply(r)}}));
  await new Promise<void>(resolve=>server.listen(0,"127.0.0.1",resolve));
  try{
    for(let i=0;i<18;i++){
      const r=request(String(i));r.game_minute=100-i; // Clock edits must not reorder conversation.
      const res=await fetch(`http://127.0.0.1:${(server.address() as any).port}/v1/agents/${r.agent_id}/decide/stream`,{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify(r)});
      assert.match(await res.text(),/event: decision.final/);
      const window=windows.at(-1)!;
      assert.ok(window.history.length<=CHAT_HISTORY_MESSAGES);
      assert.equal(window.history.at(-1).payload.text,r.dialogue_input);
      assert.equal(window.messages.length,window.history.length+1);
      if(i>=4){assert.equal(window.history.length,8);assert.equal(JSON.parse(window.messages[0].content).conversation_summary,window.summary);}
    }
    assert.equal(sources.length,27);assert.equal(windows.at(-1).history[0].event_id,"chat-reply:13");
    assert.doesNotMatch(JSON.stringify(windows.at(-1).messages),/问题-0"|答复-0"/);
    const scope=chatRoomKey(request("x"));
    const checkpoint=memory.exportCheckpoint("summary",directory,"chat-summary");
    const restored=new MemoryRepository(":memory:");
    try{
      restored.importCheckpoint(checkpoint.path,checkpoint.sha256,"summary");
      assert.equal(restored.chatSummaryCandidates("summary",scope,"chat-reply:13").previous,summaries.at(-1));
      const resetScope=chatGenerationScope(scope,"reset");
      assert.equal(restored.chatSummaryCandidates("summary",resetScope,"none").previous,"");
      assert.equal(restored.chatRecent("summary",resetScope,8).length,0);
      assert.equal(restored.chatSummaryCandidates("summary",chatRoomKey({...request("x"),agent_id:"lao_li"}),"none").previous,"");
      assert.equal(restored.chatSummaryCandidates("summary",chatRoomKey({...request("x"),chat_room:{id:"group",turn_id:"x",participants:["farmer_ahe","lao_li"]}}),"none").previous,"");
    }finally{restored.close();}
  }finally{server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));memory.close();rmSync(directory,{recursive:true,force:true});}
});

test("failed summaries retry without advancing coverage; resets and cancellation discard in-flight summaries",async()=>{
  const memory=new MemoryRepository(":memory:");memory.syncSession("summary",1);
  const r=request("current"),scope=chatRoomKey(r),events:any[]=[];
  for(let i=0;i<12;i++)memory.appendEvent(r.session_id,scope,message(`old-${i}`,"player",`旧话-${i}`));
  memory.appendEvent(r.session_id,scope,message("chat-user:current","player",r.dialogue_input!));
  let fail=true,current=true;const attempted:string[][]=[];
  const chat:ChatPort={model:"test",respond:async r=>reply(r),summarize:async(_previous,events)=>{attempted.push(events.map(e=>e.event_id));if(fail)throw Error("bad_summary");return "摘要".repeat(800);}};
  try{
    const first=await prepareChatContext(memory,chat,r,scope,e=>events.push(e),()=>current);
    assert.equal(first.summary,"");assert.equal(first.history.length,8);assert.ok(events.some(e=>e.payload?.event==="chat.summary_failed"));
    fail=false;const second=await prepareChatContext(memory,chat,r,scope,e=>events.push(e),()=>current);
    assert.deepEqual(attempted[0],attempted[1]);assert.equal(second.summary.length,CHAT_SUMMARY_CHARS);
    const previous=memory.chatSummaryCandidates(r.session_id,scope,second.history[0].event_id).previous;
    const next=request("next");memory.appendEvent(r.session_id,scope,message("chat-user:next","player",next.dialogue_input!));
    chat.summarize=async()=>{current=false;return "应丢弃";};
    await assert.rejects(prepareChatContext(memory,chat,next,scope,()=>{},()=>current),/chat_context_reset/);
    assert.equal(memory.chatSummaryCandidates(r.session_id,scope,"chat-user:next").previous,previous);
    current=true;const controller=new AbortController();chat.summarize=async()=>{controller.abort();return "应丢弃";};
    await assert.rejects(prepareChatContext(memory,chat,next,scope,()=>{},()=>current,controller.signal));
    assert.equal(memory.chatSummaryCandidates(r.session_id,scope,"chat-user:next").previous,previous);
  }finally{memory.close();}
});

test("local model receives summary only for chat, while extraction HTTP body contains exactly the latest pair",async()=>{
  const inputs:any[]=[],events:any[]=[];
  const upstream=createServer(async(req,res)=>{
    let text="";for await(const part of req)text+=part;const body=JSON.parse(text);inputs.push(body);
    if(body.stream){res.setHeader("content-type","text/event-stream");res.end(`data: ${JSON.stringify({choices:[{delta:{content:"好，我们去南湖散步。"},finish_reason:"stop"}]})}\n\ndata: [DONE]\n\n`);}
    else{res.setHeader("content-type","application/json");res.end(JSON.stringify({choices:[{finish_reason:"stop",message:{content:JSON.stringify(inputs.length===1?{summary:"SUMMARY_ONLY 玩家喜欢种花，旧邀请已取消。"}:{handoffs:[],relationship:null})}}]}));}
  });
  await new Promise<void>(resolve=>upstream.listen(0,"127.0.0.1",resolve));
  try{
    const provider=new LocalChatProvider({baseUrl:`http://127.0.0.1:${(upstream.address() as any).port}/v1`,apiKey:"test",model:"test",temperature:0,maxConcurrency:1,maxOutputTokens:800,timeoutMs:3000});
    const r=request("new");r.dialogue_input="好";
    const summary=await provider.summarize("旧摘要",[message("old","player","OLD_SUMMARY_SOURCE")],e=>events.push(e));
    const history=[message("recent",r.agent_id,"RECENT_HISTORY_ONLY 我们去南湖散步吧。")];
    const parsed=parseDecisionRequest(r);assert.ok(parsed.ok);
    await provider.respond(parsed.value,AgentRegistry.loadDefault().buildContext(r.agent_id,parsed.value,[]),history,[],async()=>({ok:true,items:[],next_cursor:-1}),e=>events.push(e),undefined,summary);
    assert.match(JSON.stringify(inputs[1]),/SUMMARY_ONLY|RECENT_HISTORY_ONLY/);
    assert.doesNotMatch(JSON.stringify(inputs[1]),/OLD_SUMMARY_SOURCE/);
    assert.doesNotMatch(JSON.stringify(inputs[2]),/SUMMARY_ONLY|RECENT_HISTORY_ONLY|OLD_SUMMARY_SOURCE/);
    assert.deepEqual(JSON.parse(inputs[2].messages[1].content).conversation,[{speaker:"player",text:"好",current:true},{speaker:r.agent_id,text:"好，我们去南湖散步。",current:true}]);
    assert.deepEqual(events.filter(e=>e.payload?.event==="provider.route").map(e=>e.payload.phase),["summarize_chat","dialogue","extract_actions"]);
  }finally{upstream.closeAllConnections();await new Promise<void>(resolve=>upstream.close(()=>resolve()));}
});

test("late concurrent summaries cannot replace newer room coverage",async()=>{
  const memory=new MemoryRepository(":memory:");memory.syncSession("summary",1);
  const r=request("a"),scope=chatRoomKey(r);
  for(let i=0;i<12;i++)memory.appendEvent(r.session_id,scope,message(`old-${i}`,"player",`旧话-${i}`));
  memory.appendEvent(r.session_id,scope,message("chat-user:a","player",r.dialogue_input!));
  let release!:(value:string)=>void,started!:()=>void;
  const waiting=new Promise<void>(resolve=>started=resolve);
  const chat:ChatPort={model:"test",respond:async r=>reply(r),summarize:async()=>{started();return new Promise<string>(resolve=>release=resolve);}};
  try{
    const older=prepareChatContext(memory,chat,r,scope,()=>{},()=>true);await waiting;
    const next=request("b");memory.appendEvent(r.session_id,scope,message("chat-user:b","player",next.dialogue_input!));
    const newer=await prepareChatContext(memory,{...chat,summarize:async()=>"较新摘要"},next,scope,()=>{},()=>true);
    release("旧摘要");const late=await older;
    assert.equal(newer.summary,"较新摘要");assert.equal(late.summary,"较新摘要");
    assert.equal(memory.chatSummaryCandidates(r.session_id,scope,newer.history[0].event_id).previous,"较新摘要");
    assert.deepEqual(memory.chatSummaryCandidates(r.session_id,scope,newer.history[0].event_id).events,[]);
  }finally{release?.("cancel");memory.close();}
});

test("messages removed by the character budget are summarized, not silently forgotten",async()=>{
  const memory=new MemoryRepository(":memory:");memory.syncSession("summary",1);
  const r=request("current"),scope=chatRoomKey(r);let summarized:MemoryEvent[]=[];
  memory.appendEvent(r.session_id,scope,message("old-user","player","重要旧约定"));
  memory.appendEvent(r.session_id,scope,message("long-reply",r.agent_id,"长回复".repeat(2500)));
  memory.appendEvent(r.session_id,scope,message("chat-user:current","player",r.dialogue_input!));
  const chat:ChatPort={model:"test",respond:async r=>reply(r),summarize:async(_previous,events)=>{summarized=events;return "保留旧约定";}};
  try{
    const context=await prepareChatContext(memory,chat,r,scope,()=>{},()=>true);
    assert.deepEqual(summarized.map(e=>e.event_id),["old-user","long-reply"]);
    assert.equal(context.history.length,1);assert.equal(context.summary,"保留旧约定");
  }finally{memory.close();}
});
