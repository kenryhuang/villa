# Agent service：两条 loop 与上下文

正式入口是 `server.ts → app.ts`。`app.ts` 负责协议、缓存、SSE 和取消；业务分别进入 `agent/service.ts` 和 `chat/loop.ts`。新客户端通过 `tool_execution: "inline"` 启用逐条执行。旧文件保留导出兼容，旧客户端的终结批次执行位于 `agent/legacy_loop.ts`。

## 行动 loop

```text
Godot 定时/事件/目标复核
  → v3 请求：资源、增量经历、角色能力、短期目标
  → agent/service：同步经历、检索记忆、读取待处理对话意图
  → agent/build_context：逐块构造固定上下文
  → agent/loop：
      更新工具菜单和剩余预算
      检查/压缩工作上下文
      调用行动模型
      没有 tool calls → 返回 final
      有 tool calls → 逐条执行 → 回填结果 → 再次调用模型
  → final 不重复携带已经执行的动作
```

`build_context.ts` 的块分别由 `buildGameEnv`、`buildRole`、`buildResources`、`buildExperience`、`buildMemory`、`buildGoals`、`buildConfirmedDialogue`、`buildTools` 和 `policy.buildRules` 构造。固定开头包含 system 游戏说明与 user JSON；工具 schema 作为独立 `tools` 参数发送。

`execute_tools.ts` 按 LLM 给出的顺序执行一个回合中的调用。读取与行动都可一次返回多个；没有发现/启用的工具不能执行。世界查询发 `read.request`，行动发 `action.request`。Godot 执行前验证权限、参数和实时条件，异步行动必须收到终态回执才继续下一条；轮询、心跳或 `in_progress` 都不算完成。

每批追加原始 `assistant.tool_calls`、逐条 `role=tool` 结果，以及可读的 assistant `execution_results`。保留 `tool_call_id` 是 OpenAI 兼容协议的要求。读取异常、参数错误和游戏执行失败都会进入结果，供模型自行修正；不把执行异常伪装成成功。权限越界终止。通信异常可能意味着已开始执行，因此不盲目重放未知结果。

动作 ID/幂等键由请求与步数确定；服务端保存派发日志，重试不能用同一个键执行不同命令。Godot 继续使用原有幂等执行器。流中断后已发生的效果保留，正在运行的动作继续被跟踪；新的后台决策等执行结束后才能开始。

## 聊天 loop

```text
当前玩家发言
  → 保存当前 room 的 ChatMessage
  → chat/build_context：游戏背景、对话规则、角色与语气、人物关系、最近5轮
  → chat/provider.reply：流式回复
  → 保存回复与 ChatIntentPending
  → 立即返回 decision.final

后台 chat/intent_worker
  → 只读取该轮玩家消息和该 NPC 最后回复
  → 使用 chat LLM 做 JSON 意图提取
  → 校验本轮原文证据和字段
  → 保存 ChatIntentExtracted，完成原任务
  → 下一次行动 loop 从数据库取出
```

聊天模型可单独配置；不配置 `chat_provider` 时复用 `provider` 的模型配置，但仍走独立聊天 loop。`chat/context_window.ts` 只保留最近5轮（当前玩家轮 + 前4轮），一条玩家发言及其后各 NPC 的回复算一轮，按插入顺序排列。另有6000字符上限，超过时整轮移出更早对话，当前玩家消息必保留。原始记录仍存档，但不再生成或注入旧聊天摘要，避免小模型上下文过长。意图提取仍只使用最近一轮。

系统提示词明确农庄游戏背景和当前人物对话任务，要求回答依据人物性格、价值观、语气及与对话者已有的关系，保持本轮逻辑连贯，只输出该人物说出的自然语言段落，不输出旁白、动作描写或内心独白。`buildRelationships` 带入游戏传来的参与者关系状态、称呼与好感，不复制其他人物的完整设定，也不凭好感虚构恋爱身份。

`chat/reply_history.ts` 处理本地模型逐轮复制整段旧回复的问题：构造历史时，仅移除同一 NPC 完整、逐字匹配、至少 40 字且以换行分隔的旧回复前缀，原始存档不改写。接收流式输出时也检查这些前缀，避免旧段落出现在面板、回写历史或进入意图提取。完全复制旧回复而没有新增内容时报告生成失败；简短寒暄、段落内引用和非完整匹配保留。原始模型输出仍保存在调试 trace，移除操作记录为 `chat.history_echo_removed`。

意图类型：出行/邀请、活动、交易、信息请求、获得的信息、关系意愿。状态明确区分 `confirmed`、`proposed`、`requested`、`cancelled`、`stated`。只有已确认约定表示双方同意，信息陈述仍需核实；价格/数量未知使用 null。地点、人物和物品保留原名称，下一次行动模型通过工具解析实际 ID。

队列使用 SQLite 事件持久化；后台抽取不依赖已关闭的聊天 SSE。连接/超时等暂时故障30秒后重试，最多3次失败；字段/证据/JSON校验失败及预算耗尽终止自动重试，原始任务和失败诊断仍保留。每5秒检查队列，前台请求也会唤醒队列。前台回复优先于后台抽取，模型调用仍受超时、并发和每日预算限制。

调试窗口打开时每2秒通过 `POST /v1/chat/intent-trace` 读取当前选中聊天的异步提取状态，按存档、角色、请求ID和epoch隔离。`ChatIntentTrace` 保存准备的messages、实际provider.input、原始provider.output、校验结果和时序；`ChatIntentError` 保存错误及是否重试。窗口的“行动指示”页显示原始聊天、prompt/messages、模型原始结果和字段级校验错误；调用下拉框也可切换至“异步意图提取”。成功、空数组、排队、重试、失败分开显示，聊天stream完成不再意味着提取已完成。旧版本没有保存的实际请求/输出不会用当前模板伪造。当前完整提示词见 [intent-extraction-prompt.md](intent-extraction-prompt.md)。

待处理意图取最早 8 条；积压时额外显示最新一条，防止旧计划盖过最新取消。额外条目标记 `context_only`，不提前消费。固定上下文对完整意图使用约 12000 UTF-8 字节预算；容纳不下的条目保留来源引用，必须 `inspect_event` 取全文后才可消费。新结果在运行过程中到达，不会被当前 loop 一并确认。

关系意愿也走异步意图链路。它本身不修改恋人状态：行动工具仍必须通过游戏现有的真实关系与同意验证，不会凭提取文本授予权限。

## 预算

- `budget/loop_budget.ts`：读取回合、读取次数、行动尝试、模型总回合上限。默认 6/12/3；错误不会退回预算。公共协调者行动上限为 1。
- `budget/context_budget.ts`：消息与工具 schema 的容量。保留固定头部，压缩工作观察；48000/32000/64000 是 UTF-8 字节保守估计，不是 tokenizer 的精确 token 数。
- `budget/provider_budget.ts`：每存档每游戏日最多预留 8000000 单位；请求字节、输出上限和模板余量都在实际发起调用前计入。行动与聊天分别落盘，重启不重置。同一模型配置也保留两条通道各自的账本。
- `provider_concurrency_gate.ts`：并发、前台优先和抢占。超时/取消由调用方贯穿模型及工具等待。
- Godot `agent_scheduler.gd`：游戏侧每日请求次数、对话/后台并发、角色调度间隔；与一次请求内部模型调用预算不同。

## 角色记忆

`memory.ts` 是持久层，`memory/service.ts` 负责抽取与组装。所有读取按 session 和 actor 隔离：行动记录放 `action.v2:<actor>`，聊天按 room，核心记忆放对应 actor 的 core scope。

每个行动上下文包含最多 5 条核心记忆、最近 15 条经历、旧历史摘要，以及按本轮目标/事件/对话意图检索出的最多 6 条相关记忆。重要事件由行动模型后台抽取，重要度至少 8 的摘要写入核心记忆；来源事件必须存在。核心记忆支持同一 key 的新版覆盖，原始来源和版本仍保存。检索采用词项与中文双字匹配，不是向量检索。

压缩工作消息不等于持久记忆抽取。前者是当前 loop 内的代码整理；后者调用模型并保存为后续 loop 可用的记忆。异步结果提交前复核来源未被存档恢复改变。队列、核心记忆、摘要和事件随原有 checkpoint 导入导出，不需要新数据库表迁移。

## 验证

在 `services/agent-service` 执行：

```powershell
npm run typecheck
npm test
$env:RUN_GODOT_LOOP_TEST = '1'
node --experimental-strip-types --test tests/agent_loop_godot.test.ts
Remove-Item Env:RUN_GODOT_LOOP_TEST
```

最后一项通过本地脚本模型和真实 Godot 验证 SSE 查询、执行、回执回填，不调用付费模型。游戏侧回归在项目根目录执行 `godot_console.exe --headless --path . --script tests/run_agent_loop_tests.gd -- --farm-test`。
