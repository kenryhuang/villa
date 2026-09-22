import type { MemoryRepository } from "../memory.ts";
import { actionActor } from "../context_channels.ts";

export function intentDiagnostics(
  memory: MemoryRepository,
  session: string,
  actor: string,
  request: string,
) {
  const source = memory.inspectEvent(
    session,
    `chat.jobs:${actor}`,
    `intent-job:${request}`,
  );
  if (!source.found)
    return {
      request_id: request,
      agent_id: actor,
      status: "not_recorded",
      calls: [],
      events: [],
    };
  const job = source.payload as Record<string, unknown>;
  const done = memory.inspectEvent(
    session,
    `chat.jobs:${actor}`,
    `intent-done:${request}`,
  );
  const extracted = memory.inspectEvent(
    session,
    actionActor(actor),
    `chat-intents:${request}`,
  );
  const consumed = memory.inspectEvent(
    session,
    actionActor(actor),
    `consumed:chat-intents:${request}`,
  );
  const events = memory.intentJobTrace(session, actor, request);
  const calls: Record<string, any>[] = [];
  let route: Record<string, unknown> = {},
    status = "queued",
    error = "",
    prepared_messages: unknown[] = [],
    validation: unknown = null;
  for (const event of events) {
    const trace = event.trace as any;
    if (
      trace?.type === "loop" &&
      trace.payload.event === "chat.intent_prepared"
    )
      prepared_messages = trace.payload.messages;
    if (
      trace?.type === "loop" &&
      trace.payload.event === "chat.intent_validation"
    )
      validation = trace.payload;
    if (trace?.type === "loop" && trace.payload.event === "provider.route")
      route = trace.payload;
    if (trace?.type === "input")
      calls.push({
        attempt_id: event.attempt_id,
        input: trace.body,
        route: { ...route },
        output: {},
        timestamp_msec: event.timestamp_msec,
      });
    if (
      trace?.type === "output" &&
      calls.at(-1)?.attempt_id === event.attempt_id
    )
      calls.at(-1)!.output = trace.output;
    if (event.status) {
      status = String(event.status);
      if(status==="running"){error="";validation=null;prepared_messages=[];}
    }
    if (event.kind === "ChatIntentError") {
      status = event.retryable ? "retry_wait" : "failed";
      error = String(event.error);
    }
  }
  if (done.found) status = String((done.payload as any).status);
  return {
    request_id: request,
    agent_id: actor,
    status,
    error,
    calls,
    events,
    prepared_messages,
    validation,
    raw_messages: [
      { role: "user", speaker: "player", content: job.player },
      { role: "assistant", speaker: actor, content: job.reply },
    ],
    accepted: (extracted.payload as any)?.intents ?? [],
    archived: extracted.found === true,
    consumed: consumed.found === true,
    diagnostic_note: calls.length
      ? "实际发送的模型请求见 calls[].input，原始输出见 calls[].output"
      : "尚无实际请求记录；旧版本未保存的 prompt/输出无法追溯，未用当前模板冒充历史请求",
  };
}
