# 3D 玫瑰

正式 3D 农庄使用的玫瑰模型。旧游戏仍使用 `assets/crops/rose/` 的图片场景。

| 模型 | 状态 |
| --- | --- |
| `rose_seed.glb` | 五粒半埋入土的种子 |
| `rose_sprout.glb` | 幼苗与子叶 |
| `rose_growing.glb` | 较小的枝叶与闭合花苞 |
| `rose_mature.glb` | 四朵开放玫瑰、两朵花苞与复叶 |
| `rose_withered.glb` | 落花、褐色下垂叶片与弯曲枝茎 |

源文件：`art/blender/rose.blend`，五阶段分 collection 保存，打开默认显示成熟阶段。原玫瑰图片作为调色参考打包在文件中。花瓣与叶片均为曲面网格，不使用图片卡片或 billboard。

Blender 使用 Z 向上，导出 GLB 使用 Y 向上，单位米。五阶段共享根部原点，根茎略伸入零平面以下，种子下半部埋入土中。游戏在地块局部 Y=0.045 放置原点，并根据地块坐标固定水平朝向；生长和镜头转动不改变朝向。

重建命令（会覆盖本目录五个 GLB 和 `art/blender/rose.blend`，手工编辑 Blender 后勿直接重跑）：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python scripts/tools/build_rose.py
godot_console.exe --headless --editor --path . --quit
```

应保留 `.glb.import` 的 `scripts/tools/import_rose.gd` 后处理配置。它启用 GLB 的顶点颜色；否则 Godot 虽保留颜色数组，材质仍可能显示为白色。

运行接入：`scripts/farm3d/crop_visual_system.gd`。不修改玫瑰的物品 ID、生长时间、季节或收获规则，也不要求迁移存档。旧 3D 存档里的玫瑰在恢复地块时自动采用新模型。
