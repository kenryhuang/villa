type RecordValue = Record<string, unknown>;
const object = (value: unknown): RecordValue => value && typeof value === "object" && !Array.isArray(value) ? value as RecordValue : {};
const size = (value: unknown) => new TextEncoder().encode(JSON.stringify(value)).length;
// Historical ledgers do not belong in a current action quote. Never truncate a
// price, identifier, prerequisite, result or arbitrary nested string into a fact.
const BULK_HISTORY = new Set(["service_records", "price_history", "event_history", "history_segments"]);
function currentFacts(value: unknown, omitted: string[], path = ""): unknown {
  if (Array.isArray(value)) return value.map((v, i) => currentFacts(v, omitted, `${path}[${i}]`));
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(Object.entries(value).flatMap(([k, v]) => {
    const field = path ? `${path}.${k}` : k;
    if (BULK_HISTORY.has(k)) { omitted.push(field); return []; }
    return [[k, currentFacts(v, omitted, field)]];
  }));
}

export function compactWorkingMessages(messages: RecordValue[], target = 16000): RecordValue[] {
  const facts: RecordValue[] = [], constraints: unknown[] = [], previousMissing: unknown[] = [];
  const calls = new Map<string, RecordValue>();
  for (const message of messages.slice(2)) {
    if (message.role === "assistant" && Array.isArray(message.tool_calls)) {
      for (const raw of message.tool_calls) {
        const call = object(raw), fn = object(call.function);
        try { calls.set(String(call.id), object(JSON.parse(String(fn.arguments)))); } catch { /* no fabricated query */ }
      }
    }
    let value: RecordValue;
    try { value = object(JSON.parse(String(message.content))); }
    catch { if (message.role === "system") constraints.push(message.content); continue; }
    if (message.role === "system") {
      const previous = object(value.continuation_summary);
      if (Array.isArray(previous.observations)) facts.push(...previous.observations.map(object));
      if (Array.isArray(previous.constraints)) constraints.push(...previous.constraints);
      if (Array.isArray(previous.missing_details)) previousMissing.push(...previous.missing_details);
    } else if (message.role === "tool") {
      const omitted: string[] = [];
      facts.push({tool: message.name, query: calls.get(String(message.tool_call_id)) ?? {},
        observation_id: value.observation_id, observed_game_minute: value.observed_game_minute,
        domain_revision: value.domain_revision, facts: currentFacts(value, omitted), omitted_fields: omitted});
    }
  }
  // Supersede repeated reads of the same query; never replace a newer quote
  // with an older one during a second compaction. Pagination remains distinct.
  const latest = new Map<string, RecordValue>();
  for (const fact of facts) {
    const query = object(fact.query);
    const key = JSON.stringify([fact.tool, Object.keys(query).length ? Object.entries(query).sort(([a],[b]) => a.localeCompare(b)) : fact.observation_id]);
    latest.delete(key); latest.set(key, fact);
  }
  const priority = (fact: RecordValue) => {
    const query = object(fact.query), value = object(fact.facts);
    return value.ok === false || ["detail", "quote", "activity", "rules"].includes(String(query.section)) ? 2 : fact.tool === "discover_tools" ? 0 : 1;
  };
  const candidates = [...latest.values()].reverse().sort((a,b) => priority(b) - priority(a));
  const observations: RecordValue[] = [], missing_details: unknown[] = [...previousMissing].slice(-6);
  const summary = {rule: "Facts are observations, not reservations/completion. Use current resources. Missing/stale action facts require refresh; never assume zero; wait if reads exhausted.",
    observations, missing_details, constraints: [...new Set(constraints)].slice(-4)};
  const build = () => [...messages.slice(0,2), {role: "system", content: JSON.stringify({continuation_summary: summary})}];
  // Reserve space for explicit omissions. Keep/drop whole observations, never
  // cut JSON or retain an ID while silently dropping its attached quote.
  for (const fact of candidates) {
    observations.push(fact);
    if (size(build()) > target - Math.min(1000, Math.max(0, (target - size(messages.slice(0,2))) / 4))) {
      observations.pop();
      missing_details.push({tool: fact.tool, query: fact.query, observation_id: fact.observation_id, reason: "capacity; refresh before action"});
      if (missing_details.length > 6) missing_details.shift();
    }
  }
  while (missing_details.length && size(build()) > target) missing_details.shift();
  while (summary.constraints.length && size(build()) > target) summary.constraints.shift();
  return build();
}
