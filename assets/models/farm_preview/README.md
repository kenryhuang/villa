# 农庄 3D 模型预览

这一组原创模型使用 Blender 程序化建模，供第三人称画面和比例评估。采用简化卡通形体与纯色粗糙材质，没有外部模型、贴图或插件依赖。

| 文件 | 内容 |
| --- | --- |
| `player_farmer.glb` | 草帽、米色衬衣、蓝背带裤、皮靴农庄主；12 骨骼；Idle / Walk 动画 |
| `tree_oak.glb` | 带树根、分枝、分层树冠的橡树 |
| `farmland_tile.glb` | 2.8 × 2.8 米的土块、七条垄沟和泥土颗粒 |
| `grain_young.glb` | 六株有弯曲叶片的谷物幼苗 |
| `grain_mature.glb` | 六株带独立籽粒、芒刺与叶片的成熟谷物 |
| `farm_environment.glb` | 六棵橡树、九块田、幼苗、麦穗、小路、草、石头、围栏组成的预览环境 |

源文件：`art/blender/farm_preview.blend`。双击用 Blender 打开，已设置整体场景与相机。原始独立资产位于 01–05 集合，02–05 默认隐藏以免与组合场景重叠；在 Outliner 中启用对应集合即可单独编辑。06 是可编辑环境，07 是合并静态网格后的导出副本，默认隐藏。

GLB 使用米为单位，Y 朝上；玩家正面朝 +Z，脚底为原点，高约 2.08 米。源文件使用 Blender 的 Z 朝上；导出器转换坐标。角色首轮采用分部刚性权重，后续精修关节变形与完整动作。

项目根目录运行 `./tools/preview_3d.ps1` 打开 Godot 预览。主游戏入口仍为 `scenes/main.tscn`；预览场景为 `scenes/preview/farm_3d_preview.tscn`，用于模型与操控评估，尚未接入种植/收获交互。

需要重新生成时，在项目根目录执行（会覆盖这些生成资产与 Blender 源文件；手工编辑的源文件请另存）：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python scripts/tools/build_3d_farm_assets.py -- --render
```

不加 `-- --render` 可以只生成模型。Blender 原始材质与 Godot 预览光照不同，最终游戏表现以 Godot 实际截图为准。
