import {actionActor,actionFacts,appendIsolatedEvent,prepareActionRequest} from "./context_channels.ts";
import {chatRoomKey,renderHandoffs,type ChatPort} from "./chat_provider.ts";
import {CHAT_HISTORY_MESSAGES} from "./chat_context.ts";
import {WorldReadBroker} from "./world_read_broker.ts";
import {createHash} from "node:crypto";
import type { IncomingMessage, ServerResponse } from "node:http";
import { isAbsolute, relative, resolve } from "node:path";
import type { AgentRegistry } from "./agents.ts";
import type { MemoryRepository } from "./memory.ts";
import { PROTOCOL_VERSION, parseActionOutcome, parseDecisionRequest, type ActionIntent, type DecisionRequest } from "./protocol.ts";
import type {ProviderTraceEvent} from "./provider_stream.ts";

interface ProviderPort {
  decide(request: DecisionRequest, context: ReturnType<AgentRegistry["buildContext"]>): Promise<ActionIntent>;
  streamDecision?(
    request: DecisionRequest,
    context: ReturnType<AgentRegistry["buildContext"]>,
    emit: (event: ProviderTraceEvent) => void,
    signal?: AbortSignal,
  ): Promise<ActionIntent>;
  compactMemory?(agent: NonNullable<ReturnType<AgentRegistry["get"]>>, events: ReturnType<MemoryRepository["recent"]>, sessionId?: string): Promise<{summary: string; importance: number}>;
}
interface AppDependencies { memory: MemoryRepository; registry: AgentRegistry; provider: ProviderPort; chatProvider?: ChatPort; checkpointRoot: string; }

function appendExperience(d:AppDependencies,session:string,actor:string,event:Parameters<MemoryRepository["appendEvent"]>[2]):void {
  if(d.chatProvider)appendIsolatedEvent(d.memory,session,actor,event);
  else d.memory.appendEvent(session,actor,event);
}

const MAX_REQUEST_BODY_BYTES = 1_048_576;

function decisionCacheKey(request: DecisionRequest): string {
  const fingerprint = createHash("sha256").update(JSON.stringify(request)).digest("hex");
  return `decision:${request.session_id}:${request.request_id}:${fingerprint}`;
}

const memoryJobs = new WeakMap<MemoryRepository,Set<string>>();
async function compactMemoryIfDue(dependencies: AppDependencies, sessionId: string, agentId: string): Promise<void> {
  const memory=dependencies.memory;
  if(memory.closed || !dependencies.provider.compactMemory)return;
  const jobs=memoryJobs.get(memory) ?? new Set<string>();memoryJobs.set(memory,jobs);
  const storageId=dependencies.chatProvider?actionActor(agentId):agentId;
  const key=`${sessionId}:${storageId}`;if(jobs.has(key))return;
  jobs.add(key);
  try{
    const agent=dependencies.registry.get(agentId);if(!agent)return;
    const history=memory.historyCandidates(sessionId,storageId);
    if(history.events.length){
      const summary=await dependencies.provider.compactMemory(agent,[...(history.previous?[{event_id:"history-prefix",kind:"prior_history_summary",game_minute:history.events[0].game_minute,payload:{summary:history.previous}}]:[]),...history.events],sessionId);
      if(memory.closed)return;
      if(history.events.every(e=>JSON.stringify(memory.inspectEvent(sessionId,storageId,e.event_id).payload)===JSON.stringify(e.payload)))memory.storeHistory(sessionId,storageId,history.events.map(e=>e.event_id),summary.summary);
    }
    if(!memory.shouldCompact(sessionId,storageId))return;
    const events=memory.compactionCandidates(sessionId,storageId,8);
    if(!events.length)return;
    const result=await dependencies.provider.compactMemory(agent,events,sessionId);
    if(memory.closed)return;
    // A restored checkpoint may have removed these future events while the model ran.
    if(events.some(e=>JSON.stringify(memory.inspectEvent(sessionId,storageId,e.event_id).payload)!==JSON.stringify(e.payload)))return;
    memory.storeLongTermMemory(sessionId,storageId,`memory:${sessionId}:${storageId}:${events[0].event_id}:${events.at(-1)!.event_id}`,
      result.summary,result.importance,events.map(e=>e.event_id));
  }catch{
    // Durable raw candidates remain queryable and retry on the next event/sync.
  }finally{jobs.delete(key);}
}

const send = (response: ServerResponse, status: number, body: unknown): void => {
  response.statusCode = status;
  response.setHeader("content-type", "application/json; charset=utf-8");
  response.end(JSON.stringify(body));
};

function decisionContext(dependencies: AppDependencies, request: DecisionRequest) {
  if(request.protocol_version===3){
    dependencies.memory.syncSession(request.session_id,request.session_epoch);
    const resources=request.resources!;
    dependencies.memory.syncResources(request.session_id,request.agent_id,request.session_epoch,Number(resources.resource_revision ?? request.world_revision),resources);
    for(const event of request.experience_events ?? [])appendExperience(dependencies,request.session_id,request.agent_id,{
      event_id:String(event.event_id),kind:String(event.kind ?? event.event_type ?? "world"),game_minute:Number(event.game_minute),
      payload:(event.payload ?? event) as Record<string,unknown>});
    const memories=dependencies.memory.relevant(request.session_id,dependencies.chatProvider?actionActor(request.agent_id):request.agent_id,
      [request.dialogue_input ?? "",...request.goals,JSON.stringify(request.goal_refs ?? []),JSON.stringify(request.dialogue_followups ?? []),JSON.stringify((request.experience_events ?? []).slice(-3))].join(" "));
    return dependencies.registry.buildContext(request.agent_id,request,memories);
  }
  const memories = [
    ...dependencies.memory.longTermRecent(request.session_id, request.agent_id, 8),
    ...dependencies.memory.recent(request.session_id, request.agent_id, 8),
  ];
  return dependencies.registry.buildContext(request.agent_id, request, memories);
}

function storeDecision(
  dependencies: AppDependencies,
  request: DecisionRequest,
  decisionKey: string,
  intent: ActionIntent,
): void {
  dependencies.memory.storeIdempotent(decisionKey, intent);
  dependencies.memory.appendEvent(request.session_id, dependencies.chatProvider?actionActor(request.agent_id):request.agent_id, {
    event_id: `decision:${intent.decision_id}`,
    kind: "decision",
    game_minute: request.game_minute,
    payload: {
      actions: intent.actions,
      action_names: intent.actions.map((action) => action.tool_name),
      decision_summary: intent.decision_summary,
    },
  });
  if (!dependencies.chatProvider && request.trigger === "dialogue" && request.dialogue_input?.trim()) {
    dependencies.memory.appendEvent(request.session_id, dependencies.chatProvider?actionActor(request.agent_id):request.agent_id, {
      event_id: `dialogue:${request.protocol_version===3?request.request_id:intent.decision_id}`,
      kind: "dialogue",
      game_minute: request.game_minute,
      payload: {
        player_text: request.dialogue_input,
        agent_speech: intent.speech?.trim() || intent.actions.filter(a=>a.tool_name==="speak" && a.arguments.target_actor_id==="player").map(a=>String(a.arguments.text ?? "")).join("\n"),
      },
    });
  }
  if(dependencies.chatProvider)for(const action of intent.actions){
    if(!["adopt_short_term_goal","revise_short_term_goal"].includes(action.tool_name))continue;
    const goalId=action.tool_name==="adopt_short_term_goal"?"goal-"+createHash("sha256").update(action.idempotency_key).digest("hex").slice(0,24):String(action.arguments.goal_id);
    const version=action.tool_name==="adopt_short_term_goal"?1:Number(action.arguments.version)+1;
    dependencies.memory.appendEvent(request.session_id,actionActor(request.agent_id),{event_id:`action-goal:${goalId}:${version}`,kind:"ActionGoalPlan",game_minute:request.game_minute,
      payload:{goal_id:goalId,version,description:action.arguments.description}});
  }
  void compactMemoryIfDue(dependencies,request.session_id,request.agent_id);
}

function beginSse(response: ServerResponse): void {
  response.statusCode = 200;
  response.setHeader("content-type", "text/event-stream; charset=utf-8");
  response.setHeader("cache-control", "no-cache, no-transform");
  response.setHeader("connection", "keep-alive");
  response.setHeader("x-accel-buffering", "no");
  response.flushHeaders();
}

async function readBody(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;
    if (size > MAX_REQUEST_BODY_BYTES) throw new Error("payload_too_large");
    chunks.push(buffer);
  }
  try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); }
  catch { throw new Error("invalid_json"); }
}

export function createApp(dependencies: AppDependencies) {
  const reads=new WorldReadBroker();
  return async (request: IncomingMessage, response: ServerResponse): Promise<void> => {
    try {
      const url = new URL(request.url || "/", "http://localhost");
      if (request.method === "GET" && url.pathname === "/health") {
        send(response, 200, {status: "ok", protocol_version: PROTOCOL_VERSION, provider: "configured", chat_provider: dependencies.chatProvider?.model??null, context_channels: dependencies.chatProvider?["chatcontext","actioncontext"]:["legacy"], decision_protocol_version: 3, capabilities: ["agent_loop_v3", "lazy_world_reads", "farm3d_environment", "rent_production", "living_world_projects", "living_world_interruptions", "public_coordination"]}); return;
      }
      if (request.method !== "POST") { send(response, 404, {error: {code: "NOT_FOUND"}}); return; }
      const body = await readBody(request);
      if(url.pathname==="/v1/experience/sync") {
        const value=body as Record<string,unknown>;
        if(typeof value.session_id!=="string"||!Number.isSafeInteger(value.session_epoch)||!Array.isArray(value.actors)||value.actors.length>64)throw new Error("invalid_experience_sync");
        dependencies.memory.syncSession(value.session_id,Number(value.session_epoch));
        const acknowledged=[];
        for(const entry of value.actors as Record<string,unknown>[]){
          if(!dependencies.registry.get(String(entry.agent_id))||!Array.isArray(entry.events)||!entry.resources||typeof entry.resources!=="object")throw new Error("invalid_experience_actor");
          const resources=entry.resources as Record<string,unknown>;
          dependencies.memory.syncResources(value.session_id,String(entry.agent_id),Number(value.session_epoch),Number(resources.resource_revision),resources);
          for(const e of entry.events as Record<string,unknown>[])appendExperience(dependencies,value.session_id,String(entry.agent_id),{
            event_id:String(e.event_id),kind:String(e.kind ?? e.event_type ?? "world"),game_minute:Number(e.game_minute),payload:(e.payload ?? {}) as Record<string,unknown>});
          void compactMemoryIfDue(dependencies,value.session_id,String(entry.agent_id));
          acknowledged.push({agent_id:entry.agent_id,event_ids:(entry.events as Record<string,unknown>[]).map(e=>e.event_id)});
        }
        send(response,200,{acknowledged});return;
      }
      if(url.pathname==="/v1/reads/result") {send(response,200,{accepted:reads.accept(body as Record<string,unknown>)});return;}
      if (url.pathname === "/v1/sessions/sync") {
        const record = body as Record<string, unknown>;
        if (!record || typeof record.session_id !== "string" || !Number.isSafeInteger(record.session_epoch)) throw new Error("invalid_session");
        if (record.reset === true) dependencies.memory.resetSession(record.session_id, Number(record.session_epoch));
        else dependencies.memory.syncSession(record.session_id, Number(record.session_epoch));
        send(response, 200, {status: "synced"}); return;
      }
      const streamMatch = url.pathname.match(/^\/v1\/agents\/([^/]+)\/decide\/stream$/);
      if (streamMatch) {
        const parsed = parseDecisionRequest(body);
        if (!parsed.ok) throw new Error(parsed.error);
        if(dependencies.chatProvider && parsed.value.protocol_version!==3)throw new Error("split_context_requires_protocol_v3");
        const receivedEventIds=(parsed.value.experience_events??[]).map(e=>e.event_id);
        const decisionRequest = dependencies.chatProvider && parsed.value.trigger!=="dialogue" ? prepareActionRequest(dependencies.memory,parsed.value) : parsed.value;
        if (decisionRequest.agent_id !== streamMatch[1]) {
          send(response, 409, {error: {code: "AGENT_MISMATCH"}}); return;
        }
        const decisionKey = (dependencies.chatProvider?`${decisionRequest.trigger==="dialogue"?"chat:"+dependencies.chatProvider.model:"action.v2"}:`:"")+decisionCacheKey(decisionRequest);
        const cached = dependencies.memory.getIdempotent(decisionKey) as ActionIntent | undefined;
        beginSse(response);
        let sequence = 0;
        const writeEvent = (name: string, payload: unknown): void => {
          if (response.destroyed || response.writableEnded) return;
          sequence += 1;
          const envelope = {
            protocol_version: PROTOCOL_VERSION,
            stream_id: `${decisionRequest.request_id}:stream`,
            request_id: decisionRequest.request_id,
            agent_id: decisionRequest.agent_id,
            sequence,
            timestamp_msec: Date.now(),
            payload,
          };
          response.write(`id: ${sequence}\nevent: ${name}\ndata: ${JSON.stringify(envelope)}\n\n`);
        };
        if (cached) {
          writeEvent("decision.final", cached);
          writeEvent("stream.completed", {status: "completed", cached: true});
          response.end();
          return;
        }
        writeEvent("stream.started", {trigger: decisionRequest.trigger});
        const controller = new AbortController();
        let finished = false;
        const cancel = () => { if (!finished) controller.abort(); };
        request.once("aborted", cancel);
        response.once("close", cancel);
        const heartbeat = setInterval(() => {
          if (!response.destroyed && !response.writableEnded) response.write(": heartbeat\n\n");
        }, 5_000);
        try {
          if (!dependencies.provider.streamDecision) throw new Error("provider_streaming_unavailable");
          const emit = (event: ProviderTraceEvent): void => {
            switch (event.type) {
              case "loop": writeEvent("loop.trace",event.payload); break;
              case "input": writeEvent("provider.input", event.body); break;
              case "reasoning": writeEvent("reasoning.delta", {delta: event.delta}); break;
              case "content": writeEvent("content.delta", {delta: event.delta}); break;
              case "tool_call": writeEvent("tool_call.delta", {
                index: event.index,
                ...(event.id !== undefined ? {id: event.id} : {}),
                ...(event.name !== undefined ? {name: event.name} : {}),
                ...(event.arguments !== undefined ? {arguments: event.arguments} : {}),
              }); break;
              case "output": writeEvent("provider.output", event.output); break;
            }
          };
          if(dependencies.chatProvider && decisionRequest.trigger==="dialogue") {
            if(decisionRequest.protocol_version!==3)throw new Error("chat_requires_protocol_v3");
            const participants=decisionRequest.chat_room?.participants??[decisionRequest.agent_id];
            if(participants.some(id=>!dependencies.registry.get(id)||id==="village_public"))throw new Error("invalid_chat_participant");
            dependencies.memory.syncSession(decisionRequest.session_id,decisionRequest.session_epoch);
            const scope=chatRoomKey(decisionRequest);
            const userEventId=`chat-user:${decisionRequest.chat_room?.turn_id??decisionRequest.request_id}`;
            const existing=dependencies.memory.inspectEvent(decisionRequest.session_id,scope,userEventId);
            if(existing.found && (existing.payload as any).text!==decisionRequest.dialogue_input)throw new Error("chat_turn_changed");
            dependencies.memory.appendEvent(decisionRequest.session_id,scope,{event_id:`chat-user:${decisionRequest.chat_room?.turn_id??decisionRequest.request_id}`,
              kind:"ChatMessage",game_minute:decisionRequest.game_minute,payload:{speaker:"player",text:decisionRequest.dialogue_input??""}});
            const chatContext=dependencies.registry.buildContext(decisionRequest.agent_id,decisionRequest,[]);
            const intent=await dependencies.chatProvider.respond(decisionRequest,chatContext,dependencies.memory.recent(decisionRequest.session_id,scope,CHAT_HISTORY_MESSAGES).reverse(),
              dependencies.registry.ids().filter(id=>id!=="village_public").map(id=>{const a=dependencies.registry.get(id)!;return {id,name:a.display_name,role:a.role_id,soul:a.soul};}),
              (name,args,signal)=>reads.read(decisionRequest,name,args,p=>writeEvent("read.request",p),signal),emit,controller.signal);
            if(!controller.signal.aborted){
              dependencies.memory.appendEvent(decisionRequest.session_id,scope,{event_id:`chat-reply:${decisionRequest.request_id}`,kind:"ChatMessage",game_minute:decisionRequest.game_minute,
                payload:{speaker:decisionRequest.agent_id,text:intent.speech??"",participants}});
              if(intent.chat_handoffs?.length)dependencies.memory.appendEvent(decisionRequest.session_id,actionActor(decisionRequest.agent_id),{
                event_id:`dialogue:${decisionRequest.request_id}`,kind:"ChatActionAgreed",game_minute:decisionRequest.game_minute,
                payload:{handoff_version:1,player_text:"",agent_speech:renderHandoffs(intent.chat_handoffs),submitted_actions:[],outcomes:[],handoffs:intent.chat_handoffs}});
              dependencies.memory.storeIdempotent(decisionKey,intent);
              writeEvent("decision.final",intent);writeEvent("stream.completed",{status:"completed",cached:false});
            }
            return;
          }
          const context=decisionContext(dependencies,decisionRequest);
          void compactMemoryIfDue(dependencies,decisionRequest.session_id,decisionRequest.agent_id);
          if(decisionRequest.protocol_version===3){
            writeEvent("context.ack",{session_id:decisionRequest.session_id,session_epoch:decisionRequest.session_epoch,
              request_id:decisionRequest.request_id,event_ids:receivedEventIds});
            const storageId=dependencies.chatProvider?actionActor(decisionRequest.agent_id):decisionRequest.agent_id;
            const experience=dependencies.memory.experience(decisionRequest.session_id,storageId);
            const recentIds=new Set((experience.recent_events as Record<string,unknown>[]).map(e=>e.event_id));
            context.loop_services={experience,memories:context.memories.filter(m=>!(m.source_event_ids as string[]|undefined)?.some(id=>recentIds.has(id))),
              read:async(name,args,signal)=>{
                if(name==="recall_memory")return {memories:dependencies.memory.relevant(decisionRequest.session_id,storageId,String(args.query))};
                if(name==="inspect_event")return dependencies.memory.inspectEvent(decisionRequest.session_id,storageId,String(args.event_id));
                if(name==="inspect_history_segment")return dependencies.memory.historySegment(decisionRequest.session_id,storageId,Number(args.cursor ?? 0));
                const result=await reads.read(decisionRequest,name,args,p=>writeEvent("read.request",p),signal);
                if(result.resources)dependencies.memory.syncResources(decisionRequest.session_id,decisionRequest.agent_id,decisionRequest.session_epoch,
                  Number((result.resources as Record<string,unknown>).resource_revision),result.resources as Record<string,unknown>);
                return dependencies.chatProvider?actionFacts(result):result;
              }};
          }
          const intent = await dependencies.provider.streamDecision(
            decisionRequest,
            context,
            emit,
            controller.signal,
          );
          if (!controller.signal.aborted) {
            storeDecision(dependencies, decisionRequest, decisionKey, intent);
            writeEvent("decision.final", intent);
            writeEvent("stream.completed", {status: "completed", cached: false});
          }
        } catch (error) {
          if (!controller.signal.aborted) {
            const message = error instanceof Error ? error.message : "unknown_error";
            writeEvent("stream.error", {
              code: message,
              message,
              retryable: message.includes("timeout") || message.startsWith("provider_http_5"),
            });
          }
        } finally {
          finished = true;
          clearInterval(heartbeat);
          request.removeListener("aborted", cancel);
          response.removeListener("close", cancel);
          if (!response.destroyed && !response.writableEnded) response.end();
        }
        return;
      }
      const decisionMatch = url.pathname.match(/^\/v1\/agents\/([^/]+)\/decide$/);
      if (decisionMatch) {
        const parsed = parseDecisionRequest(body);
        if (!parsed.ok) throw new Error(parsed.error);
        if (parsed.value.agent_id !== decisionMatch[1]) { send(response, 409, {error: {code: "AGENT_MISMATCH"}}); return; }
        const decisionKey = decisionCacheKey(parsed.value);
        const cached = dependencies.memory.getIdempotent(decisionKey);
        if (cached) { send(response, 200, cached); return; }
        if(parsed.value.protocol_version===3 || dependencies.chatProvider)throw new Error("streaming_required_for_agent_loop");
        const context = decisionContext(dependencies, parsed.value);
        const intent = await dependencies.provider.decide(parsed.value, context);
        storeDecision(dependencies, parsed.value, decisionKey, intent);
        send(response, 200, intent); return;
      }
      const outcomeMatch = url.pathname.match(/^\/v1\/agents\/([^/]+)\/outcomes$/);
      if (outcomeMatch) {
        const parsed = parseActionOutcome(body);
        if (!parsed.ok) throw new Error(parsed.error);
        const sessionId = String(request.headers["x-session-id"] || "");
        if (!sessionId) throw new Error("missing_session_id");
        const key = `outcome:${sessionId}:${outcomeMatch[1]}:${parsed.value.idempotency_key}:${parsed.value.status}:${parsed.value.committed_revision}`;
        if (dependencies.memory.getIdempotent(key)) { send(response, 200, {status: "duplicate"}); return; }
        dependencies.memory.storeIdempotent(key, parsed.value);
        appendExperience(dependencies,sessionId, outcomeMatch[1], {
          event_id: `action:${parsed.value.idempotency_key}:${parsed.value.status}:${parsed.value.committed_revision}`, kind: "Action" + parsed.value.status[0].toUpperCase() + parsed.value.status.slice(1),
          game_minute: parsed.value.game_minute,
          payload: {...parsed.value},
        });
        void compactMemoryIfDue(dependencies, sessionId, outcomeMatch[1]);
        send(response, 202, {status: "accepted"}); return;
      }
      if (url.pathname === "/v1/checkpoints/export") {
        const record = body as Record<string, unknown>;
        if (typeof record?.session_id !== "string" || typeof record?.checkpoint_id !== "string") throw new Error("invalid_checkpoint_request");
        send(response, 200, dependencies.memory.exportCheckpoint(record.session_id, dependencies.checkpointRoot, record.checkpoint_id)); return;
      }
      if (url.pathname === "/v1/checkpoints/import") {
        const record = body as Record<string, unknown>;
        if (typeof record?.session_id !== "string" || typeof record?.path !== "string" || typeof record?.sha256 !== "string") throw new Error("invalid_checkpoint_request");
        const root = resolve(dependencies.checkpointRoot);
        const checkpointPath = resolve(record.path);
        const checkpointRelative = relative(root, checkpointPath);
        if (checkpointRelative.startsWith("..") || isAbsolute(checkpointRelative)) throw new Error("invalid_checkpoint_path");
        dependencies.memory.importCheckpoint(checkpointPath, record.sha256, record.session_id);
        send(response, 200, {status: "imported"}); return;
      }
      send(response, 404, {error: {code: "NOT_FOUND"}});
    } catch (error) {
      const message = error instanceof Error ? error.message : "unknown_error";
      send(response, message === "payload_too_large" ? 413 : 400, {error: {code: message}});
    }
  };
}
