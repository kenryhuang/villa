import {createHash} from "node:crypto";
import type {ProviderConfig} from "./config.ts";
import type {DecisionRequest,ActionIntent} from "./protocol.ts";
import type {AgentContext} from "./agents.ts";
import type {MemoryEvent} from "./memory.ts";
import type {ReadPort} from "./agent_loop.ts";
import {AgentStreamAssembler,decodeProviderSse,type ProviderTraceEvent} from "./provider_stream.ts";
import {chatMessages,type ChatActor} from "./chat_context.ts";
import {RelationshipDialogue} from "./relationship_dialogue.ts";
import {ProviderConcurrencyGate} from "./provider_concurrency_gate.ts";

export interface ChatCatalog {actors:string[];places:string[];items:string[];}
export const CHAT_KINDS=["visit","date","companionship","trade","plant","harvest","build","rest"] as const;
export function chatRoomKey(r:DecisionRequest):string {
  const members=[...(r.chat_room?.participants??[r.agent_id])].sort();
  return `chat.room:${createHash("sha256").update(JSON.stringify(r.chat_room?["group",r.chat_room.id]:["private",members])).digest("hex")}`;
}
export function validateHandoffs(value:unknown,catalog:ChatCatalog,reply:string):Record<string,unknown>[] {
  if(!Array.isArray(value)||value.length>3)return [];
  const accepted:Record<string,unknown>[]=[];
  for(const raw of value){
    if(!raw||typeof raw!=="object")continue;
    const r={target_actor_id:"",place_id:"",item_id:"",quantity:0,gold:0,delay_minutes:0,...raw} as Record<string,unknown>;
    if(Object.keys(r).some(k=>!["kind","status","target_actor_id","place_id","item_id","quantity","gold","delay_minutes","confidence","reply_evidence","trade_side","building_type","plot"].includes(k)))continue;
    r.trade_side ??= "none";r.building_type ??= "";r.plot ??= -1;
    if(!["none","buy","sell"].includes(String(r.trade_side)) || !["","well","waterwheel","greenhouse","beehive","windmill","chicken_coop","food_workshop"].includes(String(r.building_type)) || !Number.isSafeInteger(r.plot) || Number(r.plot)<-1 || Number(r.plot)>999)continue;
    if(!CHAT_KINDS.includes(r.kind as any)||!["agreed","cancelled"].includes(String(r.status))||typeof r.confidence!=="number"||!Number.isFinite(r.confidence)||r.confidence<0.9||r.confidence>1)continue;
    if(typeof r.reply_evidence!=="string"||r.reply_evidence.length<2||!reply.replace(/\s+/g,"").includes(r.reply_evidence.replace(/\s+/g,"")))continue;
    if(typeof r.target_actor_id!=="string"||r.target_actor_id!==""&&!catalog.actors.includes(r.target_actor_id))continue;
    if(typeof r.place_id!=="string"||r.place_id!==""&&!catalog.places.includes(r.place_id))continue;
    if(typeof r.item_id!=="string"||r.item_id!==""&&!catalog.items.includes(r.item_id))continue;
    if(!Number.isSafeInteger(r.quantity)||Number(r.quantity)<0||Number(r.quantity)>1000||!Number.isSafeInteger(r.gold)||Number(r.gold)<0||Number(r.gold)>1000000
      ||!Number.isSafeInteger(r.delay_minutes)||Number(r.delay_minutes)<0||Number(r.delay_minutes)>10080)continue;
    if(["visit","date","companionship","trade"].includes(String(r.kind))&&!r.target_actor_id)continue;
    if(["trade","plant"].includes(String(r.kind))&&(!r.item_id||!r.quantity))continue;
    if(r.kind==="trade" && r.trade_side==="none" || r.kind==="build"&&!r.building_type)continue;
    // No quotations, explanations, notes or model-created prose leave the chat channel.
    const handoff=Object.fromEntries(["kind","status","target_actor_id","place_id","item_id","quantity","gold","delay_minutes","trade_side","building_type","plot"].map(k=>[k,r[k]]));
    if(!accepted.some(x=>JSON.stringify(x)===JSON.stringify(handoff)))accepted.push(handoff);
  }
  return accepted;
}
export function parseExtraction(text:string):Record<string,unknown> {
  const fenced=text.trim().match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  const value=JSON.parse(fenced?fenced[1]:text);
  if(!value || typeof value!=="object" || Array.isArray(value) || Object.keys(value).some(k=>!["handoffs","relationship"].includes(k)) || !Array.isArray(value.handoffs) || value.handoffs.length>3)throw new Error("invalid_chat_extraction");
  return value;
}
export function relationshipAction(r:DecisionRequest,context:AgentContext,value:unknown,reply:string,observation:Record<string,unknown>):ActionIntent["actions"] {
  if(!value || typeof value!=="object" || r.chat_room || !context.allowed_command_tools.includes("resolve_relationship_dialogue"))return [];
  const v=value as Record<string,unknown>;
  if(Object.keys(v).some(k=>!["decision","reply_evidence","player_evidence"].includes(k)) || !["confirm","decline","end"].includes(String(v.decision)))return [];
  if(typeof v.reply_evidence!=="string"||v.reply_evidence.length<2||!reply.includes(v.reply_evidence)||typeof v.player_evidence!=="string"||v.player_evidence.length<2||!r.dialogue_input?.includes(v.player_evidence))return [];
  const live=new RelationshipDialogue();live.observe("query_world",{domain:"actors",section:"relationship",id:"player"},observation);
  if(!live.player || (v.decision==="confirm" && live.player.status==="dating") || (v.decision==="end" && live.player.status!=="dating"))return [];
  // Exact current player quotation is used only by the game's existing consent validator,
  // never passed to the action model or its memories.
  return [{action_id:`chat-relation:${r.request_id}`,idempotency_key:`${r.session_id}:chat-relation:${r.request_id}`,tool_name:"resolve_relationship_dialogue",tool_version:1,
    arguments:{decision:v.decision,player_quote:r.dialogue_input,note:"当前对话的明确关系意愿"}}];
}
export function renderHandoffs(handoffs:Record<string,unknown>[]):string {
  return handoffs.map(h=>JSON.stringify(h)).join("\n");
}

export interface ChatPort {
  readonly model: string;
  respond(request:DecisionRequest,context:AgentContext,history:MemoryEvent[],actors:ChatActor[],read:ReadPort,emit:(e:ProviderTraceEvent)=>void,signal?:AbortSignal):Promise<ActionIntent>;
}
export class LocalChatProvider implements ChatPort {
  readonly model:string;
  readonly #config:ProviderConfig;
  readonly #gate:ProviderConcurrencyGate;
  constructor(config:ProviderConfig){this.#config=config;this.model=config.model;this.#gate=new ProviderConcurrencyGate(config.maxConcurrency);}
  async #complete(messages:Record<string,unknown>[],phase:string,emit:(e:ProviderTraceEvent)=>void,signal?:AbortSignal,json=false):Promise<string>{
    const started=performance.now();
    let dispatched:number|undefined,headers:number|undefined,firstToken:number|undefined,lastToken:number|undefined;
    let chunks=0,characters=0,maxGap=0,status="error";
    const elapsed=(since:number)=>Math.round(performance.now()-since);
    const timeout=AbortSignal.timeout(this.#config.timeoutMs);
    const combined=signal?AbortSignal.any([signal,timeout]):timeout;
    try {
      const result=await this.#gate.run(combined,async gateSignal=>{
        dispatched=performance.now();
        emit({type:"loop",payload:{event:"provider.route",channel:"chat",model:this.model,phase,queue_wait_ms:Math.round(dispatched-started)}});
        const body={model:this.model,messages,stream:!json,max_tokens:json?1600:this.#config.maxOutputTokens,temperature:json?0:this.#config.temperature,...(json?{response_format:{type:"json_object"}}:{})};
        emit({type:"input",body});
        const response=await fetch(`${this.#config.baseUrl}/chat/completions`,{method:"POST",headers:{"content-type":"application/json",authorization:`Bearer ${this.#config.apiKey}`},body:JSON.stringify(body),signal:gateSignal});
        headers=performance.now();
        if(!response.ok)throw new Error(`chat_provider_http_${response.status}`);
        if(!json){
          if(!response.body || !response.headers.get("content-type")?.includes("text/event-stream"))throw new Error("chat_provider_stream_required");
          const assembler=new AgentStreamAssembler();
          let visible="",first=true;
          for await(const chunk of decodeProviderSse(response.body)){
            gateSignal.throwIfAborted();
            for(const delta of assembler.accept(chunk)){
              if(delta.type==="tool_call")throw new Error("chat_provider_unexpected_tool_call");
              if(delta.type!=="content")continue;
              if(delta.delta){
                const now=performance.now();
                if(lastToken!==undefined){
                  const gap=Math.round(now-lastToken);maxGap=Math.max(maxGap,gap);
                  if(gap>=1000)emit({type:"loop",payload:{event:"chat.slow_chunk",channel:"chat",model:this.model,phase,gap_ms:gap,elapsed_ms:elapsed(started)}});
                }
                firstToken??=now;lastToken=now;chunks++;characters+=delta.delta.length;
              }
              // Respect the executor's 500-character speech envelope without splitting
              // surrogate pairs. Final speech is the same text the UI received.
              const next=assembler.rawMessage().content.slice(0,500).replace(/[\uD800-\uDBFF]$/,"");
              const addition=next.slice(visible.length);
              visible=next;
              if(addition){
                if(first){emit({type:"loop",payload:{event:"chat.first_token",channel:"chat",model:this.model,phase,first_token_ms:elapsed(dispatched!),total_wait_ms:elapsed(started)}});first=false;}
                emit({type:"content",delta:addition});
              }
            }
          }
          const output=assembler.rawOutput();
          emit({type:"output",output});
          if(!visible.trim() || output.finish_reason!=="stop")throw new Error("chat_provider_incomplete_reply");
          return visible.trim();
        }
        const data=await response.json() as any;
        const text=String(data.choices?.[0]?.message?.content??"").trim();
        if(!text || data.choices?.[0]?.finish_reason==="length")throw new Error("chat_provider_incomplete_reply");
        emit({type:"output",output:{id:String(data.id??"chat"),finish_reason:data.choices?.[0]?.finish_reason??"stop",message:{content:text,reasoning_content:"",tool_calls:[]},usage:data.usage}});
        return text;
      },"dialogue");
      status="completed";
      return result;
    } finally {
      emit({type:"loop",payload:{event:"chat.timing",channel:"chat",model:this.model,phase,
        status:combined.aborted?"cancelled":status,elapsed_ms:elapsed(started),
        queue_wait_ms:Math.round((dispatched??performance.now())-started),
        headers_ms:headers===undefined?null:Math.round(headers-dispatched!),
        first_token_ms:firstToken===undefined?null:Math.round(firstToken-dispatched!),
        content_chunks:chunks,content_characters:characters,max_chunk_gap_ms:maxGap}});
    }
  }
  async respond(r:DecisionRequest,context:AgentContext,history:MemoryEvent[],actors:ChatActor[],read:ReadPort,emit:(e:ProviderTraceEvent)=>void,signal?:AbortSignal):Promise<ActionIntent>{
    const messages=chatMessages(r,context,history,actors);
    const reply=await this.#complete(messages,"dialogue",emit,signal);
    let handoffs:Record<string,unknown>[]=[];
    let actions:ActionIntent["actions"]=[], extractionFailed=false;
    try{
      // The second pass sees only this room and this speaker's reply; no main-model call.
      const places:{id:string;name?:string;aliases?:unknown}[]=[];
      for(let cursor=0;cursor<30;cursor+=10){
        const map=await read("query_world",{domain:"map",section:"regions",cursor,limit:10},signal);
        for(const row of (Array.isArray(map.items)?map.items:[]))if(typeof row.id==="string")places.push({id:row.id,name:row.name,aliases:row.aliases});
        if(!map.ok||Number(map.next_cursor??-1)<0)break;
      }
      const items:{id:string;name?:string}[]=Object.keys((r.resources?.inventory??{}) as object).map(id=>({id}));
      if(/交易|买|卖|种子|种植|购买|出售|\b(?:buy|sell|trade|plant|seed)\b/i.test((r.dialogue_input??"")+reply)){
        for(let cursor=0;cursor<100;cursor+=10){
          const market=await read("query_world",{domain:"market",section:"items",cursor,limit:10},signal);
          for(const row of Array.isArray(market.items)?market.items:[]){
            const id=row.id??row.item_id;if(typeof id==="string"&&!items.some(i=>i.id===id))items.push({id,name:row.name??row.display_name});
          }
          if(!market.ok||Number(market.next_cursor??-1)<0)break;
        }
      }
      const catalog:ChatCatalog={actors:["player",...actors.map(a=>a.id)],places:places.map(p=>p.id),items:items.map(i=>i.id)};
      const instructions={task:"从最后这名角色的回复中抽取其明确同意的新游戏行动或明确取消的旧行动，最多3条。只返回JSON对象 {handoffs:[],relationship:null}，不要Markdown代码块。每条handoff必须包含schema全部字段，不适用使用空字符串或0。闲聊、情绪、亲昵称呼、关系身份、拒绝、假设、愿望、玩家单方面命令、别人同意、已完成旧行动均返回空数组。约会只表示双方自愿的普通游戏社交活动。不要抽取对话内容或身体描写。模糊意图不猜测。没有新约定就不重复以前的约定。撤销仅在角色明确同意取消时 status=cancelled。只抽当前发言者承诺，不能为群里其他角色承诺。缺少交易物品或数量则不创建交易行动。",
        relationship_schema:"仅私聊：玩家本轮明确请求成为恋人或分手，且最后回复明确表态时，可填 {decision:confirm/decline/end,player_evidence:玩家本轮连续原文证据,reply_evidence:最后回复连续原文证据}。日常称呼、询问旧状态、普通约会均为null。群聊为null。不能代替玩家同意。",
        schema:{kind:CHAT_KINDS,status:["agreed","cancelled"],target_actor_id:"catalog actors之一，无对象为空字符串",place_id:"catalog places之一，未约定为空字符串",item_id:"catalog items之一，不适用为空字符串",quantity:"整数0..1000",gold:"整数0..1000000，未议价为0，不代表免费，执行前核实",delay_minutes:"整数0..10080，未约定为0",trade_side:"交易从当前NPC视角buy或sell；非交易none",building_type:"建筑ID：well/waterwheel/greenhouse/beehive/windmill/chicken_coop/food_workshop；非建造空字符串",plot:"明确地块编号，未知为-1",confidence:"数字0.9..1",reply_evidence:"最后回复中连续的原文证据，必须明确同意或取消"},
        examples:[{reply:"也许以后有空可以去南湖",handoffs:[]},{reply:"我不去，你自己去吧",handoffs:[]},{reply:"好，我会和你去南湖散步",kind:"visit",status:"agreed"}],catalog:{actors:[{id:"player",name:"玩家"},...actors.map(a=>({id:a.id,name:a.name}))],places,items}};
      const raw=await this.#complete([{role:"system",content:JSON.stringify(instructions)},{role:"user",content:JSON.stringify({speaker:r.agent_id,recent_chat:messages.slice(1).slice(-8),reply})}],"extract_actions",emit,signal,true);
      const extracted=parseExtraction(raw);
      handoffs=validateHandoffs(extracted.handoffs,catalog,reply);
      if(extracted.relationship && !r.chat_room){
        const relationship=await read("query_world",{domain:"actors",section:"relationship",id:"player"},signal);
        actions=relationshipAction(r,context,extracted.relationship,reply,relationship);
      }
      extractionFailed=(extracted.handoffs as unknown[]).length>handoffs.length;
      if(extractionFailed)emit({type:"loop",payload:{event:"chat.extraction_failed",code:"invalid_handoff_fields",actions_submitted:0}});
      emit({type:"loop",payload:{event:"chat.handoffs_extracted",count:handoffs.length,handoffs}});
    }catch(error){
      if(signal?.aborted)throw error;
      extractionFailed=true;
      // Never improvise an action or send raw chat to a fallback model on extraction failure.
      emit({type:"loop",payload:{event:"chat.extraction_failed",code:"chat_extraction_failed",reason:error instanceof SyntaxError?"invalid_json":error instanceof Error?error.message:"unknown",actions_submitted:0}});
    }
    return {protocol_version:2,decision_id:`chat:${r.request_id}`,request_id:r.request_id,agent_id:r.agent_id,expected_revision:r.world_revision,
      actions,speech:reply,chat_extraction_failed:extractionFailed,decision_summary:"Chat reply; extracted game intentions await a fresh action loop",chat_handoffs:handoffs,chat_isolated:true};
  }
}
