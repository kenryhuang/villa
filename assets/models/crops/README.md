# 3D 作物模型

| 目录 | 模型 | Blender 源文件 |
| --- | --- | --- |
| `rose/` | 播种、幼苗、花苞、成熟、枯萎 | `art/blender/rose.blend` |
| `potato/` | `potato_seed.glb`、`potato_mature.glb` | `art/blender/potato.blend` |
| `tomato/` | `tomato_seed.glb`、`tomato_mature.glb` | `art/blender/tomato.blend` |
| `lavender/` | `lavender_seed.glb`、`lavender_mature.glb` | `art/blender/lavender.blend` |
| `carrot/` | 播种、成熟胡萝卜 | `art/blender/carrot.blend` |
| `strawberry/` | 播种、成熟草莓 | `art/blender/strawberry.blend` |
| `blueberry/` | 播种、成熟蓝莓 | `art/blender/blueberry.blend` |
| `watermelon/` | 播种、成熟西瓜藤 | `art/blender/watermelon.blend` |
| `sunflower/` | 播种、成熟向日葵 | `art/blender/sunflower.blend` |
| `pumpkin/` | 播种、成熟南瓜藤 | `art/blender/pumpkin.blend` |
| `apple/` | 树苗、结果苹果树 | `art/blender/apple.blend` |
| `peach/` | 树苗、结果桃树 | `art/blender/peach.blend` |
| `grape/` | 播种、结果葡萄架 | `art/blender/grape.blend` |
| `lemon/` | 树苗、结果柠檬树 | `art/blender/lemon.blend` |

除玫瑰外，这里 13 种作物各有播种／树苗和成熟两个 collection，GLB 统一命名为 `<crop_id>_seed.glb`、`<crop_id>_mature.glb`。Blender 默认显示成熟植株。源文件打包了原插画作为美术参考；游戏使用真实曲面叶片、茎、花和果实，不显示图片卡片，也不朝向镜头旋转。谷物的已有模型继续位于 `assets/models/farm3d/`。

单位为米，Blender Z 向上，导出 GLB Y 向上。共同根部原点放在地块 Y=0.045，根茎和种子下半部伸入土面。土豆播种模型使用带芽眼的种薯；成熟模型以原图的茂密宽叶与淡紫白花表现。

生成三种两阶段作物（覆盖这三种作物的 GLB 和 Blender 源文件，不改玫瑰）：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python scripts/tools/build_two_stage_crops.py
godot_console.exe --headless --editor --path . --quit
```

如果已经在 Blender 手工修改模型，重跑生成脚本会覆盖手工编辑，请直接导出所编辑的 collection。

生成其余十种作物（胡萝卜、草莓、蓝莓、西瓜、向日葵、南瓜、苹果、桃子、葡萄、柠檬）：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python scripts/tools/build_remaining_crops.py
godot_console.exe --headless --editor --path . --quit
```

此脚本复用 `build_two_stage_crops.py` 的网格与绘色工具；导入工具模块不会重建前三种作物。它仅覆盖上述十种的模型和 Blender 源文件。

所有 GLB 的 `.import` 配置使用共享 `scripts/tools/import_painted_crop.gd`，启用顶点绘色。此脚本由原 `import_rose.gd` 更名而来，玫瑰也已更新引用。

正式接入在 `scripts/farm3d/crop_visual_system.gd`：两阶段作物成熟前统一显示播种／树苗模型，成熟后切换完整植株。枯萎复用当时的模型并染褐色，不增加独立枯萎资产。原种植、生长时间、季节、库存、收获、存档规则不变；番茄和果树也沿用当前收获后移除整株的规则，柠檬仍要求温室。

原 `assets/crops/` 图片场景仍供旧游戏使用。玫瑰详细说明见 [rose/README.md](rose/README.md)。
