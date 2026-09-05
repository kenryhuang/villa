# 农庄 3D 模型与游戏场景

这一组原创模型使用 Blender 程序化建模，用于第三人称农庄游戏。角色和田地采用简化卡通形体与纯色粗糙材质；场景树木使用新建的手绘橡树模型。

| 文件 | 内容 |
| --- | --- |
| `player_farmer.glb` | 草帽、米色衬衣、蓝背带裤、皮靴农庄主；12 骨骼；Idle / Walk 动画 |
| `tree_oak.glb` | 早期几何橡树，保留作对照，当前场景不再使用 |
| `farmland_tile.glb` | 2.8 × 2.8 米的土块、七条垄沟和泥土颗粒 |
| `grain_young.glb` | 六株有弯曲叶片的谷物幼苗 |
| `grain_mature.glb` | 六株带独立籽粒、芒刺与叶片的成熟谷物 |
| `farm_environment.glb` | 静态地面、小路、石头、围栏；树木、田地和作物由 Godot 独立实例管理 |

源文件：`art/blender/farm_preview.blend`。双击用 Blender 打开，已设置整体场景与相机。原始独立资产位于 01–05 集合，02–05 默认隐藏以免与组合场景重叠；在 Outliner 中启用对应集合即可单独编辑。06 是可编辑环境，07 是合并静态网格后的导出副本，默认隐藏。09 是从 `art/blender/painted_oak.blend` 载入的新橡树组合。

Godot 场景的 `Trees` 节点包含六个 `scenes/vegetation/painted_oak.tscn` 实例，保持原来的树木位置，并按新模型调整尺寸。模型、树干碰撞和相机避让碰撞随实例一起缩放；以后更新橡树资产即可同步所有树。

GLB 使用米为单位，Y 朝上；玩家正面朝 +Z，脚底为原点，高约 2.08 米。源文件使用 Blender 的 Z 朝上；导出器转换坐标。角色首轮采用分部刚性权重，后续精修关节变形与完整动作。

项目默认启动场景为 `scenes/preview/farm_3d_preview.tscn`，在 Godot 中按 F5 即可进入 3D 农庄，也可以运行 `./tools/preview_3d.ps1`。已经接入原有格子、工具、播种、时间季节、生长和收获系统。数字键 1–4 选择锄头、谷物种子、浇水壶、收获；靠近后左键操作鼠标指向的格子，E 操作角色前方。原游戏保留在 `scenes/main.tscn`，可单独打开后按 F6 运行；单树观察场景为 `scenes/preview/tree_3d_preview.tscn`。

草地由 `scripts/farm3d/painted_meadow.gd` 使用原 `grass-seamless-blended.png` 设置地表材质；不再生成额外的立体杂草和野花。动态田地将 `farmland_tile.glb` 缩放至原游戏的 1 米格子；幼苗和成熟谷物均使用真实 GLB 网格。Blender 源文件保存静态环境、角色、树木和独立建模资产，动态草地与农田的最终效果请在 Godot 中查看。

游戏自动保存至 `user://farm_3d_save.json`，与原游戏存档独立。完整控制与验证见 `docs/validation/3d-farming-integration.md`。

需要重新生成时，在项目根目录执行（会覆盖这些生成资产与 Blender 源文件；手工编辑的源文件请另存）：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python scripts/tools/build_3d_farm_assets.py -- --render
```

不加 `-- --render` 可以只生成模型。Blender 原始材质与 Godot 预览光照不同，最终游戏表现以 Godot 实际截图为准。
