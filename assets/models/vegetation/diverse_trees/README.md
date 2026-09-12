# 六种原创树木与树皮贴图

正式地图的 34 棵树使用本目录模型。源文件是 `art/blender/diverse_trees.blend`，各树种有三档 LOD、独立树干与树叶、可编辑枝干组件。

| 树种 | 树皮 |
| --- | --- |
| `warm_oak` 橡树 | 暖灰褐色，细密纵向纤维与浅裂隙 |
| `forked_birch` 桦树 | 象牙灰白色，断续横向皮孔 |
| `copper_maple` 枫树 | 灰红褐色，柔和的细纹 |
| `golden_poplar` 杨树 | 浅灰绿色，稀疏横向斑痕 |
| `blue_pine` 松树 | 暖棕色，较明显的块状树皮 |
| `weeping_willow` 柳树 | 灰橄榄色，纵向沟纹 |

每种树共享一张 1024×1024 颜色贴图和一张切线空间法线贴图，三个 LOD 的 GLB 均引用同一对外部 PNG。不要删除这些 PNG，也不要为每个 LOD 复制一套。导入设置启用显存压缩与 mipmap，减少显存占用和远处闪烁。

树皮由 `scripts/tools/tree_bark_materials.py` 在 Blender 中程序化制作，再烘焙到树干 UV。源文件内同时保留打包贴图和带 fake user 的 `editable procedural bark` 材质，便于继续调整。叶片继续使用原有顶点颜色。树皮凹凸由法线贴图表达，不额外增加几何面。

`scripts/vegetation/tree_pack_tree.gd` 从导入材质读取树皮贴图并传入风动 Shader，切换 LOD 时继续共享贴图；未带树皮贴图的旧树及灌木沿用原有颜色材质。

重建：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --disable-autoexec --python scripts/tools/build_diverse_trees.py
```

预览：`./tools/preview_diverse_trees.ps1`，1–6 切换树种，B 隐藏树叶，L 切换 LOD，W 开关风动。

资源验证：`godot_console.exe --headless --path . --script tests/run_tree_bark_tests.gd`。
