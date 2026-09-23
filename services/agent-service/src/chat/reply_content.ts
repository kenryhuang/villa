// Some local models put reasoning and speech in the same content field. Parse
// only top-level reply fields, never a matching key inside a reasoning string.
// Input is cumulative: every returned streaming prefix must remain append-only.
const envelopeKeys = new Set(["thinking", "reasoning", "analysis", "decision", "response", "content", "role", "tool_calls"]);
const thinkingTags = ["think", "thinking", "analysis"];

function jsonString(source: string, start: number): { text: string; end: number; closed: boolean } | undefined {
  if (source[start] !== '"') return;
  let i = start + 1;
  for (; i < source.length; i++) {
    if (source[i] === '"') {
      try { return { text: JSON.parse(source.slice(start, i + 1)), end: i + 1, closed: true }; }
      catch { return; }
    }
    if (source[i] === "\\") {
      if (i + 1 >= source.length) break;
      if (source[i + 1] === "u") {
        if (i + 6 > source.length) break;
        i += 5;
      } else i++;
    }
  }
  try {
    // Hold an unfinished escape and a high surrogate until the next chunk.
    const text = (JSON.parse(source.slice(start, i) + '"') as string).replace(/[\uD800-\uDBFF]$/, "");
    return { text, end: i, closed: false };
  } catch { return; }
}

function skipValue(source: string, start: number): number | undefined {
  let depth = 0;
  for (let i = start; i < source.length; i++) {
    const char = source[i];
    if (char === '"') {
      const value = jsonString(source, i);
      if (!value?.closed) return;
      i = value.end - 1;
    } else if (char === "{" || char === "[") depth++;
    else if (char === "}" || char === "]") {
      if (depth === 0) return i;
      depth--;
    } else if (char === "," && depth === 0) return i;
  }
}

function envelopeReply(source: string, complete: boolean): string {
  let i = 1, recognized = false;
  const whitespace = () => { while (/\s/.test(source[i] ?? "") && i < source.length) i++; };
  while (i < source.length) {
    whitespace();
    const key = jsonString(source, i);
    if (!key?.closed) return recognized || !complete ? "" : source;
    if (!recognized) {
      // Ordinary JSON mentioned as dialogue is not a model reply envelope.
      if (!envelopeKeys.has(key.text)) return source;
      recognized = true;
    }
    i = key.end;
    whitespace();
    if (source[i++] !== ":") return "";
    whitespace();
    if (key.text === "response" || key.text === "content") {
      const value = jsonString(source, i);
      if (!value || (complete && !value.closed)) return "";
      // A closed response string is enough, even if the model omits the outer }.
      return value.text;
    }
    const end = skipValue(source, i);
    if (end === undefined || source[end] !== ",") return "";
    i = end + 1;
  }
  return recognized || !complete ? "" : source;
}

export function replyContent(raw: string, complete: boolean): string {
  let text = raw.trimStart();
  // Reasoning tags are sometimes sent in content instead of reasoning_content.
  for (;;) {
    const tag = thinkingTags.find(name => text.startsWith(`<${name}>`));
    if (!tag) break;
    const end = text.indexOf(`</${tag}>`, tag.length + 2);
    if (end < 0) return "";
    text = text.slice(end + tag.length + 3).trimStart();
  }
  if (!complete && thinkingTags.some(tag => `<${tag}>`.startsWith(text))) return "";
  // Hold the opening fence until its language is known. Only JSON wrappers are
  // removed; a code block quoted in ordinary dialogue retains its formatting.
  if (text.startsWith("```")) {
    const newline = text.indexOf("\n");
    if (newline < 0) return complete ? text : "";
    const language = text.slice(3, newline).trim().toLowerCase();
    const body = text.slice(newline + 1).trimStart();
    if (!complete && language === "" && !body) return "";
    if (language === "json" || language === "" && body.startsWith("{")) text = body;
  } else if (!complete && "```".startsWith(text)) return "";
  return text.startsWith("{") ? envelopeReply(text, complete) : text;
}
