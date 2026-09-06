# 3D 作物模型

| 目录 | 模型 | Blender 源文件 |
| --- | --- | --- |
| `rose/` | 播种、幼苗、花苞、成熟、枯萎 | `art/blender/rose.blend` |
| `potato/` | `potato_seed.glb`、`potato_mature.glb` | `art/blender/potato.blend` |
| `tomato/` | `tomato_seed.glb`、`tomato_mature.glb` | `art/blender/tomato.blend` |
| `lavender/` | `lavender_seed.glb`、`lavender_mature.glb` | `art/blender/lavender.blend` |

三种新增作物各有播种和成熟两个 collection，Blender 默认显示成熟植株。源文件打包了原插画作为美术参考；游戏使用真实曲面叶片、茎、花和果实，不显示图片卡片，也不朝向镜头旋转。

单位为米，Blender Z 向上，导出 GLB Y 向上。共同根部原点放在地块 Y=0.045，根茎和种子下半部伸入土面。土豆播种模型使用带芽眼的种薯；成熟模型以原图的茂密宽叶与淡紫白花表现。

生成三种两阶段作物（覆盖这三种作物的 GLB 和 Blender 源文件，不改玫瑰）：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python scripts/tools/build_two_stage_crops.py
godot_console.exe --headless --editor --path . --quit
```

如果已经在 Blender 手工修改模型，重跑生成脚本会覆盖手工编辑，请直接导出所编辑的 collection。

所有 GLB 的 `.import` 配置使用共享 `scripts/tools/import_painted_crop.gd`，启用顶点绘色。此脚本由原 `import_rose.gd` 更名而来，玫瑰也已更新引用。

正式接入在 `scripts/farm3d/crop_visual_system.gd`：三种作物成熟前统一显示播种模型，成熟后切换完整植株。枯萎复用当时的模型并染褐色，不增加独立枯萎资产。原种植、生长时间、季节、库存、收获、存档规则不变；番茄也沿用当前收获后移除整株的规则。

原 `assets/crops/` 图片场景仍供旧游戏使用。玫瑰详细说明见 [rose/README.md](rose/README.md)。
