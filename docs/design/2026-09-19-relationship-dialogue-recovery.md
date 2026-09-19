# 关系对话实时核对与错误提示

## 问题

2026-09-19 13:21 的阿禾对话中，实时查询已经返回双方好感 92、status=dating。模型仍提交 resolve_relationship_dialogue(confirm)，两次工具输出均没有对白，导致 dialogue_reply_required。界面丢弃错误类型，统一显示服务不可用。此前的关系否认只依据旧记忆，没有查询实时状态。

## 修复

- 关系类对话要求模型先发现 actors，再查询 relationship(id=player)。初始上下文不预加载关系数据，普通问候不增加查询。
- 对显式涉及恋人身份、好感和分手等话题的最终回复增加查询检查；记忆、提议列表和其他人的关系不能代替玩家与该 NPC 的实时关系。失败查询允许解释无法核实，但不能提交未核实的关系变更。
- 当前 loop 的有效关系观察单独保存，不依赖压缩后的文本；新 loop 清空，必须重新查询。
- 已经交往时重复 confirm 转为正常对白，不提交重复动作；游戏端也对当前对话里的重复确认作无副作用处理。
- 新的关系动作只有工具输出、没有对白时，补充表达意愿的回复。仍保留原始动作参数并由游戏校验，不把提议描述为已经执行。
- 3D 对话和原入口透传错误码，区分缺少回复、关系查询失败、超时、上下文容量、认证与连接问题。失败后可继续输入，过期请求不能覆盖当前对话。

## 验证

- agent-service 全量：150 项通过，1 项跳过。
- `tests/relationship_dialogue.test.ts` 重现阿禾的发现→提议查询→关系查询→重复确认序列；覆盖仅工具回复、新确认/拒绝/分手、失效查询、无关关系及跨 loop 状态刷新。
- `godot_console.exe --headless --path . --script tests/run_agent_system_tests.gd`：1749 项通过。
- `godot_console.exe --headless --path . --script tests/run_social_navigation_tests.gd -- --farm-test --living-world-scenario=P12`：79 项通过，包含重复确认不增加好感、提议、版本和事件，以及原有对话授权、确认、分手和保存恢复。

agent-service 已重启加载修改；游戏客户端脚本在重新运行游戏后加载。真实玩家存档未修改。
