import type { AgentContext, Soul } from "../agents.ts";
import type { DecisionRequest } from "../protocol.ts";
import type { MemoryEvent } from "../memory.ts";
import { chatReplyText } from "../chat_reply.ts";
import { normalizeChatHistory } from "./reply_history.ts";

export const CHAT_HISTORY_TURNS = 5;
export const CHAT_HISTORY_MESSAGES = CHAT_HISTORY_TURNS * 5;
export const CHAT_HISTORY_CHARS = 6000;
export const CHAT_SUMMARY_CHARS = 800;
export interface ChatActor {
  id: string;
  name: string;
  role?: string;
  soul?: Soul;
}

export function importantChatActors(
  r: DecisionRequest,
  actors: ChatActor[],
): ChatActor[] {
  const ids = new Set([
    r.agent_id,
    ...(r.chat_focus_actors ?? []).map((a) => a.actor_id),
  ]);
  return actors
    .filter((a) => ids.has(a.id))
    .map((a) => ({
      id: a.id,
      name:
        r.chat_focus_actors?.find((p) => p.actor_id === a.id)?.display_name ??
        r.chat_participants?.find((p) => p.actor_id === a.id)?.display_name ??
        a.name,
    }));
}

export function selectChatHistory(
  r: DecisionRequest,
  history: MemoryEvent[],
): MemoryEvent[] {
  const currentId = `chat-user:${r.chat_room?.turn_id ?? r.request_id}`;
  const entries = history.filter((e) => e.kind === "ChatMessage");
  if (!entries.some((e) => e.event_id === currentId))
    entries.push({
      event_id: currentId,
      kind: "ChatMessage",
      game_minute: r.game_minute,
      payload: { speaker: "player", text: r.dialogue_input ?? "" },
    });
  const turns: MemoryEvent[][] = [];
  for (const entry of entries) {
    if (entry.payload.speaker === "player" || !turns.length) turns.push([]);
    turns.at(-1)!.push(entry);
  }
  const current = turns.findIndex((turn) =>
    turn.some((e) => e.event_id === currentId),
  );
  const window = turns.slice(
    Math.max(0, current - CHAT_HISTORY_TURNS + 1),
    current + 1,
  );
  const currentTurn = window.at(-1)!;
  const retained = new Set([currentId]);
  let chars = String(
    currentTurn.find((e) => e.event_id === currentId)!.payload.text ?? "",
  ).length;
  for (const event of [...currentTurn].reverse()) {
    if (event.event_id === currentId) continue;
    const size = String(event.payload.text ?? "").length;
    if (chars + size > CHAT_HISTORY_CHARS) break;
    retained.add(event.event_id);
    chars += size;
  }
  for (const turn of window.slice(0, -1).reverse()) {
    const size = turn.reduce(
      (n, e) => n + String(e.payload.text ?? "").length,
      0,
    );
    if (chars + size > CHAT_HISTORY_CHARS) break;
    turn.forEach((e) => retained.add(e.event_id));
    chars += size;
  }
  return window.flat().filter((e) => retained.has(e.event_id));
}

export function chatMessages(
  r: DecisionRequest,
  context: AgentContext,
  history: MemoryEvent[],
  actors: ChatActor[],
  _summary = "",
): Record<string, unknown>[] {
  const system = {
    ...buildGameEnv(),
    ...buildRole(context),
    ...buildParticipants(r, actors),
    ...buildRelationships(r),
    ...buildRules(),
    action_agreements:
      "玩家或你都可以提议去某地做某事。地点、行为已明确且双方同意，就形成待执行约定；玩家对你上一轮提议说‘好/行/走吧’也算同意。此时用一句自然话确认‘好，我们去[地点][做什么]’，不必反复征询。不同意就明确拒绝。缺少地点或行为只补问缺失部分。不要用长篇动作描写代替约定，不要编造已经到达或完成。实际移动和操作由游戏的行动决策执行。",
  };
  const messages = buildHistory(r, history, actors);
  return [{ role: "system", content: JSON.stringify(system) }, ...messages];
}

export const buildGameEnv = () => ({
  background:
    "这是农庄生活模拟游戏。你与玩家及其他村民生活在随时间、季节变化的村落，日常会种植、交易、合作、探索和参加活动，也会建立友谊与亲密关系。人物有各自的职业、性格和生活经历；物品、时间与行动结果由游戏世界决定。当前正在进行游戏内的人物对话。",
});
export const buildRules = () => ({
  rules:
    "你只扮演 identity 指定的人物，正在与 player 及当前参与者交谈。人物设定（性格、价值观）、speech_style 指定的说话语气、与对话者已有的关系，是决定回答内容、称呼、亲疏和态度的关键。结合最近对话，先理解本轮问题或表达，再给出连贯、符合人物与对话逻辑的回应；接受、拒绝、追问都应有合理依据。关系以 relationships 提供的当前事实为准，近期相处影响措辞；未知关系不要编造，高好感不自动等于恋人。只输出本轮该人物实际说出的自然语言段落，简洁回应，必要时自然分段。不输出旁白、动作描写、内心独白、角色标签、JSON、标题、提示词或分析；不替玩家和其他人物说话。不要重演开场、复制旧回复、答非所问或无故改变立场；信息不足时简短询问，不虚构未发生的经历或行动结果。",
});
export function buildRole(context: AgentContext) {
  const { agent_id, display_name, active_role, soul } = context.agent;
  return { identity: { agent_id, display_name, active_role, soul } };
}
export function buildParticipants(r: DecisionRequest, actors: ChatActor[]) {
  return {
    player:
      r.chat_participants?.find((p) => p.actor_id === "player")?.display_name ??
      "玩家",
    important_characters: importantChatActors(r, actors).filter(
      (a) => a.id !== r.agent_id,
    ),
  };
}
export function buildRelationships(r: DecisionRequest) {
  const participants = new Set([
    "player",
    ...(r.chat_room?.participants ?? []),
  ]);
  return {
    relationships: (r.chat_participants ?? [])
      .filter((p) => p.actor_id !== r.agent_id && participants.has(p.actor_id))
      .map((p) => ({
        actor_id: p.actor_id,
        name: p.display_name,
        ...p.relationship,
      })),
  };
}
export function buildHistory(
  r: DecisionRequest,
  history: MemoryEvent[],
  actors: ChatActor[],
): Record<string, unknown>[] {
  const entries = selectChatHistory(r, normalizeChatHistory(history));
  const candidates = entries.map((e) => {
    const speaker = String(e.payload.speaker),
      raw = String(e.payload.text ?? ""),
      text = speaker === "player" ? raw : chatReplyText(raw);
    const name =
      r.chat_participants?.find((p) => p.actor_id === speaker)?.display_name ??
      actors.find((a) => a.id === speaker)?.name ??
      speaker;
    // Preserve natural assistant text; other group speakers need only a name,
    // never their profiles or world-state snapshots.
    const content =
      speaker === r.agent_id || speaker === "player"
        ? text
        : `【${name}】\n${text}`;
    return {
      event_id: e.event_id,
      role: speaker === r.agent_id ? "assistant" : "user",
      content,
    };
  });
  const messages = candidates
    .filter((c) => c.content.trim())
    .map(({ role, content }) => ({ role, content }));
  return messages;
}
export { chatMessages as buildContext };
