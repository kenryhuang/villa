# 八床育苗温室

- `greenhouse.glb`：可在 Blender 等工具中打开的模型交换文件。
- `source/greenhouse_native.tscn`：独立原始网格、施工分组和完整材质参数，无生成脚本依赖。
- `generation.json`：参数、几何规模、引擎版本、源文件校验值与来源说明。
- `preview.png`：正式农场场景实拍，床中的作物是游戏的独立作物资产，不烘焙进温室模型。

可编辑建模源为 `scripts/farm3d/greenhouse_model.gd`；以 `scripts/tools/export_greenhouse.gd` 重新导出。
运行时入口为 `scenes/farm3d/buildings/greenhouse.tscn`，保留共享建造、维护、存档与种植规则。

本资产使用程序化网格和内嵌 PBR 材质，不依赖图片生成服务，没有外部输入图片或贴图文件。材质参数已保存在原始场景与 GLB 中，空数组也记录在清单中。

经营规则、出租设计和测算见 `docs/design/2026-09-16-greenhouse-model-economy.md`。
