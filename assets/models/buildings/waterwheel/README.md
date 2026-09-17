# 岸边水车原始素材

- 可编辑生成源：`scripts/farm3d/waterwheel_model.gd`。
- `source/waterwheel_native.tscn`：烘焙的原始网格和嵌入 PBR 材质，不依赖生成脚本即可打开。
- `waterwheel.glb`：用于 Blender 等工具交换；保留独立 Rotor 节点，运行旋转由游戏脚本驱动，没有骨骼动画。
- `generation.json`：生成方法、版本、源文件校验、尺寸、轴向和网格统计。
- `preview.png`：实际农庄场景中的水车与温室联动。

这是项目内原生几何建模，没有使用 Meshy/Tripo 或输入图片，也没有外部贴图；木材、铁件、石材和水面使用嵌入的颜色/粗糙度材质。因此参数清单中的输入图片与贴图数组为空，并非遗漏归档。

岸基为 2×2 米，轮缘半径 1.14 米，+Z 面朝水域，X 为转轴；木轮伸出岸基进入水域。运行时自动匹配水源方向和水位。温室连接管由实时场景生成，不属于单体 GLB。

重新归档：`godot_console.exe --headless --path . --script res://scripts/tools/export_waterwheel.gd`。
