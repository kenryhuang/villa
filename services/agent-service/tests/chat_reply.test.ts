import test from "node:test";
import assert from "node:assert/strict";
import {createServer} from "node:http";
import {chatReplyText} from "../src/chat_reply.ts";
import {chatMessages} from "../src/chat_context.ts";
import {LocalChatProvider} from "../src/chat_provider.ts";
import {parseDecisionRequest} from "../src/protocol.ts";
import {AgentRegistry} from "../src/agents.ts";

const prefix="# 角色背景：你与玩家生活在农庄村落。\n\n# 你是：一位热爱园艺的村民。\n\n# 当前场景：农庄门口。\n\n";
const answer="你好，我们去南湖散步吧。\n\n我会带一瓶水。";
function fixture(){
  const parsed=parseDecisionRequest({protocol_version:3,request_id:"echo-test",session_id:"echo",session_epoch:1,agent_id:"farmer_ahe",trigger:"dialogue",dialogue_input:"去南湖散步吗？",game_minute:1,world_revision:1,active_role:"farmer",goals:[],allowed_command_tools:["speak","wait"],resources:{},experience_events:[],goal_refs:[]});
  assert.ok(parsed.ok);const r=parsed.value;return {r,context:AgentRegistry.loadDefault().buildContext(r.agent_id,r,[])};
}

test("recognized setup paragraphs never appear even when split into single-character chunks",()=>{
  for(const preamble of [prefix,"# 你与玩家生活在农庄村落。\n\n","# 角色背景\n\n农庄村落中的园丁。\n\n"]){
    const raw=preamble+answer;let previous="";
    for(let i=1;i<=raw.length;i++){
      const shown=chatReplyText(raw.slice(0,i),false);
      assert.ok(answer.startsWith(shown));assert.ok(shown.startsWith(previous));previous=shown;
    }
    assert.equal(chatReplyText(raw),answer);
  }
  assert.equal(chatReplyText(prefix),"");
});

test("ordinary dialogue and headings are unchanged; known speaker/text envelopes unwrap",()=>{
  for(const text of ["你好","你是我的朋友。","# 南湖散步\n\n我们出发吧。","这是一个例子：\n# 当前场景：农庄。",'{"price": 20}'])assert.equal(chatReplyText(text),text);
  assert.equal(chatReplyText("你好",false),"你好");
  const wrapped=JSON.stringify({speaker:"farmer_ahe",text:JSON.stringify({speaker:"farmer_ahe",text:answer})});
  assert.equal(chatReplyText(wrapped),answer);
  for(let i=1;i<wrapped.length;i++)assert.equal(chatReplyText(wrapped.slice(0,i),false),"");
});

test("old assistant echoes are cleaned when building context, without altering player messages",()=>{
  const {r,context}=fixture();r.dialogue_input=prefix+"玩家自己的文字";
  const messages=chatMessages(r,context,[{event_id:"old",kind:"ChatMessage",game_minute:0,payload:{speaker:r.agent_id,text:prefix+answer}}],[]);
  assert.equal(messages[1].content,answer);assert.equal(messages.at(-1)?.content,r.dialogue_input);
});

test("streamed dialogue and final speech contain only reply body; trace preserves exact raw model output",async()=>{
  const raw=prefix+answer,emitted:any[]=[],inputs:any[]=[];
  const server=createServer(async(req,res)=>{
    let source="";for await(const part of req)source+=part;const body=JSON.parse(source);inputs.push(body);
    if(!body.stream){res.setHeader("content-type","application/json");res.end(JSON.stringify({choices:[{finish_reason:"stop",message:{content:'{"handoffs":[],"relationship":null}'}}]}));return;}
    res.setHeader("content-type","text/event-stream");
    for(const content of raw)res.write(`data: ${JSON.stringify({choices:[{delta:{content},finish_reason:null}]})}\n\n`);
    res.end(`data: ${JSON.stringify({choices:[{delta:{},finish_reason:"stop"}]})}\n\ndata: [DONE]\n\n`);
  });
  await new Promise<void>(resolve=>server.listen(0,"127.0.0.1",resolve));
  try{
    const provider=new LocalChatProvider({baseUrl:`http://127.0.0.1:${(server.address() as any).port}/v1`,apiKey:"test",model:"test",temperature:0,maxConcurrency:1,maxOutputTokens:800,timeoutMs:3000});
    const {r,context}=fixture();const reply=await provider.respond(r,context,[],[],async()=>({ok:true,items:[],next_cursor:-1}),e=>emitted.push(e));
    assert.equal(reply.speech,answer);
    assert.equal(emitted.filter(e=>e.type==="content").map(e=>e.delta).join(""),answer);
    assert.equal(emitted.find(e=>e.type==="output").output.message.content,raw);
    assert.equal(JSON.parse(inputs[1].messages[1].content).conversation[1].text,answer);
  }finally{server.closeAllConnections();await new Promise<void>(resolve=>server.close(()=>resolve()));}
});
