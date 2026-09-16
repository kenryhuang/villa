# Agent Streaming 长时间等待修复

## 现场证据

本地 trace 配置实际写入 `tmp/`。会话 `farm3d-65b6a891c34a0-106ea00f19c-1789362985-4052681.ndjson` 中，老李的一次决策完成 6 轮模型调用，用时约 259 秒；关闭游戏时，铁匠请求已等待 457 秒、阿水 384 秒、老李的新请求 252 秒（该请求尚无完整 provider round）。服务 `/health` 正常，不能据此判断某个模型请求正常推进。

原实现存在以下等待和诊断缺口：

- `provider.input` 在获得并发名额前发出，因此看到 input 不代表已发给上游。
- 180 秒上游超时从取得名额后开始计时；多轮 Loop 和排队没有总时限。
- 每 5 秒 SSE 心跳持续刷新客户端 60 秒空闲超时，客户端不能区分“连接活着”和“模型在推进”。
- 记忆压缩与决策共享优先级和并发池，且非流式记忆请求未明确关闭 thinking。

这些证据说明等待确实超过了用户可接受的范围；旧日志没有每次排队/首条输出的时间，不能反推所有等待分别发生在哪一阶段。

## 修改

- v3 整个 Loop 使用可配置 `provider.loop_timeout_ms`（默认 180,000），覆盖排队、每轮模型请求和工具回传；超时中断，返回 `agent_loop_timeout`。
- 新增 `provider.stream_idle_timeout_ms`（默认 45,000），约束首条输出和后续有效 delta 间隔；心跳与空元数据不续期。超时返回 `provider_stream_idle_timeout`，不提交半成品行动。
- 输入事件在实际拿到名额后发出；`provider.status` 区分 queued、waiting_provider、receiving、round_completed，含轮数及时间。每轮记录实际排队时长。
- 记忆处理使用 maintenance 优先级，最多同时执行一个。决策优先，单名额时可取消当前记忆调用并在稍后重试；原始记忆事件仍持久保留。
- SSE 解码在 DONE、异常或调用者退出时取消并解锁 reader，避免 HTTP body 未关闭而长期持有连接。
- 调试面板展示当前阶段及 Loop 事件，滚动位置恢复限定在当前文本范围内。
- 联调时发现市场查询 `merchant_live` 的动态类型推断导致 Godot 编译失败，增加明确 bool 类型，保留查询行为。

不更改私人配置、模型或 API key；旧配置自动采用新增默认值。游戏中的旧调试面板需要重新运行场景才能加载 UI 修改。

## 验证

新增回归覆盖心跳不断但模型无输出、持续输出突破总时限、超时后后续请求可以继续、记忆积压不占满决策名额、单名额抢占和恢复，以及 DONE 后上游仍不关闭 HTTP 的清理。

Agent Service 113 项、Godot Agent 1,719 项、Agent Loop 106 项通过。日志：`tmp/agent-refactor/stream-stall-service2.log`、`stream-stall-godot.log`、`stream-stall-loop2.log`。

使用现有配置重启服务后，在独立 P1 测试场景调用真实模型，阿禾、老李、林先生三次对话分别约 1.41、1.76、1.32 秒完成，均实际呈现在对话框中。日志 `tmp/agent-refactor/stream-stall-live2.log`。未修改玩家正式存档；该短测不代表所有自主探索循环都具有同样延迟。
