import type {DecisionRequest} from "./protocol.ts";
import type {MemoryRepository,MemoryEvent} from "./memory.ts";

export const actionActor=(id:string)=>`action.v2:${id}`;
const rawKinds=new Set(["dialogue","ActorSpoke","AgentSpoke","DialogueMessage","ChatMessage"]);
const textKeys=new Set(["text","speech","player_text","agent_speech","player_quote","note","reason","description","summary","decision_summary","hud_message","dialogue_input","dialogue_followups","dialogue","messages","chatcontext","chat_context","history","recent_facts","narrative","content","prompt","instructions","dialogue_handoffs","message","quote","dialogue_text","reply","explanation"]);
// Retain machine facts. Human conversation and free prose never cross this boundary.
export function actionFacts(value:unknown):any {
  if(Array.isArray(value))return value.filter(v=>!v || typeof v!=="object" || !rawKinds.has(String(v.kind??v.event_type)) && !["speak","send_message","express_support"].includes(String(v.tool_name))).map(actionFacts);
  if(!value || typeof value!=="object")return value;
  return Object.fromEntries(Object.entries(value).filter(([k])=>!textKeys.has(k)).map(([k,v])=>[k,actionFacts(v)]));
}
export function appendIsolatedEvent(memory:MemoryRepository,session:string,actor:string,event:MemoryEvent):void {
  if(rawKinds.has(event.kind)) {
    memory.appendEvent(session,`chat.legacy:${actor}`,event);return;
  }
  if(event.kind==="ActionGoalPlan"||event.kind==="ChatActionAgreed")return;
  const payload=actionFacts(event.payload);
  delete payload.handoff_version;delete payload.handoffs;
  memory.appendEvent(session,actionActor(actor),{...event,payload});
}
export function prepareActionRequest(memory:MemoryRepository,request:DecisionRequest):DecisionRequest {
  const clean=structuredClone(request);
  delete clean.dialogue_input;delete clean.chat_room;delete clean.chat_participants;
  // Only a handoff already archived by this service's extraction path is trusted.
  clean.dialogue_followups=(request.dialogue_followups??[]).flatMap(entry=>{
    const stored=memory.inspectEvent(request.session_id,actionActor(request.agent_id),String(entry.event_id));
    const payload=stored.payload as Record<string,unknown>|undefined;
    return stored.kind==="ChatActionAgreed" && payload?.handoff_version===1?[{event_id:entry.event_id,kind:"dialogue",game_minute:stored.game_minute,payload}]:[];
  });
  clean.goal_refs=(request.goal_refs??[]).map(g=>{
    const plan=memory.inspectEvent(request.session_id,actionActor(request.agent_id),`action-goal:${g.goal_id}:${g.version}`);
    const trusted=plan.kind==="ActionGoalPlan"?(plan.payload as any)?.description:undefined;
    return {...actionFacts(g),description:typeof trusted==="string"?trusted:`执行已登记目标 ${g.goal_id}，先核实完成条件 ${JSON.stringify(actionFacts(g.success_condition??{}))}`};
  });
  clean.experience_events=actionFacts((request.experience_events??[]).filter(e=>!rawKinds.has(String(e.kind??e.event_type))));
  for(const field of ["actor_context","public_world_state","global_public_events","known_actors","own_event_delta","market_summary","market_view","interaction_view","agreement_view"] as const)
    (clean as any)[field]=actionFacts(clean[field]);
  return clean;
}
