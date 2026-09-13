# Photorealistic Grass 局部试铺

当前状态：已按用户要求从正式场景撤下（2026-09-13）。保留转换源文件与试验代码供后续参考，游戏不再加载或生成这两处草丛。以下为此前试铺参数。

原资源：**Photorealistic Grass**，作者 **xablend1122**，Blend Swap 69868。
原文件为 `art/blender/import/Photorealistic Grass/GrasTest.blend`。
随附授权为 **Creative Commons Attribution 3.0**，使用和分发时保留作者署名。
原授权全文已复制到本目录 `LICENSE.txt`。

原文件是 Blender 2.68 毛发粒子场景，配置 15,000 根母草和每根 60 根子草，
没有草叶图片贴图。其粒子、地面位移和离线材质不能直接作为 Godot 地面导入。
转换脚本读取到 1,470 条有效母草曲线，将它们转为逐渐收尖的网格草叶，
适配 16–29 cm 草高、深色根部与橄榄绿叶尖。地面继续使用正式地图的地形。

| 模型 | 变体 | 每丛草叶 | 每丛三角面 |
| --- | ---: | ---: | ---: |
| LOD0 | 3 | 52 | 468 |
| LOD1 | 3 | 18 | 54 |

`scripts/farm3d/photoreal_grass_trial.gd` 在正式农庄试铺两处：

- 西侧：中心 `(-7, 3.5)`，椭圆半径 `(2.7, 2.0)` 米。
- 东侧：中心 `(11, -4.5)`，椭圆半径 `(2.4, 2.2)` 米。

新农庄初始布局共 284 丛草，使用 12 个 MultiMesh 批次（两档 LOD，
同一位置只显示一档）。全部以近景显示时约 132,912 个三角面，
远景为 15,336 个。18 米切换远景，34–44 米逐渐压入地面，46 米停止显示。
叶根固定、叶尖随风轻摆；没有草丛碰撞体。

只在当前可通行荒地生成，避开道路、树干、农田、作物和建筑。
格子开垦或建造后，相关草丛随事件移除；建筑拆除恢复荒地后按固定种子恢复。
草丛不修改存档、格子状态或寻路规则。初始数量可能随已有存档地块变化。

重建：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --factory-startup --background --disable-autoexec --python-exit-code 1 --python scripts/tools/build_photoreal_grass.py
```

可编辑转换文件为 `art/blender/photoreal_grass_game.blend`，原文件保持完整。
测试：`godot_console.exe --headless --path . --script tests/run_grass_trial_tests.gd -- --farm-test`。
22 项检查通过，包含导入颜色/风动权重、实例预算、地形落点、地块清草与恢复。
实景前后截图位于 `docs/validation/photoreal-grass/`。
此结果验证局部使用效果，尚未进行全地图铺设的帧率评估。
