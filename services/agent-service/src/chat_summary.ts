import type {MemoryRepository} from "./memory.ts";
import type {ChatPort} from "./chat_provider.ts";
import type {DecisionRequest} from "./protocol.ts";
import type {ProviderTraceEvent} from "./provider_stream.ts";
import {CHAT_HISTORY_MESSAGES,CHAT_SUMMARY_CHARS,selectChatHistory} from "./chat_context.ts";

// Persist only the prefix that the summarizer actually saw. Raw records remain
// available for retries/checkpoints, but never expand the live chat window.
export async function prepareChatContext(memory:MemoryRepository,provider:ChatPort,r:DecisionRequest,scope:string,emit:(e:ProviderTraceEvent)=>void,isCurrent:()=>boolean,signal?:AbortSignal){
  const history=selectChatHistory(r,memory.chatRecent(r.session_id,scope,CHAT_HISTORY_MESSAGES));
  const first=history[0].event_id;
  const pending=memory.chatSummaryCandidates(r.session_id,scope,first);
  let summary=pending.previous.slice(0,CHAT_SUMMARY_CHARS);
  const events=[];let chars=0;
  for(const event of pending.events){
    const size=String(event.payload.text??"").length;
    if(events.length&&chars+size>12000)break;
    events.push(event);chars+=size;
  }
  if(events.length&&provider.summarize){
    try{
      const next=await provider.summarize(summary,events,emit,signal);
      signal?.throwIfAborted();
      if(memory.closed||!isCurrent())throw new Error("chat_context_reset");
      const current=memory.chatSummaryCandidates(r.session_id,scope,first);
      const sourcesUnchanged=events.every(e=>JSON.stringify(memory.inspectEvent(r.session_id,scope,e.event_id).payload)===JSON.stringify(e.payload));
      if(current.through===pending.through&&current.previous===pending.previous&&sourcesUnchanged){
        if(!next.trim())throw new Error("invalid_chat_summary");
        summary=next.trim().slice(0,CHAT_SUMMARY_CHARS);
        memory.storeHistory(r.session_id,scope,events.map(e=>e.event_id),summary);
        emit({type:"loop",payload:{event:"chat.summary_updated",source_event_ids:events.map(e=>e.event_id),summary,retained_messages:history.length}});
      }else summary=current.previous.slice(0,CHAT_SUMMARY_CHARS);
    }catch(error){
      if(signal?.aborted||memory.closed||!isCurrent())throw error;
      emit({type:"loop",payload:{event:"chat.summary_failed",reason:error instanceof Error?error.message:"unknown_error",retry_next_turn:true}});
    }
  }
  emit({type:"loop",payload:{event:"chat.context_window",retained_event_ids:history.map(e=>e.event_id),retained_messages:history.length,summary_characters:summary.length,extraction_scope:"current_player_and_current_npc_reply"}});
  return {history,summary};
}
