import test from "node:test";
import assert from "node:assert/strict";
import {AgentRegistry} from "../src/agents.ts";
import {parseDecisionRequest} from "../src/protocol.ts";
import {AgentStreamAssembler} from "../src/provider_stream.ts";
import {runAgentLoop} from "../src/agent_loop.ts";
import {RelationshipDialogue} from "../src/relationship_dialogue.ts";

function fixture(text="确认了啊，你还不知道么，看看你的好感度和状态") {
  const parsed=parseDecisionRequest({protocol_version:3,request_id:"ahe-reminder",session_id:"test",session_epoch:1,
    agent_id:"farmer_ahe",trigger:"dialogue",dialogue_input:text,game_minute:9152,world_revision:579,
    active_role:"farmer",goals:[],allowed_command_tools:["speak","wait","resolve_relationship_dialogue"],resources:{gold:5000},experience_events:[],goal_refs:[]});
  assert.ok(parsed.ok);const request=parsed.value;
  return {request,ctx:AgentRegistry.loadDefault().buildContext(request.agent_id,request,[])};
}
function output(name?:string,args:Record<string,unknown>={},speech="") {
  const a=new AgentStreamAssembler();a.accept({choices:[{index:0,delta:{content:speech,...(name?{tool_calls:[{index:0,id:"call",type:"function",function:{name,arguments:JSON.stringify(args)}}]}:{})},finish_reason:name?"tool_calls":"stop"}]});return a;
}
const discover=()=>output("discover_tools",{domains:["actors"]});
const pairRead=()=>output("query_world",{domain:"actors",section:"relationship",id:"player"});
const live={actor_id:"player",status:"dating",affinity:92,mutual_affinity:92,version:4};

test("ahe trace: live dating state makes a tool-only repeated confirmation a spoken no-op",async()=>{
  const {request,ctx}=fixture();let round=0;const events:any[]=[];
  const steps=[discover,()=>output("query_world",{domain:"actors",section:"relationship_proposals"}),
    ()=>output("query_world",{domain:"actors",section:"relationships"}),
    ()=>output("resolve_relationship_dialogue",{player_quote:request.dialogue_input,decision:"confirm",note:"已有恋人状态，正式记录确认。"})];
  const result=await runAgentLoop(request,ctx,{experience:{},memories:[{summary:"以前没有确认过恋人关系"}],
    read:async(_name,args)=>({ok:true,items:args.section==="relationships"?[live]:[]})},async(messages)=>{
      assert.ok(String(messages[0].content).includes("实时 status/affinity 优先"));return steps[round++]();
    },e=>events.push(e));
  assert.equal(round,4);assert.deepEqual(result.actions,[]);assert.match(result.speech!,/已经是恋人/);
  assert.ok(events.some(e=>e.payload?.event==="dialogue.relationship_already_confirmed"));
  assert.ok(!events.some(e=>e.payload?.event==="loop.validation_failed"));
});

test("memory-based denial must discover and read live state before answering a relationship question",async()=>{
  const {request,ctx}=fixture("既然你是我女朋友，有什么需要尽管提");let round=0,reads=0;
  const steps=[()=>output(undefined,{},"我们还没有确认关系。"),discover,pairRead,()=>output(undefined,{},"我们已经是恋人了，谢谢你关心。")];
  const result=await runAgentLoop(request,ctx,{experience:{},memories:[],read:async()=>{reads++;return {ok:true,data:live};}},async(messages)=>{
    if(round===1)assert.match(String(messages.at(-1)?.content),/relationship_state_required/);
    return steps[round++]();
  },()=>{});
  assert.equal(reads,1);assert.equal(result.speech,"我们已经是恋人了，谢谢你关心。");
});

for(const decision of ["confirm","decline","end"]){
  test(`tool-only new relationship ${decision} keeps the pending action and supplies speech`,async()=>{
    const {request,ctx}=fixture("我们正式成为恋人吧");let round=0;
    const args={player_quote:request.dialogue_input,decision,note:"模型自己的意愿"};
    const steps=[discover,pairRead,()=>output("resolve_relationship_dialogue",args)];
    const result=await runAgentLoop(request,ctx,{experience:{},memories:[],read:async()=>({ok:true,data:{...live,status:decision==="end"?"dating":"none"}})},async()=>steps[round++](),()=>{});
    assert.equal(round,3);assert.equal(result.actions.length,1);assert.deepEqual(result.actions[0].arguments,args);
    assert.ok(result.speech?.trim());assert.doesNotMatch(result.speech!,/已经是恋人|已成功|已完成/);
  });
}

test("failed relation query permits an honest uncertainty reply, not an unchecked action",async()=>{
  const {request,ctx}=fixture();let round=0;
  const steps=[discover,pairRead,()=>output("resolve_relationship_dialogue",{player_quote:request.dialogue_input,decision:"confirm",note:"愿意"}),()=>output(undefined,{},"暂时没查到状态，我不能确定。")];
  const result=await runAgentLoop(request,ctx,{experience:{},memories:[],read:async()=>({ok:false,error:"temporarily_unavailable"})},async()=>steps[round++](),()=>{});
  assert.deepEqual(result.actions,[]);assert.match(result.speech!,/不能确定/);
});

test("relationship evidence ignores other pairs and proposals, and invalidates after a failed refresh",()=>{
  const state=new RelationshipDialogue();
  state.observe("query_world",{domain:"actors",section:"relationship_proposals"},{ok:true,items:[live]});
  state.observe("query_world",{domain:"actors",section:"relationships"},{ok:true,items:[{...live,actor_id:"resident_yun"}]});
  assert.equal(state.attempted,false);assert.equal(state.player,undefined);
  state.observe("query_world",{domain:"actors",section:"relationship",id:"player"},{ok:true,data:live});
  assert.deepEqual(state.player,live);
  state.observe("query_world",{domain:"actors",section:"relationship",id:"player"},{ok:false});
  assert.equal(state.player,undefined);assert.equal(state.attempted,true);
});

test("a new loop cannot reuse relationship observations from the previous loop",async()=>{
  for(let i=0;i<2;i++){
    const {request,ctx}=fixture();let round=0,reads=0;
    const steps=[discover,pairRead,()=>output(undefined,{},"我刚核对了状态。")];
    await runAgentLoop(request,ctx,{experience:{},memories:[],read:async()=>{reads++;return {ok:true,data:live};}},async(messages)=>{
      if(round===0){assert.equal(messages.length,2);assert.ok(!String(messages[1].content).includes('"affinity":92'));}
      return steps[round++]();
    },()=>{});
    assert.equal(reads,1);
  }
});
