import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
import {AgentRegistry} from "../src/agents.ts";
import {AgentStreamAssembler} from "../src/provider_stream.ts";
import {runAgentLoop,DEFAULT_LOOP,validLoopRead} from "../src/agent_loop.ts";
import type {DecisionRequest} from "../src/protocol.ts";

const fixture=JSON.parse(readFileSync(new URL("./fixtures/loop-discovery-errors.json",import.meta.url),"utf8"));
const registry=AgentRegistry.loadDefault();
function context(actor="farmer_ahe"){
  const profile=registry.get(actor)!;
  const request={protocol_version:3,request_id:"discovery-regression",session_id:"fixture",session_epoch:1,agent_id:actor,
    trigger:"schedule",game_minute:0,world_revision:1,active_role:profile.role_id,goals:profile.goals,
    allowed_command_tools:[...profile.tools,"adopt_short_term_goal","revise_short_term_goal","abandon_short_term_goal","submit_project","start_leisure"],
    allowed_read_tools:[],actor_context:{},public_world_state:{},global_public_events:[],known_actors:[],own_event_delta:[],market_summary:{},market_view:{},interaction_view:{},agreement_view:{},
    resources:{gold:30,inventory:{grain_seed:2},resource_revision:1},experience_events:[],goal_refs:[]} as unknown as DecisionRequest;
  return {request,ctx:registry.buildContext(actor,request,[])};
}
function output(calls:{id:string;function:{name:string;arguments:string}}[]=[]){
  const a=new AgentStreamAssembler();
  a.accept({id:"fixture-reply",choices:[{index:0,delta:{content:"",tool_calls:calls.map((c,index)=>({...c,index,type:"function"}))},finish_reason:calls.length?"tool_calls":"stop"}]});
  return a;
}
const call=(name:string,args:Record<string,unknown>={})=>({id:`call-${name}`,function:{name,arguments:JSON.stringify(args)}});

test("named map discovery resolves query_map through the live world broker then moves",async()=>{
  const {request}=context();request.allowed_command_tools.push("move");
  const ctx=registry.buildContext(request.agent_id,request,[]);let round=0;
  const reads:unknown[]=[];
  const intent=await runAgentLoop(request,ctx,{experience:{},memories:[],read:async(name,args)=>{
    reads.push([name,args]);return {ok:true,items:[{name:"南湖",navigation_action:{tool_name:"move",arguments:{x:-5.5,z:84.5}}}]};
  }},async(messages,tools)=>{
    const names=tools.map(t=>(t.function as any).name);
    if(round++===0){assert.ok(!names.includes("query_map"));return output([call("discover_tools",{domains:["map"]})]);}
    assert.ok(names.includes("query_map"));
    if(round===2)return output([call("query_map",{query:"南湖"})]);
    const place=JSON.parse(String(messages.at(-1)!.content)).items[0];
    return output([call(place.navigation_action.tool_name,place.navigation_action.arguments)]);
  },()=>{});
  assert.deepEqual(reads,[["query_world",{query:"南湖",domain:"map",section:"regions"}]]);
  assert.equal(intent.actions[0].tool_name,"move");
  assert.ok(!validLoopRead("query_map",{query:"南湖"},["self"]));
  assert.ok(!validLoopRead("query_map",{query:"南湖",domain:"actors"},["map"]));
});

test("dialogue discovers relationship recording with the player's exact utterance",async()=>{
  const {request}=context("xiao_hua");request.trigger="dialogue";
  request.allowed_command_tools.push("resolve_relationship_dialogue");
  const ctx=registry.buildContext(request.agent_id,request,[]);let round=0;
  const intent=await runAgentLoop(request,ctx,{experience:{},memories:[],read:async()=>({ok:true,data:{actor_id:"player",status:"none"}})},async(_messages,tools)=>{
    if(round++===0)return output([call("discover_tools",{domains:["actors"],actions:["resolve_relationship_dialogue"]})]);
    if(round===2)return output([call("query_world",{domain:"actors",section:"relationship",id:"player"})]);
    assert.ok(tools.some(t=>(t.function as any).name==="resolve_relationship_dialogue"));
    const a=output([call("resolve_relationship_dialogue",{player_quote:"我们正式成为恋人吧。",decision:"confirm",note:"我也愿意。"})]);
    a.accept({choices:[{index:0,delta:{content:"我也愿意认真和你交往。"}}]});
    return a;
  },()=>{});
  assert.equal(intent.actions[0].tool_name,"resolve_relationship_dialogue");
});

for(const example of fixture.cases){
  test(`real trace ${example.request_id}: discovery returns selection feedback and continues`,async()=>{
    const {request,ctx}=context(example.agent_id);let rounds=0;const observed:string[]=[];
    const intent=await runAgentLoop(request,ctx,{experience:{},memories:[],read:async(name)=>{observed.push(name);return {ok:true};}},async(messages,tools)=>{
      if(rounds++===0){
        const discovery:any=tools.find(t=>(t.function as any).name==="discover_tools");
        assert.equal(discovery.function.parameters.properties.actions,undefined,"first discovery never asks for names not yet provided");
        return output(example.tool_calls);
      }
      if(rounds===2){
        const result=messages.filter(m=>m.role==="tool"&&m.name==="discover_tools").map(m=>JSON.parse(String(m.content)))[0];
        assert.equal(result.error,"invalid_action_selection");
        assert.ok(result.rejected_actions.length);assert.deepEqual(result.enabled_actions,[]);
        assert.ok(result.available_actions.every((n:string)=>ctx.allowed_command_tools.includes(n)));
        const discovery:any=tools.find(t=>(t.function as any).name==="discover_tools");
        assert.deepEqual(discovery.function.parameters.properties.actions.items.enum,result.available_actions);
        const domain=JSON.parse(example.tool_calls[0].function.arguments).domains[0];
        return output([call("query_world",{domain,section:"overview"})]);
      }
      assert.ok(messages.some(m=>m.role==="tool"&&m.name==="query_world"));
      return output();
    },()=>{});
    assert.equal(rounds,3);assert.deepEqual(intent.actions,[]);
    assert.ok(observed.includes("query_world"));
    assert.ok(observed.every(n=>["query_world","inspect_self_resources"].includes(n)),"discovery never executes invented commands");
  });
}

test("separate domain discoveries retain already enabled actions",async()=>{
  const {request,ctx}=context();let round=0;
  await runAgentLoop(request,ctx,{experience:{},memories:[],read:async()=>({})},async(messages,tools)=>{
    if(round++===0)return output([call("discover_tools",{domains:["farm"]})]);
    if(round===2)return output([call("discover_tools",{domains:["goals"]})]);
    const names=tools.map(t=>(t.function as any).name);
    assert.ok(names.includes("plant"));assert.ok(names.includes("adopt_short_term_goal"));
    const catalog=JSON.parse(String(messages[1].content)).turn.query_catalog;
    assert.deepEqual(catalog.farm.sections,["plots","crops"]);assert.deepEqual(catalog.goals.sections,["list"]);
    return output();
  },()=>{});
});

test("3D merchant discovers a physical build with coordinates, without legacy virtual buildings",async()=>{
  const {request}=context("tiejiang_zhang");request.allowed_command_tools.push("build");
  const ctx=registry.buildContext(request.agent_id,request,[]);let round=0;
  const intent=await runAgentLoop(request,ctx,{experience:{},memories:[],read:async()=>({})},async(messages,tools)=>{
    if(round++===0)return output([call("discover_tools",{domains:["buildings"]})]);
    const catalog=JSON.parse(String(messages.at(-1)!.content));
    assert.ok(catalog.available_actions.includes("build"));
    const definition:any=tools.find(t=>(t.function as any).name==="build");
    assert.deepEqual(definition.function.parameters.required,["building_type","gx","gz"]);
    assert.deepEqual(definition.function.parameters.properties.building_type.enum,["windmill","food_workshop"]);
    assert.equal(definition.function.parameters.properties.building_id,undefined);
    return output([call("build",{building_type:"windmill",gx:28,gz:38})]);
  },()=>{});
  assert.equal(intent.actions[0].tool_name,"build");assert.equal(intent.actions[0].arguments.gx,28);
});

test("authorized action omitted from menu is recoverable and requires explicit discovery",async()=>{
  const {request,ctx}=context();let round=0;const traces:any[]=[];
  const intent=await runAgentLoop(request,ctx,{experience:{},memories:[],read:async()=>({})},async()=>{
    if(round++===0)return output([call("plant",{plot:0,seed_item_id:"grain_seed"})]);
    if(round===2)return output([call("discover_tools",{domains:["farm"],actions:["plant"]})]);
    return output([call("plant",{plot:0,seed_item_id:"grain_seed"})]);
  },e=>traces.push(e));
  assert.equal(intent.actions.length,1);assert.equal(round,3);
  assert.ok(traces.some(t=>t.type==="loop"&&t.payload.event==="loop.validation_failed"&&t.payload.error.startsWith("action_tool_not_enabled")));
});

test("knowledge discovery alone supports a survey including travel",async()=>{
  const {request,ctx}=context("xuezhe_lin");let round=0;
  const intent=await runAgentLoop(request,ctx,{experience:{},memories:[],read:async()=>({})},async(_messages,tools)=>{
    if(round++===0)return output([call("discover_tools",{domains:["knowledge"],actions:["survey"]})]);
    const survey:any=tools.find(t=>(t.function as any).name==="survey");
    assert.match(survey.function.description,/includes walking/);
    assert.match(survey.function.description,/At actual arrival/);
    assert.ok(!tools.some(t=>(t.function as any).name==="travel"));
    return output([call("survey",{region_id:"creek"})]);
  },()=>{});
  assert.deepEqual(intent.actions.map(a=>a.tool_name),["survey"]);
});

for(const activity of ["eat","drink","rest","sleep","visit"]){
  test(`self discovery exposes real ${activity} action for non-farmers too`,async()=>{
    const {request,ctx}=context("lao_li");let round=0;
    const args={activity,partner_id:activity==="drink"?"village_inn":activity==="visit"?"farmer_ahe":"lao_li"};
    const intent=await runAgentLoop(request,ctx,{experience:{},memories:[],read:async()=>({})},async(_messages,tools)=>{
      if(round++===0)return output([call("discover_tools",{domains:["self"],actions:["start_leisure"]})]);
      const leisure:any=tools.find(t=>(t.function as any).name==="start_leisure");
      assert.ok(leisure.function.parameters.properties.activity.enum.includes(activity));
      return output([call("start_leisure",args)]);
    },()=>{});
    assert.deepEqual(intent.actions[0].arguments,args);
  });
}

test("public catalog lookup cannot authorize private actions",async()=>{
  const {request,ctx}=context("village_public");let round=0;
  await assert.rejects(runAgentLoop(request,ctx,{experience:{},memories:[],read:async()=>{throw new Error("unexpected world read");}},async(messages)=>{
    if(round++===0)return output([call("discover_tools",{domains:["public"],actions:["buy"]})]);
    const catalog=JSON.parse(String(messages.at(-1)!.content));
    assert.equal(catalog.error,"invalid_action_selection");assert.ok(!catalog.available_actions.includes("buy"));
    return output([call("buy",{item_id:"grain",quantity:1,max_total_price:10})]);
  },()=>{}),/provider_unauthorized_tool/);
  assert.equal(round,2);
});

test("read budgets are visible and an oversized batch consumes no remaining calls",async()=>{
  const {request,ctx}=context();let round=0,reads=0;
  await runAgentLoop(request,ctx,{experience:{},memories:[],read:async()=>{reads++;return {ok:true};}},async(messages)=>{
    const budget=JSON.parse(String(messages[1].content)).turn.budget;
    if(round++===0){assert.equal(budget.remaining_read_calls,3);return output([call("discover_tools",{domains:["farm"]})]);}
    assert.equal(budget.remaining_read_calls,2);assert.equal(budget.max_read_calls_per_round,2);
    if(round===2)return output([call("inspect_self_resources"),call("query_world",{domain:"farm"}),call("recall_memory",{query:"grain"})]);
    assert.ok(String(messages.at(-1)!.content).includes("Remaining reads: 2"));return output();
  },()=>{},undefined,{...DEFAULT_LOOP,max_read_calls:3});
  assert.equal(reads,0);assert.equal(round,3);
});
