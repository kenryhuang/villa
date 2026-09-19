// Observations are scoped to one loop and come only from its live world reads.
// Historical memories must never stand in for current relationship state.
export class RelationshipDialogue {
  attempted = false;
  player?: Record<string, unknown>;

  observe(name: string, args: Record<string, unknown>, result: Record<string, unknown>): void {
    if (name !== "query_world" || args.domain !== "actors" || !["relationship", "relationships"].includes(String(args.section))) return;
    const exactPlayer = args.section === "relationship" && args.id === "player";
    const rows = Array.isArray(result.items) ? result.items : [result.data];
    const player = rows.find(row => row && typeof row === "object" && row.actor_id === "player");
    if (exactPlayer || player) {
      this.attempted = true;
      // A failed fresh read invalidates an earlier observation of this pair.
      this.player = result.ok === true && player && ["none", "dating", "former_partners"].includes(player.status) ? player : undefined;
    }
  }
}

export function asksRelationshipState(text: string): boolean {
  return /(?:男朋友|女朋友|恋人|好感|恋爱|情侣|交往关系|确认关系|确定关系|关系状态|感情状态|分手|\b(?:boyfriend|girlfriend|dating|romantic|affection|relationship status)\b)/i.test(text);
}

export function pendingRelationshipReply(name: string, args: Record<string, unknown>): string | undefined {
  if (name !== "resolve_relationship_dialogue") return undefined;
  switch (args.decision) {
    case "confirm": return "我也愿意认真和你交往，我们来确认彼此的心意吧。";
    case "decline": return "关于确定恋人关系这件事，我尊重彼此的意愿，我们先不走这一步。";
    case "end": return "我听到了你的分手想法，也尊重你的决定。";
    default: return undefined;
  }
}
