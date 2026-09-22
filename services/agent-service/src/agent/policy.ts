import type { DecisionRequest } from "../protocol.ts";

export function buildRules(
  request: DecisionRequest,
  actionLimit: number,
  inline: boolean,
): Record<string, unknown> {
  const rules =
    `按人格和目标决策，最多${actionLimit}个行动。查询真实状态、价格、权限和资源，不猜测对象ID或完成结果。` +
    (inline
      ? "工具按返回顺序逐条执行，结果会回填。根据真实回执反省并修正；此前已成功的行动不可重复。"
      : "只读与行动不能混批；最终提交有序行动，由游戏执行。") +
    "没有进一步操作时直接结束。异步行为完成才可续行。";
  const dialogue_handoff_rules =
    "优先处理 confirmed_dialogue 与 dialogue_followups 中的约定和目标。仅双方确认才代表约定；提议、问题、传闻不能当同意或事实。" +
    "较新修改/取消优先。通过工具核实人物、地点、活动和交易条件；保留‘到哪里做什么’，不能只移动而丢掉活动。" +
    "旧 handoff_version=1 使用 payload.handoffs，price/gold=0 代表价格未定。place_id 可能是建筑ID，地图未命中时查询 buildings/detail。" +
    "问候、拒绝、假设和玩家单方面请求无需动作。可执行步骤本轮返回具体动作工具调用；多步或受阻计划用短期目标保存来源、限制、完成条件和复核时间。只有真实完成回执证明成功。";
  if (request.trigger !== "dialogue") return { rules, dialogue_handoff_rules };
  // Only old embedders use the single-model dialogue route. The server uses chat/loop.ts.
  return {
    rules,
    dialogue_handoff_rules:
      dialogue_handoff_rules +
      "明确同意稍后行动时用 adopt_short_term_goal，来源为 turn.dialogue_event_id，review_in_minutes=1。",
    dialogue_rules:
      "当前玩家消息是本轮任务，用一至三句自然回复。问候无需工具；不要在对话中自主种植、收获、投机或探索。工具行动仍须给出回复，未执行的只描述为计划。",
    relationship_rules:
      "先查询 actors/relationship/player 核实关系；实时 status/affinity 优先于记忆和旧对白。dating 表示已是恋人，不重复确认；读取失败不猜测。只有本轮新的双方明确意愿才改变关系。",
  };
}
