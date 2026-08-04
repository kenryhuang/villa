# 手动采集系统验收记录

日期：2026-08-04  
分支：`feature/single-click-tree-felling`
设计依据：`docs/superpowers/specs/2026-08-04-manual-gathering-design.md`

## 验收范围

本轮在原手动采集验收上加入单击伐木增量：五种可砍树、绿/红资格提示、2 秒三帧倒树、根部斧头、整树原子结算、手绘树桩和退休树记录迁移；矿石继续保持 1.2 秒单单位流程。

关键结果：

- 新树一次增加 5 木材（旧部分树只增加剩余量），扣除 8 体力和 1 点斧头耐久；矿石仍一次增加 1 单位。
- 仅 `pine-small`、`pine-tall`、`canopy-small`、`canopy-medium`、`round-small` 可砍；其他树显示红环并在点击时提示“此树不可砍伐”。
- 五套透明图集各包含三张砍倒帧和一张同树种手绘树桩；左右倒向、根部基线和取消恢复均通过视觉检查。
- 采集动作期间游戏时钟暂停；成功后精确推进 10 游戏分钟，23:55 开始的动作会在次日 06:05 完成。
- 背包满、体力不足、工具损坏、不可达、目标失效以及任何主动取消均不会产生部分结算。
- 采集所得立即进入玩家背包并减少建筑材料缺口；采集本身不改变市场，只有主动出售才改变金币与市场库存。
- 旧资源记录按当前容量向上折算为 v2；新增可砍稳定树自动补满；退休的 `tree-resource-04/07` 精确丢弃，其他重复/未知 ID、非法刷新日和坏记录整批拒绝并回滚。
- 真实 v1 资源 ID 会一对一迁移到新目录 ID，并采用当前 authored 坐标；装饰树和资源碰撞体都参与 A* 阻挡，物理自动移动已覆盖验证。
- 采集事务会缓冲资源激活信号；任何目标提交异常都会同时回滚资源、背包、体力、耐久和对外事件。

## 自动测试

以下命令均在 `D:\UnityProject\villa\.worktrees\single-click-tree-felling` 执行，使用 Godot 4.7.1，退出码均为 0。

| 测试入口 | 实际结果 |
|---|---:|
| `tests/run_tests.gd` | PASS：1269 |
| `tests/run_grid_system_tests.gd` | PASS：106 |
| `tests/run_farming_system_tests.gd` | PASS：578 |
| `tests/run_building_system_tests.gd` | PASS：921 |
| `tests/run_economy_system_tests.gd` | PASS：64132 |
| `tests/run_economy_ui_tests.gd` | PASS：126 |
| `tests/run_main_gameplay_integration_tests.gd` | PASS：982 |
| `tests/run_resource_gathering_tests.gd` | PASS：170 |
| `tests/run_gathering_visual_tests.gd` | PASS：64 |
| `tests/run_main_gathering_integration_tests.gd` | PASS：100 |

经济测试保留两项既有非阻塞警告：恶意 JSON 指数过高的防御性解析警告，以及水车施工阶段图缺失时启用程序化回退；本功能未新增解析错误、无效节点、孤立信号或时间锁警告。

## 视觉捕获

执行命令：

```powershell
godot --path . --display-driver windows --rendering-method gl_compatibility `
  -s res://tests/capture_manual_gathering.gd
```

结果：`PASS: 39 deterministic manual gathering captures`。运行产物写入 `.godot/manual-gathering-validation/`，不纳入版本控制。

| 状态 | 1280×720 | 1920×1080 | 3000×2000 | 人工检查 |
|---|---:|---:|---:|---|
| 树木目标与虚线路径 | 通过 | 通过 | 通过 | 目标环、剩余量、路径端点清晰 |
| 绿/红树木资格 | 通过 | 通过 | 通过 | 透明环颜色清晰，仍可看到树根与树种 |
| 伐木动作与三帧 | 通过 | 通过 | 通过 | 进度圆跟随目标；斧头位于根部；缺口、倾斜、近倒地三帧无单元格裁切 |
| 左右倒向 | 通过 | 通过 | 通过 | 水平翻转方向明确，树根基线不跳动 |
| `+5 木材` 与手绘树桩 | 通过 | 通过 | 通过 | 本地化飘字可读，HUD 增加 5，灰色几何树桩已移除 |
| 矿脉完整/受损/碎石 | 通过 | 通过 | 通过 | 体积、裂纹与扁平碎石阶段可区分 |
| 背包已满 | 通过 | 通过 | 通过 | 失败文字居中，无裁切，不启动移动 |
| 无法到达 | 通过 | 通过 | 通过 | 失败文字居中，无裁切，不产生结算 |

进度扇形使用相机投影跟随资源上方，并与剩余量文字保持至少 72px 屏幕间距；自动装备提示跟随玩家，失败提示保持视口中心；结果/失败文字具有自动消失时限。三种分辨率下未发现本功能新增的裁切、重叠或不可读文字。截图中沿用的角色胶囊、矿石程序化模型和 HUD 空白信息槽属于当前项目既有美术框架，不影响本轮采集逻辑与反馈验收。

## 静态检查

- `git diff --check`：无输出。
- 功能改动文件中未留下未完成实现标记。
- 全局搜索只命中既有市场安全回退纹理及其测试，不属于本功能。

## 结论

手动采集已形成可玩的经济入口：玩家能从世界获得木材、石材和矿产，资源直接进入建造/合成/交易共用背包，并保持市场行为由玩家主动交易驱动。功能满足正式设计和执行计划的完成定义。
