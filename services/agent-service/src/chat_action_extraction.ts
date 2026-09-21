import type {DecisionRequest} from "./protocol.ts";
import type {MemoryEvent} from "./memory.ts";

export const CHAT_ACTIVITIES={visit:"前往/拜访",walk:"散步",chat:"聊天",inspect_crops:"查看作物",fish:"钓鱼",golf:"打高尔夫",eat:"吃饭",drink:"喝水",rest:"休息",plant:"种植",water:"浇水",harvest:"收获",buy:"购买",sell:"出售",build:"建造",work:"工作",explore:"探索"} as const;
export interface ExtractionTurn {speaker:string;text:string;current?:boolean;}
export interface ExtractionPlace {id:string;name?:string;aliases?:unknown;owner_id?:string;kind?:string;}

// History and summaries deliberately never enter the extraction call.
export function extractionTurns(r:DecisionRequest,_history:MemoryEvent[],reply:string):ExtractionTurn[]{
  return [{speaker:"player",text:r.dialogue_input??"",current:true},{speaker:r.agent_id,text:reply,current:true}];
}

export function movementExtractionInstructions(places:ExtractionPlace[],actors:{id:string;name:string}[]):Record<string,unknown>{
  return {
    task:"只从最后一轮对话（本轮玩家消息＋本轮当前NPC回复）提取刚达成的‘去哪里、做什么’约定。没有历史对话或摘要可供提取，不要补想此前内容。输出必须是单个合法JSON对象，首字符为{，末字符为}；禁止Markdown代码块，禁止解释理由，禁止JSON外的任何文字。格式 {\"handoffs\":[],\"relationship\":null}，最多3条。没有已同意的安排就返回空数组。",
    agreement_rules:[
      "玩家提出‘去地点做行为’，NPC同意：提取。玩家本轮说‘好/行/可以/走吧’，且NPC本轮明确确认‘好，我们去某地做某事’：也提取，地点和行为取自本轮确认。若本轮只有‘好’和‘那就出发’，缺少目的地或行为，返回空数组，不能从历史补全。玩家提出安排本身就表示玩家愿意，无需额外再次确认。",
      "先判定玩家本轮有没有主动提出安排，或明确同意此前的安排。‘南湖在哪里？’‘你想去哪？’只是问询，绝不等于玩家同意。即使NPC在本轮回复里新邀请‘要一起去吗’，玩家还没有回答该邀请，handoffs必须为空；等待玩家下一轮确认。不能用NPC的意愿替代玩家的意愿。",
      "只记录当前NPC参与的约定；不能拿群内另一名NPC的话当成玩家或当前NPC的同意。player_evidence必须摘自本轮玩家发言；actor_evidence必须摘自本轮当前NPC回复。短短一个‘好’也可以作为证据。",
      "优先采用最新安排。问地点、假设、愿望、明确拒绝不算达成约定。玩家撤回或NPC最新明确拒绝时不创建agreed行动；双方明确取消旧安排时用cancelled。不要把早先的同意套到后来已被拒绝的安排上。",
      "同一轮的情绪或闲聊不影响独立存在的出行约定。‘迈步、拉手走’是聊天叙述，不是游戏真正到达的证据；本轮重新确认出发仍需记录。仅讨论已完成往事不重复派发。",
      "地点使用catalog.places中的唯一id；也可用唯一匹配的地名。建筑按owner_id区分归属。无法确定目的地或行为就返回空数组，让下一轮补问，不能编造。‘去看看’对应explore；散步walk；看作物inspect_crops。",
      "只提取地点和行为计划，不负责执行。‘去市场买东西’可记buy，不强制要求聊天先给商品、数量、价格；这些交给行动loop查询和确认。无明确约定时间时delay_minutes为0。",
    ],
    schema:{place_id:"catalog地点id",activity:CHAT_ACTIVITIES,status:"agreed或cancelled",target_actor_id:"共同前往填player；独自前往填空字符串；涉及重要角色用catalog演员id",player_evidence:"本轮玩家原文连续摘录",actor_evidence:"当前NPC提议或同意的原文连续摘录",delay_minutes:"可省略；非负整数，默认0"},
    examples:[
      {conversation:["玩家：好。","NPC：好，我们去南湖散步。"],handoffs:[{place_id:"lake",activity:"walk",status:"agreed",target_actor_id:"player",player_evidence:"好",actor_evidence:"我们去南湖散步"}]},
      {conversation:["玩家：好。","NPC：那就出发。"],handoffs:[]},
      {conversation:["玩家：我们去南湖钓鱼吧。","NPC：可以。"],handoffs:[{place_id:"lake",activity:"fish",status:"agreed",target_actor_id:"player",player_evidence:"我们去南湖钓鱼吧",actor_evidence:"可以"}]},
      {conversation:["玩家：不去了。","NPC：那就留在这里吧。"],handoffs:[]},
      {conversation:["玩家：南湖在哪里？","NPC：在农庄南边。"],handoffs:[]},
      {conversation:["玩家：南湖在哪里？","NPC：从这里向东走就到了。要一起去看看吗？顺便检查稻田！"],handoffs:[]},
    ],
    relationship_schema:"仅私聊：玩家本轮明确请求成为恋人或分手，且最后回复明确表态时可填 {decision:confirm/decline/end,player_evidence:玩家原文,reply_evidence:最后回复原文}。其他情况为null。",
    catalog:{places,actors},
  };
}

export function inspectMovementHandoffs(value:unknown,places:ExtractionPlace[],actors:string[],turns:ExtractionTurn[],actor:string){
  const accepted:Record<string,unknown>[]=[],rejected:{index:number;reason:string}[]=[];
  if(!Array.isArray(value)||value.length>3)return {accepted,rejected:[{index:-1,reason:"invalid_handoff_list"}]};
  const quote=(e:unknown,speaker:string,current=false)=>typeof e==="string"&&e.trim().length>0&&e.length<=1000&&turns.some(t=>t.speaker===speaker&&(!current||t.current)&&t.text.replace(/\s+/g,"").includes(e.replace(/\s+/g,"")));
  for(const [index,h] of value.entries()){
    const reject=(reason:string)=>rejected.push({index,reason});
    if(!h||typeof h!=="object"||Array.isArray(h)||Object.keys(h).some(k=>!["place_id","activity","status","target_actor_id","player_evidence","actor_evidence","delay_minutes"].includes(k))){reject("invalid_movement_fields");continue;}
    const matches=places.filter(p=>p.id===h.place_id||p.name===h.place_id||Array.isArray(p.aliases)&&p.aliases.includes(h.place_id));
    if(matches.length!==1){reject(matches.length?"ambiguous_place":"unknown_place_id");continue;}
    const activity=Object.hasOwn(CHAT_ACTIVITIES,String(h.activity))?String(h.activity):Object.entries(CHAT_ACTIVITIES).find(([,label])=>label===h.activity)?.[0];
    if(!activity){reject("unknown_activity");continue;}
    if(!["agreed","cancelled"].includes(h.status)){reject("invalid_status");continue;}
    if(!quote(h.player_evidence,"player",true)){reject("player_agreement_evidence_missing");continue;}
    if(!quote(h.actor_evidence,actor,true)){reject("actor_proposal_or_agreement_evidence_missing");continue;}
    const target=h.target_actor_id??"player",delay=h.delay_minutes??0;
    if(typeof target!=="string"||target!==""&&!actors.includes(target)){reject("unknown_actor_id");continue;}
    if(!Number.isSafeInteger(delay)||delay<0||delay>10080){reject("invalid_delay");continue;}
    const handoff={kind:"visit",activity,status:h.status,target_actor_id:target,place_id:matches[0].id,item_id:"",quantity:0,gold:0,delay_minutes:delay,trade_side:"none",building_type:"",plot:-1};
    if(!accepted.some(a=>JSON.stringify(a)===JSON.stringify(handoff)))accepted.push(handoff);
  }
  return {accepted,rejected};
}
