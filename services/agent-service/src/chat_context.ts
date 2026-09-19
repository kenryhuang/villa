import type {AgentContext,Soul} from "./agents.ts";
import type {DecisionRequest} from "./protocol.ts";
import type {MemoryEvent} from "./memory.ts";

export const CHAT_HISTORY_MESSAGES=6;
export const CHAT_HISTORY_CHARS=1800;
export interface ChatActor {id:string;name:string;role?:string;soul?:Soul;}

export function chatMessages(r:DecisionRequest,context:AgentContext,history:MemoryEvent[],actors:ChatActor[]):Record<string,unknown>[] {
  const playerName=r.chat_participants?.find(p=>p.actor_id==="player")?.display_name??"玩家";
  const {agent_id,display_name,active_role,soul}=context.agent;
  const system={
    background:"你与玩家生活在农庄村落。",
    identity:{agent_id,display_name,active_role,soul},player:playerName,
    rules:"以角色身份简洁自然地回应本轮对话，主动推进互动，避免重复旧回复或反复声明人设。只写自己的回应，不代替他人发言。行动约定不等于已经执行。",
  };
  const currentId=`chat-user:${r.chat_room?.turn_id??r.request_id}`;
  const entries=history.slice(-CHAT_HISTORY_MESSAGES);
  if(!entries.some(e=>e.event_id===currentId))entries.push({event_id:currentId,kind:"ChatMessage",game_minute:r.game_minute,payload:{speaker:"player",text:r.dialogue_input??""}});
  const candidates=entries.map(e=>{
    const speaker=String(e.payload.speaker),text=String(e.payload.text??"");
    const name=r.chat_participants?.find(p=>p.actor_id===speaker)?.display_name??actors.find(a=>a.id===speaker)?.name??speaker;
    // Preserve natural assistant text; other group speakers need only a name,
    // never their profiles or world-state snapshots.
    const content=speaker===r.agent_id||speaker==="player"?text:`【${name}】\n${text}`;
    return {event_id:e.event_id,role:speaker===r.agent_id?"assistant":"user",content};
  });
  const current=candidates.findIndex(e=>e.event_id===currentId);
  const retained=new Set<number>([current]);
  let chars=candidates[current].content.length;
  for(let i=candidates.length-1;i>=0;i--){
    if(i===current)continue;
    if(retained.size>=CHAT_HISTORY_MESSAGES || chars+candidates[i].content.length>CHAT_HISTORY_CHARS)break;
    chars+=candidates[i].content.length;retained.add(i);
  }
  const messages=candidates.filter((_,i)=>retained.has(i)).map(({role,content})=>({role,content}));
  return [{role:"system",content:JSON.stringify(system)},...messages];
}
