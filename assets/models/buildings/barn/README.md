# Blender 谷仓

正式 3D 谷仓使用 `barn.glb`，源文件为 `art/blender/barn.blend`。保留原图的木梁、暖色木墙、灰绿色瓦顶和石砌底座，补齐四面墙、屋顶、双开门、金属门环、阁楼窗和侧面通风窗。

- 单位为米，Godot Y 朝上，正门朝 +Z；原有占地仍为 2 × 2 格，檐口略伸出占地，高约 3.2 米。
- 底座向地下延伸约 0.23 米，衔接平地和允许建造的轻微高差。
- `Foundation`、`Frame`、`Walls`、`Roof`、`Details` 为施工阶段分组。部件合并为五个网格，材质分别保留木材、红木板、瓦片、石块和铁件。
- 三张 `barn_*_paint.png` 为程序绘制的表面材质，贴在真实几何体上。GLB 嵌入贴图，Blender 源文件也已打包，移动源文件后仍可编辑。
- 3D 专用场景：`scenes/farm3d/buildings/barn.tscn`。`Farm3DBuildingSystem` 对谷仓选择此场景，放置预览、新建谷仓、旧存档恢复均走同一入口；原游戏的 `scenes/buildings/barn.tscn` 保留。
- 建造费用、2 × 2 占地、施工时长、仓库效果与建筑存档格式沿用原系统。

重新生成（覆盖该谷仓模型与 Blender 源文件）：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python scripts/tools/build_barn.py
godot_console.exe --headless --editor --path . --quit
```

[实景与验证](../../../../docs/validation/barn-3d.md)
