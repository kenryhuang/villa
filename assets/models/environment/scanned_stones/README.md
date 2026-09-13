# 农庄扫描石头

来源：`art/blender/import/Stone Pack 1 photoscanned/stone_pack_01.blend`。随包 `license.txt` 声明模型与作者照片纹理为 CC0；保留原目录的许可文件及 BlendSwap 许可页面作为来源记录。

生成：`scripts/tools/build_scanned_stones.py`，使用 Blender 后台运行。整理后的可编辑源文件为 `art/blender/scanned_stones.blend`，原扫描文件和原农庄 GLB 不改动。

- 四个 GLB 各含 `Rock` 和 `Pebble` 网格，共用一套 1024×1024 颜色/法线贴图。两个网格重叠是变体资产的组织方式，运行时只提取需要的网格。
- 模型最长水平边归一化为 2 米，接地中心为原点；裁去扫描裙边，补平底面，重新展开游戏 UV 并烘焙贴图。颜色略微降低饱和度、加入暖灰，保留扫描裂纹和苔藓。
- 普通石头分别为 1,904 / 3,000 / 3,000 / 3,000 三角面；小石每种 140 三角面。生成脚本验证两种网格均封闭。
- GLB 内嵌贴图，由 Godot 按项目已有导入方式提取为 PNG；不再另存一套重复的烘焙图片。Blender 源文件也已打包贴图。
- `placements.tres` 是从现有 `farm_environment.glb` 的 `River stone` 材质网格提取的 58 个原始位置及尺寸，作为资源随游戏导出。
- 正式入口通过 `scripts/farm3d/ground_stones.gd` 移除环境网格中的旧岩石表面，保留其他表面；3 块大石和 55 块小石按固定位置使用四种模型，以 7 个 MultiMesh 批次显示。
- 大石有简化凸包碰撞，沿用现有不可耕作与 NPC 避让区域；小石作为地面细节，不阻挡行走、不投射阴影，远距离隐藏。Godot 自动生成网格 LOD。

实景与验证：`docs/validation/2026-09-11-stone-pack-review.md`。

## 山坡少量试铺（2026-09-13）

正式入口额外加载 `scripts/farm3d/hillside_stones.gd`，复用上述四种 Rock 网格和材质，不新增贴图或重复导出资产。西侧丘陵 24 块、北侧山坡 12 块；宽约 0.4–0.95 米，固定种子随机大小和朝向，重新加载布局保持一致。只选取装饰坡地，避开道路、种植、建筑、树干、水面和已有灌木；存档占用可能减少最终数量。

石头随坡面法线旋转，以所有底部顶点校准高度后再嵌入 2 cm，避免跨地形三角面时露出底面。使用空间分组的 MultiMesh 和既有自动网格 LOD，100 米外隐藏。这批低矮点缀不增加碰撞、不修改导航或存档；原农庄三块大石的碰撞保持原样。

验证：`tests/run_hillside_stone_tests.gd -- --farm-test`，9 项检查通过，涵盖数量、区域、四种模型、占用避让、底部贴地、顶部露出和固定布局。游戏内截图：`docs/validation/hillside-stones/hillside.png`、`detail.png`。
