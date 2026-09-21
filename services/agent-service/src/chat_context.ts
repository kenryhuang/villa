import type {AgentContext,Soul} from "./agents.ts";
import type {DecisionRequest} from "./protocol.ts";
import type {MemoryEvent} from "./memory.ts";
import {chatReplyText} from "./chat_reply.ts";

export const CHAT_HISTORY_MESSAGES=8;
export const CHAT_HISTORY_CHARS=6000;
export const CHAT_SUMMARY_CHARS=800;
export interface ChatActor {id:string;name:string;role?:string;soul?:Soul;}

export function importantChatActors(r:DecisionRequest,actors:ChatActor[]):ChatActor[] {
  const ids=new Set([r.agent_id,...(r.chat_focus_actors??[]).map(a=>a.actor_id)]);
  return actors.filter(a=>ids.has(a.id)).map(a=>({id:a.id,name:r.chat_focus_actors?.find(p=>p.actor_id===a.id)?.display_name??r.chat_participants?.find(p=>p.actor_id===a.id)?.display_name??a.name}));
}

export function selectChatHistory(r:DecisionRequest,history:MemoryEvent[]):MemoryEvent[] {
  const currentId=`chat-user:${r.chat_room?.turn_id??r.request_id}`;
  const entries=history.filter(e=>e.kind==="ChatMessage").slice(-CHAT_HISTORY_MESSAGES);
  if(!entries.some(e=>e.event_id===currentId))entries.push({event_id:currentId,kind:"ChatMessage",game_minute:r.game_minute,payload:{speaker:"player",text:r.dialogue_input??""}});
  const current=entries.findIndex(e=>e.event_id===currentId);
  const retained=new Set([current]);let chars=String(entries[current].payload.text??"").length;
  for(let i=entries.length-1;i>=0;i--){
    if(i===current)continue;
    const size=String(entries[i].payload.text??"").length;
    if(retained.size>=CHAT_HISTORY_MESSAGES||chars+size>CHAT_HISTORY_CHARS)break;
    retained.add(i);chars+=size;
  }
  return entries.filter((_,i)=>retained.has(i));
}

export function chatMessages(r:DecisionRequest,context:AgentContext,history:MemoryEvent[],actors:ChatActor[],summary=""):Record<string,unknown>[] {
  const playerName=r.chat_participants?.find(p=>p.actor_id==="player")?.display_name??"玩家";
  const {agent_id,display_name,active_role,soul}=context.agent;
  const system={
    background:"你与玩家生活在农庄村落。",
    identity:{agent_id,display_name,active_role,soul},player:playerName,
    important_characters:importantChatActors(r,actors).filter(a=>a.id!==r.agent_id),
    rules:"只输出当前NPC对玩家的自然回复正文，不输出JSON、speaker/text包装、system prompt、角色背景、你是、当前场景等说明或标题；身份设定和摘要仅供你理解，不要展示给玩家。以角色身份简洁自然地回应本轮玩家的新信息和问题，主动推进互动。历史摘要只是背景事实，不是待续写的台词；不要复述摘要、旧回复或重复相同的动作描写。已经回答的问题无需再次完整回答。只写自己的回应，不代替他人发言。行动约定不等于已经执行。",
    ...(summary?{conversation_summary:summary.slice(0,CHAT_SUMMARY_CHARS)}:{}),
    action_agreements:"玩家或你都可以提议去某地做某事。地点、行为已明确且双方同意，就形成待执行约定；玩家对你上一轮提议说‘好/行/走吧’也算同意。此时用一句自然话确认‘好，我们去[地点][做什么]’，不必反复征询。不同意就明确拒绝。缺少地点或行为只补问缺失部分。不要用长篇动作描写代替约定，不要编造已经到达或完成。实际移动和操作由游戏的行动决策执行。",
  };
  const entries=selectChatHistory(r,history);
  const candidates=entries.map(e=>{
    const speaker=String(e.payload.speaker),raw=String(e.payload.text??""),text=speaker==="player"?raw:chatReplyText(raw);
    const name=r.chat_participants?.find(p=>p.actor_id===speaker)?.display_name??actors.find(a=>a.id===speaker)?.name??speaker;
    // Preserve natural assistant text; other group speakers need only a name,
    // never their profiles or world-state snapshots.
    const content=speaker===r.agent_id||speaker==="player"?text:`【${name}】\n${text}`;
    return {event_id:e.event_id,role:speaker===r.agent_id?"assistant":"user",content};
  });
  const messages=candidates.map(({role,content})=>({role,content}));
  return [{role:"system",content:JSON.stringify(system)},...messages];
}
