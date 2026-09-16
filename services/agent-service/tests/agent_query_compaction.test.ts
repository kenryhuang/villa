import test from "node:test";
import assert from "node:assert/strict";
import {compactWorkingMessages, inputEstimate, QUERY_CATALOG, readDefinition, validLoopRead} from "../src/agent_loop.ts";

const header = [{role:"system",content:"game rules"},{role:"user",content:JSON.stringify({resources:{gold:6000,inventory:{flour:24,egg:24}},goal_refs:[{goal_id:"make-bread"}],experience:{recent_events:[{kind:"ResourcesGranted"}]}})}];
function observation(id:string, query:Record<string,unknown>, value:Record<string,unknown>){
  return [{role:"assistant",tool_calls:[{id,function:{name:"query_world",arguments:JSON.stringify(query)}}]},
    {role:"tool",name:"query_world",tool_call_id:id,content:JSON.stringify({ok:true,observation_id:id,observed_game_minute:194680,domain_revision:1270,...value})}];
}
const quoteQuery={domain:"buildings",section:"quote",id:"food_workshop:20:19",recipe_id:"bread",batches:2};
const breadQuote={building_id:"food_workshop:20:19",recipe_id:"bread",batches:2,fee:12,inputs:{flour:4,egg:2},outputs:{bread:4},policy_version:1,
  action:{tool_name:"rent_production",arguments:{building_id:"food_workshop:20:19",recipe_id:"bread",batches:2,max_fee:12}}};
const summary=(messages:Record<string,unknown>[])=>JSON.parse(String(messages[2].content)).continuation_summary;

test("query schema and discovery catalog expose actual sections, batching and quote inputs",()=>{
  const definition:any=readDefinition("query_world",["market","buildings"]);
  assert.ok(definition.function.parameters.properties.section.enum.includes("quote"));
  assert.ok(!definition.function.parameters.properties.section.enum.includes("training"));
  assert.equal(QUERY_CATALOG.buildings.default_section,"list");
  assert.ok(validLoopRead("query_world",{domain:"market",section:"detail",ids:["iron_ore","coal"]},["market"]));
  assert.ok(validLoopRead("query_world",quoteQuery,["buildings"]));
  assert.ok(!validLoopRead("query_world",{...quoteQuery,batches:0},["buildings"]));
  assert.ok(!validLoopRead("query_world",{domain:"market",ids:Array(11).fill("coal")},["market"]));
});

test("real rental failure shape: history is discarded but late fees and complete action survive twice",()=>{
  const detail={building_id:"food_workshop:20:19",production:{service_records:{old:{text:"old delivered jobs".repeat(2000)}},maintenance_state:"ok"},
    rental_fees:[{recipe_id:"bread",fee_per_batch:6,inputs:{flour:2,egg:1},outputs:{bread:2}}],service_policy:{open:true,version:1}};
  const first=compactWorkingMessages([...header,...observation("building",{domain:"buildings",section:"detail",id:detail.building_id},{items:[detail]}),
    ...observation("quote",quoteQuery,{data:breadQuote})],7000);
  assert.deepEqual(first.slice(0,2),header);
  let facts=summary(first).observations;
  assert.deepEqual(facts.find((f:any)=>f.observation_id==="quote").facts.data,breadQuote);
  assert.equal(facts.find((f:any)=>f.observation_id==="building").facts.items[0].rental_fees[0].fee_per_batch,6);
  assert.ok(!JSON.stringify(first).includes("old delivered jobs"));
  const second=compactWorkingMessages([...first,...observation("catalog",{domain:"market",section:"items"},{items:Array(1000).fill({id:"irrelevant",stock:0})})],7000);
  facts=summary(second).observations;
  assert.deepEqual(facts.find((f:any)=>f.observation_id==="quote").facts.data.action.arguments,breadQuote.action.arguments);
  assert.ok(summary(second).missing_details.some((f:any)=>f.observation_id==="catalog"));
  assert.ok(inputEstimate(second)<=7000);
});

test("position prerequisites and failed query diagnostics survive compaction",()=>{
  const position={activity:{reported_region_id:"creek",position:{x:0,z:0}},field_sites:[{id:"creek",arrived:false,distance:34,next_action:"travel",required_items:{bread:1}}]};
  const result=compactWorkingMessages([...header,...observation("self",{domain:"self",section:"activity"},{data:position}),
    ...observation("error",{domain:"market",section:"detail"},{ok:false,error:"id_required",hint:"Supply exact id"}),
    {role:"system",content:"No action was submitted. Correct the rejected batch once."}],5000);
  assert.deepEqual(summary(result).observations.find((f:any)=>f.observation_id==="self").facts.data,position);
  assert.equal(summary(result).observations.find((f:any)=>f.observation_id==="error").facts.error,"id_required");
  assert.ok(summary(result).constraints[0].includes("No action was submitted"));
});

test("a newer quote supersedes old price while different building quotes stay distinct",()=>{
  const first=compactWorkingMessages([...header,...observation("old",quoteQuery,{data:breadQuote})],7000);
  const result=compactWorkingMessages([...first,...observation("new",quoteQuery,{data:{...breadQuote,fee:18}}),
    ...observation("other",{...quoteQuery,id:"other-workshop"},{data:{...breadQuote,building_id:"other-workshop",fee:8}})],7000);
  const facts=summary(result).observations;
  assert.ok(!facts.some((f:any)=>f.observation_id==="old"));
  assert.equal(facts.find((f:any)=>f.observation_id==="new").facts.data.fee,18);
  assert.equal(facts.find((f:any)=>f.observation_id==="other").facts.data.fee,8);
});
