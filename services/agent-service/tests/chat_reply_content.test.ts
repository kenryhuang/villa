import test from "node:test";
import assert from "node:assert/strict";
import { chatReplyText } from "../src/chat_reply.ts";

const answer = '好，我们去南湖。\n\n带上“水壶”和一张地图 🗺️。';
const envelope = JSON.stringify({
  thinking: ['内部分析', '字符串里的 "response":"假答案"', { response: "嵌套假答案" }],
  decision: ["内部决策"],
  response: answer,
});

function assertStream(raw: string, expected: string) {
  let previous = "";
  for (let i = 1; i <= raw.length; i++) {
    const shown = chatReplyText(raw.slice(0, i), false);
    assert.ok(expected.startsWith(shown), `leaked content at ${i}: ${JSON.stringify(shown)}`);
    assert.ok(shown.startsWith(previous), `retracted content at ${i}`);
    assert.ok(!/[\uD800-\uDBFF]$/.test(shown), `split surrogate at ${i}`);
    previous = shown;
  }
  assert.equal(chatReplyText(raw), expected);
}

test("only response streams from reasoning envelopes, including a missing outer closing brace", () => {
  for (const raw of [envelope, envelope.slice(0, -1), '```json\n' + envelope + '\n```', '```\n' + envelope + '\n```',
    JSON.stringify({ response: answer, thinking: "hidden after reply" })]) {
    assertStream(raw, answer);
    const start = raw.indexOf('"response":' + JSON.stringify(answer));
    assert.ok(chatReplyText(raw.slice(0, start + '"response":"好，我们'.length), false).length > 0,
      "must stream before the response string or envelope closes");
  }
});

test("JSON escapes are decoded only when complete, including Unicode pairs and quotes", () => {
  assertStream('{"thinking":null,"decision":{"x":[true,42]},"response":"你好\\n\\n\\u4e16\\u754c \\ud83d\\ude42 \\"好\\" \\\\ /"}',
    '你好\n\n世界 🙂 "好" \\ /');
});

test("thinking tags and their incomplete chunks never enter dialogue", () => {
  for (const tag of ["think", "thinking", "analysis"]) {
    assertStream(`<${tag}>内部推理\n另一行</${tag}>\n${envelope}`, answer);
    assertStream(`<${tag}>内部推理</${tag}>${answer}`, answer);
    assert.equal(chatReplyText(`<${tag}>没有结束的分析`), "");
  }
});

test("missing or non-string responses never fall back to displaying the raw envelope", () => {
  for (const raw of ['{"thinking":["secret"]}', '{"thinking":', '{"response":null}',
    '{"response":{"thinking":"secret"}}', '```json\n{"decision":["secret"]}\n```']) {
    assertStream(raw, "");
  }
});

test("ordinary text and non-reply JSON stay intact", () => {
  for (const text of ['你好，我们去南湖。', '{"price":20}', '价格 < 20，明白吗？']) {
    assertStream(text, text);
  }
});
