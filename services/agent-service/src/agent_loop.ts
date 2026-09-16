import {readFileSync} from "node:fs";
import {fileURLToPath} from "node:url";
import type {AgentContext} from "./agents.ts";
import type {DecisionRequest, ActionIntent} from "./protocol.ts";
import {toolDescription, toolArgumentErrors} from "./tool_contracts.ts";
import {AgentStreamAssembler, type ProviderTraceEvent} from "./provider_stream.ts";
import {LOOP_DIALOGUE_COMMANDS as DIALOGUE_COMMANDS} from "./agent_policy.ts";

import {compactWorkingMessages} from "./agent_context_compaction.ts";
export {compactWorkingMessages} from "./agent_context_compaction.ts";
export const QUERY_CATALOG: Record<string, {sections: string[]; default_section: string; hint: string}> = JSON.parse(readFileSync(fileURLToPath(new URL("../../../data/agents/query_catalog.json", import.meta.url)), "utf8"));

export const GAME_ENV = JSON.parse(readFileSync(fileURLToPath(new URL("../../../data/agents/game_env.json", import.meta.url)), "utf8"));
export interface LoopConfig {max_read_rounds: number; max_read_calls: number; max_actions: number; max_dialogue_actions: number;
  compact_at_tokens: number; compact_target_tokens: number; max_input_tokens: number; max_compactions: number;}
export const DEFAULT_LOOP: LoopConfig = {max_read_rounds:6,max_read_calls:12,max_actions:3,max_dialogue_actions:1,
  compact_at_tokens:48000,compact_target_tokens:32000,max_input_tokens:64000,max_compactions:6};
export type ReadPort = (name: string, args: Record<string, unknown>, signal?: AbortSignal) => Promise<Record<string, unknown>>;
export interface LoopServices {read: ReadPort; experience: Record<string, unknown>; memories: readonly Record<string, unknown>[];}
export function validateLoopConfig(value: unknown): LoopConfig {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid_loop_config");
  const result = {...DEFAULT_LOOP, ...value};
  for (const [k,v] of Object.entries(result)) if (!(k in DEFAULT_LOOP) || !Number.isSafeInteger(v) || Number(v)<1) throw new Error("invalid_loop_config");
  if (!(result.compact_target_tokens < result.compact_at_tokens && result.compact_at_tokens < result.max_input_tokens)
    || result.max_actions>3 || result.max_dialogue_actions>result.max_actions || result.max_read_calls>64 || result.max_read_rounds>16 || result.max_compactions>8) throw new Error("invalid_loop_config");
  return result;
}
const obj = (value: unknown): Record<string, unknown> => value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
const BASIC_COMMANDS = ["speak","wait","public_wait"];
export function commandDomain(name: string): string {
  if (name.startsWith("public_")) return "public";
  if (name.includes("short_term_goal")) return "goals";
  if (["move","travel"].includes(name)) return "map";
  if (["till","plant","harvest"].includes(name)) return "farm";
  if (["buy","sell","request_supply"].includes(name)) return "market";
  if (["build","rent_production","manage_building"].includes(name)) return "buildings";
  if (["survey","collect_sample","register_discovery","prepare_supplies"].includes(name) || /intelligence|investigation/.test(name)) return "knowledge";
  if (/activity/.test(name)) return "social";
  if (/route_repair/.test(name)) return "environment";
  if (/trade|cooperation|contribution|role_change/.test(name) || name === "send_message") return "actors";
  return "tasks";
}
const schema = (name:string, description:string, properties:Record<string,unknown>,required:string[]=[]) => ({type:"function",function:{name,description,parameters:{type:"object",properties,required,additionalProperties:false}}});
const str = {type:"string",maxLength:500};
export function readDefinition(name:string, domains:string[], actionNames:readonly string[]=[]): Record<string,unknown> {
  if (name === "discover_tools") return schema(name,"发现所需领域的查询入口和行动目录，不执行行动、不读取世界实例。首次只填 domains，例如 {\"domains\":[\"farm\"]}。查询事实使用 query_world；行动名称只能从返回的 available_actions 选择，不能填写意图描述或读取工具名。",{
    domains:{type:"array",items:{type:"string",enum:domains},minItems:1,maxItems:3},
    ...(actionNames.length?{actions:{type:"array",description:"可选：从已发现的 available_actions 中选取精确行动名，替换当前额外行动菜单；省略则保留已启用行动。不是要查询的信息或要立即执行的动作。",items:{type:"string",enum:actionNames},maxItems:6,uniqueItems:true}}:{})},["domains"]);
  if (name === "query_world") return schema(name,"查询授权事实，无需先读overview。按discover_tools返回的query_catalog选择分区。省略section时id/ids自动查detail、query自动搜索，否则overview。多词query匹配任一词；精确批量详情用ids。租生产先查buildings/quote。",{
    domain:{type:"string",enum:domains},section:{type:"string",enum:["overview",...new Set(domains.flatMap(d=>QUERY_CATALOG[d]?.sections ?? []))]},
    id:str,ids:{type:"array",items:str,minItems:1,maxItems:10,uniqueItems:true},query:str,recipe_id:str,batches:{type:"integer",minimum:1,maximum:100},
    cursor:{type:"integer",minimum:0},limit:{type:"integer",minimum:1,maximum:10}},["domain"]);
  if (name === "recall_memory") return schema(name,"检索自己在本存档中的重要记忆。历史事实不是实时状态。",{query:str},["query"]);
  if (name === "inspect_event") return schema(name,"按来源ID查询自己的完整经历原文。",{event_id:str},["event_id"]);
  if (name === "inspect_history_segment") return schema(name,"分页查询自己的早期事件原文。",{cursor:{type:"integer",minimum:0}});
  return schema(name,"重新核对自己的完整资源。",{});
}
export function validLoopRead(name:string,args:Record<string,unknown>,domains:string[]):boolean {
  if (name === "discover_tools") return Object.keys(args).every(k=>["domains","actions"].includes(k)) && (args.actions===undefined || Array.isArray(args.actions) && args.actions.length<=6 && args.actions.every(x=>typeof x==="string")) && Array.isArray(args.domains) && args.domains.length>0 && args.domains.length<=3 && args.domains.every(x=>domains.includes(String(x)));
  if (name === "query_world") return domains.includes(String(args.domain)) && Object.keys(args).every(k=>["domain","section","id","ids","query","recipe_id","batches","cursor","limit"].includes(k)) &&
    ["section","id","query","recipe_id"].every(k=>args[k]===undefined || typeof args[k]==="string" && String(args[k]).length<=500) &&
    (args.ids===undefined || Array.isArray(args.ids) && args.ids.length>0 && args.ids.length<=10 && new Set(args.ids).size===args.ids.length && args.ids.every(x=>typeof x==="string" && x.length>0 && x.length<=500)) &&
    (args.batches===undefined || Number.isSafeInteger(args.batches) && Number(args.batches)>=1 && Number(args.batches)<=100) &&
    (args.cursor===undefined || Number.isSafeInteger(args.cursor) && Number(args.cursor)>=0) && (args.limit===undefined || Number.isSafeInteger(args.limit) && Number(args.limit)>=1 && Number(args.limit)<=10);
  if (name === "recall_memory" || name === "inspect_event") {const key=name==="recall_memory"?"query":"event_id";return Object.keys(args).length===1 && typeof args[key]==="string" && String(args[key]).length<=500;}
  if (name === "inspect_history_segment") return Object.keys(args).every(k=>k==="cursor") && (args.cursor===undefined || Number.isSafeInteger(args.cursor) && Number(args.cursor)>=0);
  return name==="inspect_self_resources" && Object.keys(args).length===0;
}
// Conservative UTF-8 byte bound: explicitly labelled as an estimate in telemetry.
export const inputEstimate = (value:unknown):number => new TextEncoder().encode(JSON.stringify(value)).length;
export async function runAgentLoop(request:DecisionRequest,context:AgentContext,services:LoopServices,
  round:(messages:Record<string,unknown>[],tools:Record<string,unknown>[],fast:boolean)=>Promise<AgentStreamAssembler>,
  emit:(event:ProviderTraceEvent)=>void, signal?:AbortSignal, config:LoopConfig=DEFAULT_LOOP):Promise<ActionIntent> {
  const publicAgent=context.agent.active_role==="public_coordinator";
  const dialogue=request.trigger==="dialogue";
  const authorizedCommands=context.allowed_command_tools.filter(n=>!dialogue||DIALOGUE_COMMANDS.has(n));
  const domains=publicAgent?["public","environment","social","memory"]:Object.keys(GAME_ENV.domains).filter(x=>x!=="public");
  const opened=new Set<string>();
  const enabledCommands=new Set<string>(BASIC_COMMANDS);
  let reads=0,readRounds=0,compactions=0,corrections=0;
  const actionLimit=publicAgent?1:request.trigger==="dialogue"?config.max_dialogue_actions:config.max_actions;
  const header={identity:context.agent,resources:request.resources,experience:services.experience,relevant_memories:services.memories,
    turn:{loop_id:request.request_id,trigger:request.trigger,game_minute:request.game_minute,dialogue_input:request.dialogue_input,
      goal_refs:request.goal_refs ?? [],query_catalog:{} as Record<string,unknown>,budget:{remaining_read_rounds:config.max_read_rounds,remaining_read_calls:config.max_read_calls,max_read_calls_per_round:4,max_actions:actionLimit}}};
  let messages:Record<string,unknown>[]=[{role:"system",content:JSON.stringify({GameEnv:GAME_ENV.description,
    domains:Object.fromEntries(domains.map(d=>[d,GAME_ENV.domains[d]])),
    rules:`按自己的目标自主查询，信息足够后最终提交0-${actionLimit}个有序行动。不要混合读取和行动。行动后由游戏执行，异步步骤完成才续行。对话保持简短，不重复普通文字和speak。没有操作要明确。所有行为受实际权限、资源与条款约束。`,
    ...(dialogue?{dialogue_rules:"这是玩家对话，当前玩家消息是本轮任务。先以角色身份直接回答，用一至三句自然语言；问候直接回应，不因看到成熟作物或市场机会就转做自主规划。回答足够时无需工具。只有对话确实涉及交易、合作、生产或短期目标时才查询和提交相关互动；没有相关需求时不移动、不下单。不要在对话中种植、收获、买卖投机或出发探索，这些留给后台 Loop。用户提到的机会可在你明确决定采纳时设短期目标。即使调用互动行动也要给出对话回复；尚未执行的操作只能描述为请求/计划，不能声称完成。"}:{})})},
    {role:"user",content:JSON.stringify(header)}];
  while(true){
    signal?.throwIfAborted();
    const canRead=reads<config.max_read_calls && readRounds<config.max_read_rounds;
    const queryDomains=[...opened].filter(d=>QUERY_CATALOG[d]);
    const readNames=canRead?["discover_tools","inspect_self_resources","recall_memory",...(queryDomains.length?["query_world"]:[]),...(opened.has("memory")?["inspect_event","inspect_history_segment"]:[])]:[];
    const available=authorizedCommands.filter(n=>!BASIC_COMMANDS.includes(n)&&opened.has(commandDomain(n)));
    const commands=authorizedCommands.filter(n=>enabledCommands.has(n));
    const tools=[...readNames.map(n=>readDefinition(n,n==="query_world"?queryDomains:domains,available)),...commands.map(n=>toolDescription(n,true))];
    header.turn.budget={remaining_read_rounds:Math.max(0,config.max_read_rounds-readRounds),remaining_read_calls:canRead?config.max_read_calls-reads:0,
      max_read_calls_per_round:canRead?Math.min(4,config.max_read_calls-reads):0,max_actions:actionLimit};
    header.turn.query_catalog=Object.fromEntries([...opened].filter(d=>QUERY_CATALOG[d]).map(d=>[d,QUERY_CATALOG[d]]));
    messages[1]={role:"user",content:JSON.stringify(header)};
    const before=inputEstimate({messages,tools});
    const protectedInput=inputEstimate({messages:messages.slice(0,2),tools});
    const hardPressure=before>config.max_input_tokens;
    if(messages.length>2 && (hardPressure || before>=config.compact_at_tokens && compactions<config.max_compactions)){
      // The immutable header and tool schema are a real floor. Leave room for
      // useful observations instead of repeatedly targeting below that floor.
      const target=Math.min(config.max_input_tokens-1024,Math.max(config.compact_target_tokens,protectedInput+Math.min(8192,config.max_input_tokens/8)));
      messages=compactWorkingMessages(messages,target-inputEstimate({tools,messages:[]}));compactions++;
      const after=inputEstimate({messages,tools});
      emit({type:"loop",payload:{event:"context.compacted",loop_id:request.request_id,before,after,target,configured_target:config.compact_target_tokens,
        protected_input:protectedInput,target_met:after<=target,count:compactions,reason:hardPressure?"hard_limit_recovery":"threshold",estimate:"utf8_bytes_upper_bound"}});
    }
    const finalSize=inputEstimate({messages,tools});
    if(finalSize>config.max_input_tokens){
      emit({type:"loop",payload:{event:"context.capacity_exceeded",loop_id:request.request_id,input_estimate:finalSize,protected_input:protectedInput,
        tool_bytes:inputEstimate(tools),limit:config.max_input_tokens,compactions,reason:protectedInput>config.max_input_tokens?"protected_header_and_tools":"working_context"}});
      throw new Error("context_capacity_exceeded");
    }
    emit({type:"loop",payload:{event:"loop.round",loop_id:request.request_id,read_rounds:readRounds,reads,compactions,input_estimate:inputEstimate({messages,tools})}});
    const assembler=await round(messages,tools,request.trigger==="dialogue"||corrections>0);
    const raw=assembler.rawOutput();
    try {
      if(raw.finish_reason==="length") throw new Error("provider_output_truncated");
      const calls=assembler.toolCalls(Math.max(4,actionLimit));
      const unavailable=calls.filter(c=>!readNames.includes(c.name)&&!commands.includes(c.name));
      if(unavailable.length){
        if(unavailable.some(c=>!context.allowed_command_tools.includes(c.name)&&!["discover_tools","inspect_self_resources","recall_memory","query_world","inspect_event","inspect_history_segment"].includes(c.name)))throw new Error("provider_unauthorized_tool");
        if(unavailable.some(c=>context.allowed_command_tools.includes(c.name)&&!authorizedCommands.includes(c.name)))throw new Error("dialogue_action_not_allowed: answer the player's message; autonomous farming, trading and exploration belong to a background loop");
        if(unavailable.some(c=>context.allowed_command_tools.includes(c.name)))throw new Error("action_tool_not_enabled: use discover_tools to discover its domain and select the exact action name before calling it");
        throw new Error(canRead?"read_tool_not_discovered: open its domain using discover_tools first":"read_budget_exhausted: finish with an enabled action or a reply; no more reads are available");
      }
      if(calls.some(c=>readNames.includes(c.name))){
        if(calls.some(c=>!readNames.includes(c.name))) throw new Error("mixed_read_action_batch");
        if(reads+calls.length>config.max_read_calls) throw new Error("read_budget_exceeded");
        // Validate all calls before any read or catalog mutation.
        if(calls.some(c=>!validLoopRead(c.name,c.arguments,c.name==="query_world"?queryDomains:domains))) throw new Error("invalid_read_arguments");
        messages.push({role:"assistant",content:raw.message.content||null,tool_calls:raw.message.tool_calls});
        readRounds++;
        for(const call of calls){
          reads++;
          let result:Record<string,unknown>;
          if(call.name==="discover_tools") {
            for(const d of call.arguments.domains as string[])opened.add(d);
            const available=authorizedCommands.filter(n=>!BASIC_COMMANDS.includes(n)&&opened.has(commandDomain(n)));
            const requested=call.arguments.actions as string[]|undefined;
            const rejected=requested?.filter(n=>!available.includes(n)) ?? [];
            // Discovery is a catalog lookup, not a command. A mistaken selection
            // returns useful feedback and never grants or executes an unknown action.
            const retained=available.filter(n=>enabledCommands.has(n));
            const defaults=available.filter(n=>(call.arguments.domains as string[]).includes(commandDomain(n))).slice(0,4);
            const selected=rejected.length?retained:requested ?? [...new Set([...retained,...defaults])].slice(0,6);
            enabledCommands.clear();[...BASIC_COMMANDS,...selected].forEach(n=>enabledCommands.add(n));
            result={ok:rejected.length===0,opened:[...opened],query_catalog:Object.fromEntries([...opened].filter(d=>QUERY_CATALOG[d]).map(d=>[d,QUERY_CATALOG[d]])),available_actions:available,enabled_actions:selected,
              ...(rejected.length?{error:"invalid_action_selection",rejected_actions:rejected}:{}),
              next:"Domains are now open. query_catalog gives exact sections and requirements; skip overview and query facts directly with query_world(domain,section) or inspect_self_resources directly. actions accepts only exact names from available_actions, not read tools or natural-language descriptions. Omit actions to discover domains; explicit actions replaces the extra action menu. No action was executed."};
          }
          else result=await services.read(call.name,call.arguments,signal);
          emit({type:"loop",payload:{event:"read.result",loop_id:request.request_id,name:call.name,arguments:call.arguments,result}});
          if(result.resources){header.resources=obj(result.resources);messages[1]={role:"user",content:JSON.stringify(header)};}
          messages.push({role:"tool",tool_call_id:call.id,name:call.name,content:JSON.stringify(result)});
        }
        continue;
      }
      const errors=calls.flatMap(c=>toolArgumentErrors(c.name,c.arguments));
      if(errors.length) throw new Error(`invalid_action_arguments:${errors.join("; ")}`);
      if(dialogue&&!raw.message.content.trim()&&!calls.some(c=>c.name==="speak"&&c.arguments.target_actor_id==="player"&&String(c.arguments.text ?? "").trim()))
        throw new Error("dialogue_reply_required: provide a brief in-character spoken reply to the player's current message, even when submitting an interaction request");
      return assembler.finish(request,commands,actionLimit).intent;
    }catch(error){
      if(signal?.aborted)throw error;
      const message=error instanceof Error?error.message:"loop_error";
      emit({type:"loop",payload:{event:"loop.validation_failed",loop_id:request.request_id,error:message,
        called_tools:raw.message.tool_calls.map(c=>c.function.name),enabled_tools:[...readNames,...commands],remaining_read_calls:Math.max(0,config.max_read_calls-reads)}});
      if(message.includes("unauthorized")||corrections++>=1)throw error;
      messages.push({role:"system",content:`No action was submitted and the rejected batch did not execute. Correct once or finish without action: ${message.slice(0,900)}. Remaining reads: ${canRead?config.max_read_calls-reads:0}; at most ${header.turn.budget.max_read_calls_per_round} in one round. Current action menu: ${commands.join(", ")}.`});
    }
  }
}
