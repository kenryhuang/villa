# 原画风格疏叶树

当前作为独立美术预览保留；正式地图已改用 [tree_pack 的三种加粗枝干树木](../tree_pack/README.md)。下文接入说明记录本组模型先前的使用方式。

参考 `assets/vegetation/` 原2D树木，重点塑造粗根、弯干、分叉和树瘤。叶簇覆盖枝梢和外侧枝条，保留冠间空隙，方便看到树干结构。当前版将原四种树的叶量增至约1.9～2倍，并增加约9米高、直干的高松树。

| 树种 / 文件前缀 | 原图 | 近景叶片 | LOD0 / LOD1 / LOD2 三角面 |
| --- | --- | ---: | ---: |
| 粗根老橡树 `elder_oak` | `tree-oak-large.png` | 1010 | 24,654 / 13,942 / 6,886 |
| 舒展伞冠树 `open_canopy` | `tree-canopy-medium.png` | 892 | 22,768 / 12,808 / 6,311 |
| 斜干金叶树 `golden_leaning` | `tree-yellow.png` | 722 | 20,046 / 11,174 / 5,494 |
| 疏层松树 `open_pine` | `tree-pine-large.png` | 1239 | 28,299 / 16,124 / 7,969 |
| 直干高松树 `tall_pine` | `tree-pine-tall.png` | 1599 | 34,038 / 19,566 / 9,687 |

源文件：`art/blender/illustrated_trees.blend`。五种树分集合排列，每棵含三档模型和隐藏的 `editable branch construction` 原始枝干组件。可打开集合继续精修；`STUDIO` 是预览地面、灯光和相机，不导出。

根、干、枝熔合为连续网格。树皮从原橡树图片采样笔触，通过Blender烘焙到1024×1024 UV贴图；叶片直接以原图树冠的有效区域为纹理，是弯曲的实体网格，不朝向相机。原图中的地面与投影不会成为树模型的一部分。

GLB以根部为原点，Y向上、米为单位；每档只有树干、树叶两个网格。纹理打包在GLB与Blend中，独立的五张 `{树种}_bark.png` 烘焙副本已清理，需要编辑时可从Blend提取。Godot实际引用的 `{树种}_lod{档位}_*.png` 及其导入配置仍需保留。Godot使用已有 `scripts/tools/import_painted_oak.gd` 保留顶点色；`.glb.import` 禁用再次自动生成LOD及动画导入。

正式地图已使用 `scenes/vegetation/illustrated_tree.tscn` 替换全部34棵旧橡树：农庄中心6棵、外围16棵、高尔夫球场12棵。位置和原有缩放沿用，树种由世界坐标与固定种子确定，不依赖游戏随机数或存档，每次启动相同。

运行脚本 `scripts/vegetation/illustrated_tree.gd` 按需加载三档模型并共享资源；约24/55米切档，距离按树木缩放调整并带切换缓冲。远处首次只实例化低细节模型，曾加载的模型留作复用，每棵只显示一档。树干碰撞位于层1，树冠近似碰撞位于层4，后者用于镜头和高尔夫；五种树的树冠碰撞分别设置。原有寻路避让保留，并修复道路格覆盖树干时仍被当作可通行区域的问题。模型目前为静态树，没有风动。

```powershell
# 预览：1–5切树，B隐藏叶子，L切LOD，右键环绕
./tools/preview_illustrated_trees.ps1

# 重建生成资产和Blender渲染图
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --disable-autoexec --python scripts/tools/build_illustrated_trees.py -- --render
```

脚本只覆盖本套生成资产；如手工修改Blend，请先另存。现有导入设置应与模型一起保留。原图未被修改。

[五树预览与验收](../../../../docs/validation/2026-09-11-illustrated-trees.md)。
