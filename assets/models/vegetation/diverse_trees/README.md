# 六种原创树木与树皮贴图

正式地图的 28 棵树使用本目录模型，另外 6 棵为 mawais/T1 试放模型。源文件是 `art/blender/diverse_trees.blend`，各树种有三档 LOD、独立树干与树叶、可编辑枝干组件。

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

## 垂柳叶片细化

垂柳改为沿 308 根细枝交错生长的独立柳叶，叶片长约 12–24 厘米，
有轻微折面、弯曲和朝向变化；保留下垂形态，并打开叶丛之间的空隙。
叶色与局部明暗参考 mawais_tree，使用 `willow_leaves.gdshader`，
不再把叶片法线混成整个树冠的方向。该材质只用于垂柳，兼容原有风动开关。

| LOD | 叶片数 | 总三角面 |
| --- | ---: | ---: |
| 0 | 6,414 | 63,464 |
| 1 | 4,439 | 39,124 |
| 2 | 2,465 | 25,460 |

仅重建柳叶（也应在完整重建六种树之后运行）：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --factory-startup --background --disable-autoexec --python-exit-code 1 --python scripts/tools/refine_willow_foliage.py
```

脚本同步更新 Blender 源文件和三档柳树 GLB，保留树干几何、法线、UV 和共享树皮贴图。
三档资源已对比原模型验证，132 项树皮/LOD 检查通过；地图中 4 棵垂柳均已实景截图。
前后近景、三档 LOD 和实景图位于 `docs/validation/willow-leaves/`。
原模型本地备份在 `tmp/willow-before-leaf-refine/`。

## 其余五种树的叶片细化

橡树改为有浅裂的独立叶片，桦树为小型锯齿叶，枫树为掌状裂叶，
杨树为金色卵形叶；蓝绿色松树由宽叶片改为成束针叶。
叶片生长在连接原有枝干的细小分叉上，保留疏密变化和局部折面。
五种树使用 `modeled_leaves.gdshader`，与垂柳一样保留单片叶子的明暗，
并正确转换 Compatibility 渲染器中的顶点颜色。

| 树种 | 地图数量 | LOD0 三角面 | LOD1 三角面 | LOD2 三角面 |
| --- | ---: | ---: | ---: | ---: |
| 橡树 | 7 | 105,028 | 62,553 | 17,597 |
| 桦树 | 2 | 73,112 | 42,418 | 17,581 |
| 枫树 | 9 | 89,780 | 54,042 | 29,174 |
| 杨树 | 3 | 81,150 | 46,340 | 25,289 |
| 蓝绿色松树 | 3 | 110,768 | 63,776 | 35,218 |

这些模型增加了近景叶片和细枝几何，继续使用三档 LOD 与共享模型资源。
截图验证不代表帧率测试。树干碰撞、NPC 避让、树位和风动开关沿用已有逻辑。

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --factory-startup --background --disable-autoexec --python-exit-code 1 --python scripts/tools/refine_grove_foliage.py
```

只重建单个树种可在命令末尾加 `-- --species blue_pine`（或表中的英文资源 ID）。
完整重建六种树后，应分别执行柳树细化脚本和此脚本。此脚本保存更新后的
`art/blender/diverse_trees.blend` 及 15 个 GLB，不生成或覆盖垂柳资源。

15 个 GLB 已对比确认原有树干顶点、法线、UV、索引和树皮引用一致；
132 项材质/LOD 检查通过。五种树均有实景截图，地图中共 24 棵自动使用新资源。
资源备份位于 `tmp/grove-before-leaf-refine/`；截图与总览位于
`docs/validation/grove-leaves/`。
