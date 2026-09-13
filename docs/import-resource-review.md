# 导入资源检查（2026-09-13）

正式场景已经撤下 Photorealistic Grass 的两处试铺。原始资源、转换产物和试验脚本保留，正式入口不再加载它们。`tests/run_grass_trial_tests.gd` 改为先确认正式场景没有试铺草，再单独实例化试验组件；23 项检查通过。

检查范围：`art/blender/import/` 下全部同级资源。未将以下新候选资源加入正式地图，未覆盖原始 blend 文件。

后续核对与实施：项目在 9 月 11 日已经为扫描石头包生成 `assets/models/environment/scanned_stones/` 游戏版本，原农庄正在使用。本次山坡布置复用该版本，新增西侧 24 块、北侧 12 块。下表石头面数是原文件基础网格统计，实际使用的是已有精简网格（每种 1,904–3,000 三角面）。

| 资源 | 实际内容 / 开销 | 适用判断 |
| --- | --- | --- |
| Stone Pack 1 photoscanned | 4 块扫描石头；关闭细分后的基础三角面分别为 1,952 / 7,492 / 3,652 / 7,582，总计 20,678。颜色和位移图已打包，前三块 2K，第四块 4096×2048。 | 优先候选，适合路边、树下和水边点缀。导入时关闭离线细分/微位移，整理实时材质和碰撞，按需要增加 LOD。 |
| Trees/t3.blend | Apple Tree，带苹果的绿叶树。使用几何节点散布；当前视口依赖图遍历得到 158 个网格对象/实例，含源对象约 956,232 三角面，不能只看基础树干面数。 | 最贴合果园主题。应先精简树冠、实例和果实，并转换节点。当前统计不是完成导出后的最终预算。 |
| Trees/t4.blend | Orange Fall Tree，多干橙叶树，364,870 基础三角面，颜色/法线/透明度等图已打包。 | 可做秋色点缀，先精简并整理透明叶材质。 |
| Trees/t2.blend | Sakura Tree，3,526,461 基础三角面，其中花冠 3,120,000。 | 春季景观候选，原版过重，应重做花冠密度并提供 LOD。 |
| Trees/Baum3.blend | 老式树木场景，存在粒子叶片和细分。 | 与现有树木用途重叠；还需展开粒子才能获得准确游戏预算，优先级低。 |
| Trees  Bushes pack | 树和灌木合集，没有外部贴图依赖。 | 已有项目适配版本和灌木布置脚本，可复用现成资产，避免重复转换。 |
| Tree/tree.blend、Trees/t1.blend | 已处理的 mawais 树、修剪松树。 | 继续沿用已认可的游戏版本。 |
| Grassy Meadow/GEO Nodes 3.1.2.blend | 实际是 Landscape Generator，含沙漠、火星、阿尔卑斯山预设，非草甸模型。 | 文件内容与同目录草甸说明不匹配，不当作可直接导入的草地资源。 |

## 随文件携带的授权记录

- 石头包的 `license.txt` 和 `88662 - LICENSE.html` 均标为 CC0。
- t2、t3、t4 各自对象的 `asset_data` 中 license 为 `royalty_free`，来源 BlenderKit；不能用同目录其他 Blend Swap 许可替代其各自许可。
- Trees & Bushes pack：已有衍生资产说明记录 Painkiller5555 / CC BY 3.0。
- Grassy Meadow 外部 HTML 标 CC BY 3.0，但实际 blend 内 README 写明作者 grinsegold、CC-BY-NC 3.0 DE。该记录属于资源元数据；尚未将这份地形生成器用于游戏。

## 预览

这些是 Blender 对本地模型的渲染，不是游戏内效果。预览统一相机和光照；石头关闭细分以展示基础网格。未修改源文件。

![四块石头](validation/import-review/stones.png)

![苹果树](validation/import-review/t3.png)

![橙叶树](validation/import-review/t4.png)

![樱花树](validation/import-review/t2.png)
