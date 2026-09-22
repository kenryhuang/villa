const bytes = (value: unknown) =>
  new TextEncoder().encode(JSON.stringify(value)).length;

/** Keep whole intents and provenance. Oversized entries are references, never cut facts. */
export function selectDialogueContext(
  entries: Record<string, unknown>[],
  limit = 12000,
): Record<string, unknown>[] {
  const selected: Record<string, unknown>[] = [];
  let size = 0;
  for (const entry of entries) {
    const candidate = bytes(entry);
    if (size + candidate <= limit) {
      selected.push(entry);
      size += candidate;
    } else {
      selected.push({
        event_id: entry.event_id,
        game_minute: entry.game_minute,
        source: entry.source,
        details_available: true,
        instruction:
          "Use inspect_event with event_id before acting on or consuming this dialogue intent.",
      });
    }
  }
  return selected;
}
