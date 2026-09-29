# zewei → flower_girl 改名补全 + 旧存档迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 补全未提交的 zewei→flower_girl id 改名（数据已改、代码未改），新增旧存档 id 迁移，恢复用户 9/23 的农场进度，让该 NPC 可对话且 agent loop 正常调度。

**Architecture:** 三层修复：(1) 数据层——`residents.json` 的 `focus_actors` 残留 `"zewei"` 改为 `"flower_girl"`（这是"无法对话+loop不调度"的直接根因：可见 NPC 由 focus 名单生成，过期 id 过不了 `registry.is_agent_managed`，而 flower_girl 不在名单则被决策调度跳过）；(2) 代码层——`npc.gd` 模型映射键改名，`farm_session.gd` 新增 `_migrate_rename_zewei`（递归重写存档中所有 id token，保留 `name`/`display_name` 显示字段），并把现有"向 36 人老存档添加新居民"的 `_migrate_zewei` 重定向为 flower_girl；(3) 恢复层——把 `.bak`（旧进度，含 531 处 zewei）复制回 `farm_3d_save.json`，由加载时迁移自动改写并通过 `_valid_save`。

**Tech Stack:** Godot 4.7 GDScript（headless 测试 `tests/run_zewei_npc_tests.gd`，需 `-- --farm-test --living-world-scenario=P12`）、Node agent-service（`npm test`，`tests/zewei.test.ts`）、Python 仅用于验证脚本。

**背景事实（执行者无需重新调查）：**
- 服务注册表（来自 `data/agents/profiles.json`）只有 `flower_girl`，无 `zewei`（已用 `/v1/chat/intent-trace` 探测证实：flower_girl→200，zewei→400）。agent 服务无需重启。
- `data/farm_3d_save.json.pre-rename-protected.bak`（1.4MB）= 旧进度安全副本；`data/farm_3d_save.json.fresh-20260924` = 当前全新农场副本。均已在计划前创建。
- `.bak` 中 `zewei` 全部作为完整 token 出现（`:`/`-`/`|`/引号定界），分布在 `agents.loop_state.event_queue`(195)、`agents.executor.outcomes`(78)、`agents.loop_state.loops`(33)、`living_world.work.*`(64)、`agents.activities`(21)、`society.ledger`(18)、`society.residents`(2) 等；`npc_economy` 与 `buildings` 无命中。
- 显示名保持 "zewei"：`profiles.json` 的 `display_name`、`residents.json` 的 `name`、存档内 `residents.*.name` 都不改。
- `chat_summary.test.ts` 中 "zewei" 是任意 fixture id（不查注册表），不改。
- 已知基线失败（与本改动无关，勿修）：`run_economy_system_tests.gd` 12 个；`run_agent_loop_tests.gd` 的 "Isolated 3D fixture"。
- 用户未要求 commit；全部改动留在工作区，最后询问用户是否提交。

---

### Task 1: 数据与模型映射修复（focus_actors + npc.gd）

**Files:**
- Modify: `data/living_world/residents.json:102`（`focus_actors` 数组内 `"zewei"` → `"flower_girl"`）
- Modify: `scripts/actors/npc.gd:31`（模型映射键 `"zewei"` → `"flower_girl"`）

- [ ] **Step 1: 改 residents.json focus_actors**

把：
```json
    "resident_shan",
    "zewei"
  ],
```
改为：
```json
    "resident_shan",
    "flower_girl"
  ],
```

- [ ] **Step 2: 改 npc.gd 模型映射键**

把：
```gdscript
	"zewei": "res://assets/models/characters/young_woman_cardigan.glb",
```
改为：
```gdscript
	"flower_girl": "res://assets/models/characters/young_woman_cardigan.glb",
```

- [ ] **Step 3: 验证无残留 id 引用**

Run: `cd /d/UnityProject/villa && grep -rn '"zewei"' data/living_world/ scripts/ | grep -v farm_3d_save | grep -v farm_session.gd`
Expected: 仅剩 Task 2/3 尚未处理的测试文件命中（`tests/` 不在此 grep 范围内，故应无输出）。`farm_session.gd` 的 `"zewei"` 字面量在 Task 3 处理，此处显式排除。
另验证显示名保留：`grep -n '"name": "zewei"' data/living_world/residents.json` 应仍有 1 处命中（第 244 行附近）。

---

### Task 2: 更新 Godot 测试（TDD 失败测试先行）

**Files:**
- Modify: `tests/run_zewei_npc_tests.gd`（全文 30 处 "zewei"，按下述规则替换 + 新增迁移测试块）

- [ ] **Step 1: 机械替换 id 引用（保留显示名断言）**

替换规则（`run()` 与 `capture()` 内）：
- 所有作为 **agent id** 的 `"zewei"` → `"flower_girl"`：第 28/30/39/44/45/46/47/49/55/56/57/59/60/61/62/75/85/86 行的参数、`emitted == [...]`、`filter(...)`、`erase(...)`、`has(...)`、`actor(...)`、`set_focus(...)`、`not in w.society.focus`。
- **保留** 显示名断言不动：第 29 行 `profile.display_name == "zewei"`、第 32 行 `npc.nameplate.text == "zewei"`。
- 第 24 行存档路径改为 `s.save_path = "user://flower_girl_npc_integration_test.json"`。
- 第 7 行超时消息改为 `push_error("Flower girl (zewei) integration timeout")`。
- 第 66/69/73/80 行 `s._migrate_zewei(...)` → `s._migrate_flower_girl(...)`（Task 3 才实现该改名，此时测试会失败——预期）。
- 第 87 行输出前缀改为 `print("FLOWER_GIRL: %d checks, %d failures" % [checks, failures])`。

替换后关键行示例（第 26-32 行）：
```gdscript
	check(w.society.residents.size() == 37 and r.registry.get_agent_ids().size() == 37, "37 residents and agents registered")
	check(w.society.focus.size() == 9 and r.farm3d_actors.size() == 9, "Flower girl added without displacing existing visible NPCs")
	var profile: Dictionary = w.character_profile("flower_girl")
	check(profile.display_name == "zewei" and profile.soul.social_profile.age == 22 and profile.soul.social_profile.gender == "female", "Adult female identity and authored personality")
	var npc: Node3D = w.actor("flower_girl")
	check(npc != null and npc.character_model != null and npc.character_animation != null, "Reference model with animations loaded")
	check(npc.nameplate.visible and npc.nameplate.text == "zewei" and not npc.placeholder_mesh.visible, "Visible nameplate and no placeholder body")
```

- [ ] **Step 2: 在第 52 行 `check(s._valid_save(saved), "New expanded save validates")` 之后插入改名迁移测试块**

```gdscript
	# Reverse-project the snapshot into the pre-rename "zewei" id space and
	# verify the rename migration rewrites every id token while keeping the
	# authored display name.
	var zewei_legacy: Dictionary = JSON.parse_string(JSON.stringify(saved).replace("flower_girl", "zewei"))
	check(zewei_legacy.living_world.society.residents.has("zewei"), "Fixture projects back to legacy zewei ids")
	s._migrate_rename_zewei(zewei_legacy)
	check(zewei_legacy.living_world.society.residents.has("flower_girl") and not zewei_legacy.living_world.society.residents.has("zewei"), "Rename migration moves the resident key to flower_girl")
	check(str(zewei_legacy.living_world.society.residents.flower_girl.name) == "zewei", "Authored display name survives the rename")
	check(zewei_legacy.living_world.society.focus.has("flower_girl") and not zewei_legacy.living_world.society.focus.has("zewei"), "Focus list follows the rename")
	check(s._valid_save(zewei_legacy), "Renamed legacy save validates against renamed config")
	var rename_once: Dictionary = zewei_legacy.duplicate(true)
	s._migrate_rename_zewei(zewei_legacy)
	check(zewei_legacy == rename_once, "Rename migration is idempotent")
	check(s.restore_save_data(zewei_legacy.duplicate(true), false) and w.actor("flower_girl") != null, "Renamed legacy save restores visible flower_girl")
```

- [ ] **Step 3: 真实存档只读验证块（原第 77-82 行）加入改名迁移**

把：
```gdscript
		s._migrate_zewei(actual)
```
改为：
```gdscript
		s._migrate_rename_zewei(actual)
		s._migrate_flower_girl(actual)
```
（其余 `original_text` 不变断言保留——迁移只作用于内存副本。）

- [ ] **Step 4: 运行测试，确认失败（红）**

Run: `cd /d/UnityProject/villa && godot --headless --path . --script tests/run_zewei_npc_tests.gd -- --farm-test --living-world-scenario=P12`
Expected: FAIL —— `_migrate_rename_zewei`/`_migrate_flower_girl` 方法不存在导致脚本错误，或断言失败。这是 TDD 的红灯，属预期。

---

### Task 3: farm_session.gd 实现迁移（绿灯）

**Files:**
- Modify: `scripts/farm3d/farm_session.gd`（`restore_save_data` 调用点约 320-321 行；`_migrate_zewei` 函数 779-841 行）

- [ ] **Step 1: 在 `_migrate_zewei`（将改名）之前新增改名迁移函数**

```gdscript
const _RENAME_KEEP_DISPLAY_KEYS := ["name", "display_name"]

func _migrate_rename_zewei(value: Variant) -> void:
	# One-time id rename: saves authored before the rename reference the
	# resident as "zewei"; config, registry and focus now use "flower_girl".
	# Rewrite every id token (dictionary keys and string values) so all
	# cross-references stay mutually consistent, but keep authored display
	# fields showing "zewei". Never relax validation of a damaged snapshot.
	if not value is Dictionary: return
	var residents: Variant = value.get("living_world", {}).get("society", {}).get("residents")
	if not residents is Dictionary or not (residents as Dictionary).has("zewei"): return
	var migrated: Dictionary = _rename_agent_id_refs(value, "")
	value.clear(); value.merge(migrated)

func _rename_agent_id_refs(value: Variant, key: String) -> Variant:
	if value is Dictionary:
		var out := {}
		for k in value:
			out[str(k).replace("zewei", "flower_girl")] = _rename_agent_id_refs(value[k], str(k))
		return out
	if value is Array:
		var out_arr := []
		for item in value:
			out_arr.append(_rename_agent_id_refs(item, key))
		return out_arr
	if value is String and not _RENAME_KEEP_DISPLAY_KEYS.has(key):
		return str(value).replace("zewei", "flower_girl")
	return value
```

说明：存档来自 `JSON.parse_string`，所有 Dictionary 键必为 String，`str(k)` 安全；`value.clear()+merge()` 沿用 `_migrate_zewei` 的原地替换模式，调用方持有的引用保持有效。

- [ ] **Step 2: 将 `_migrate_zewei` 改名为 `_migrate_flower_girl` 并重定向全部 id 字面量**

对函数体（779-841 行）做替换：函数名 `_migrate_zewei` → `_migrate_flower_girl`；注释首行改为 `# Add this authored resident (flower_girl, display name "zewei") once to the previous expanded roster.`；所有 `"zewei"` 字面量 → `"flower_girl"`，共 15 处：
`saved_residents.has(...)`、`old_registry._agents.erase(...)`、`old_config.residents` 的 filter、`old_config.focus_actors.erase(...)`、`npc_economy._profiles.erase(...)`、`npc_economy._states.erase(...)`、`_base_actor_profiles` 的 filter、`economy_profiles().filter(...)[0]`、`npc_states.append({"npc_id": ...})`、`living_world.society.residents.flower_girl`（属性访问）、`original_config.residents.filter(...)[0].spawn`、`Needs.initial(...)`、`society.residents.flower_girl = resident`、`society.focus.append(...)`、`society.feeding.queue.append(...)`、ledger 的 `actor_id` 与 `source: "flower_girl一次性移入初始资源"`。

- [ ] **Step 3: 更新 `restore_save_data` 调用点（约 320-321 行）**

把：
```gdscript
	_migrate_zewei(parsed)
```
改为：
```gdscript
	_migrate_rename_zewei(parsed)
	_migrate_flower_girl(parsed)
```
顺序关键：先改名（37 人含 zewei 的存档 → flower_girl，随后 `_migrate_flower_girl` 因 `has("flower_girl")` 提前返回），再补人（36 人无 zewei 的老存档 → 新增 flower_girl）。

- [ ] **Step 4: 运行测试，确认通过（绿）**

Run: `cd /d/UnityProject/villa && godot --headless --path . --script tests/run_zewei_npc_tests.gd -- --farm-test --living-world-scenario=P12`
Expected: `FLOWER_GIRL: N checks, 0 failures`，退出码 0。

- [ ] **Step 5: 跑相关守护套件防回归**

Run: `cd /d/UnityProject/villa && godot --headless --path . --script tests/run_agent_loop_tests.gd`
Expected: 除已知基线失败（"Isolated 3D fixture"）外无新增失败。

---

### Task 4: 服务端测试更新

**Files:**
- Modify: `services/agent-service/tests/zewei.test.ts`

- [ ] **Step 1: 更新注册表断言**

把第 6-11 行与第 21 行：
```ts
test("zewei is an authored adult Agent using the shared game identity and tools", () => {
  const registry = AgentRegistry.loadDefault();
  const profile = registry.get("zewei");
  assert.ok(profile);
  assert.equal(profile.display_name, "zewei");
  assert.equal(profile.npc_id, "zewei");
```
改为：
```ts
test("flower_girl (display name zewei) is an authored adult Agent using the shared game identity and tools", () => {
  const registry = AgentRegistry.loadDefault();
  const profile = registry.get("flower_girl");
  assert.ok(profile);
  assert.equal(profile.display_name, "zewei");
  assert.equal(profile.npc_id, "flower_girl");
```
第 21 行：
```ts
  assert.deepEqual(profile.soul.social_profile, social.actors.zewei);
```
改为：
```ts
  assert.deepEqual(profile.soul.social_profile, social.actors.flower_girl);
```
其余断言（role/age/gender/traits/tools、resident_yun 与 farmer_ahe 存在性）不变。

- [ ] **Step 2: 运行服务端测试**

Run: `cd /d/UnityProject/villa/services/agent-service && npm test`
Expected: 全部通过（含更新后的 zewei.test.ts）。

---

### Task 5: 恢复旧存档并验证

**Files:**
- Modify: `data/farm_3d_save.json`（用保护副本覆盖）

**前置条件：用户的 Godot 游戏必须已关闭**（运行中的实例会用全新农场覆盖存档）。执行前与用户确认。

- [ ] **Step 1: 恢复旧存档**

```bash
cd /d/UnityProject/villa
cp data/farm_3d_save.json.pre-rename-protected.bak data/farm_3d_save.json
```

- [ ] **Step 2: headless 验证真实旧存档可迁移可校验（只读）**

Run: `cd /d/UnityProject/villa && godot --headless --path . --script tests/run_zewei_npc_tests.gd -- --farm-test --living-world-scenario=P12`
Expected: `FLOWER_GIRL: N checks, 0 failures`。其中 "Existing player save validates after additive migration" 检查会对恢复后的真实存档执行 `_migrate_rename_zewei` + `_valid_save`（只读，不落盘）——通过即证明旧进度可加载。
再用 Python 复核存档文件未被测试改写：`ls -la data/farm_3d_save.json`（大小应仍为 1415333、mtime 不变）。

- [ ] **Step 3: 用户启动 Godot 做游戏内验证**

Expected（用户确认）：
1. 启动日志无 "Farm save could not be loaded"（旧农场恢复，日期/金币为 9/23 进度）；
2. 地图 (-6,-6) 附近出现 zewei（flower_girl），名字牌显示 "zewei"，使用 young_woman_cardigan 模型；
3. 点击可对话且有 LLM 回复；
4. 她进入 focus 名单，agent loop 正常调度。

- [ ] **Step 4: 服务端旁证**

用户游戏内操作后，验证事件出现（应见 `chat.jobs:flower_girl` 与 `action.v2:flower_girl` 的决策类事件，而非只有经济模拟事件）：
```bash
cd /d/UnityProject/villa/services/agent-service/data
sqlite3 "file:agent-memory.sqlite?mode=ro" "SELECT agent_id, kind, COUNT(*) FROM events WHERE session_id=(SELECT session_id FROM sessions ORDER BY updated_at DESC LIMIT 1) AND agent_id LIKE '%flower_girl%' GROUP BY 1,2;"
```

---

### Task 6（可选，需用户确认）: 提交

用户确认后提交全部改动（含此前未提交的 4 个数据文件改名 + 本计划改动），commit message 以 `Co-Authored-By: Claude Code <noreply@anthropic.com>` 结尾。清理项：`data/farm_3d_save.json.fresh-20260924` 与 `.pre-rename-protected.bak` 是否保留/加入 .gitignore 由用户决定（勿提交进 git）。
