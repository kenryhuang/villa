# 水井原始素材

- `source/well_native.tscn`：可编辑原始网格，嵌入所有 PBR 材质，不依赖运行脚本。
- `well.glb`：用于 Blender 等工具的交换模型。
- `generation.json`：生成参数、源代码位置、SHA-256、尺寸和三角面统计。
- 生成器：`scripts/farm3d/well_model.gd`；导出器：`scripts/tools/export_well.gd`。

原生程序化建模，无输入图片，无外部纹理贴图。材质颜色、粗糙度及金属度保存在原始场景和 GLB 中。

游戏场景 `scenes/farm3d/buildings/well.tscn` 使用同一生成器，包含施工阶段、碰撞和操作范围。与水车、温室的运行规则见 `docs/design/2026-09-19-well-irrigation.md`。
