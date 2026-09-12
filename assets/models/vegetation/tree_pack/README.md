# Trees & Bushes pack · 三种树木与两种灌木

原作者 **Painkiller5555**，原作 [Trees & Bushes pack / Blend Swap 78071](http://www.blendswap.com/blends/view/78071)，使用 [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/) 许可。

原始 Blender 文件及随附许可保留在 `art/blender/import/Trees  Bushes pack/`。Villa 的修改包括选取五个对象、统一米制尺寸与根部原点、展开不规则阔冠、接缝焊接、删减末梢枝条、按原弯曲中心线重建渐细主干和浅根、保留原始小叶片、顶点着色和三档细节。模型未沿用原场景的地板或相机，也没有外部图片纹理依赖。发布这些衍生资源时保留本署名及许可信息。

| 游戏名称 | 原对象 | 高度 | 近景三角面 | 中景 | 远景 |
| --- | --- | ---: | ---: | ---: | ---: |
| 金叶舒展 | tree.005 | 约5.46米 | 35,188 | 21,615 | 10,365 |
| 绿叶圆冠 | tree.007 | 约5.82米 | 69,416 | 36,616 | 15,615 |
| 灰绿层冠 | tree.008 | 约5.68米 | 54,916 | 31,215 | 14,366 |
| 草甸灌木 | tree | 1.25 米 | 2,549 | 1,069 | 404 |
| 灰绿灌木 | leaves | 1.05 米 | 2,318 | 939 | 379 |

这是外观命名，不代表已鉴定的植物物种。完整导出数据见 `model_report.json`。

文件ID沿用早期样板的 `golden_broadleaf`、`green_columnar`、`open_green`，但后两者的原始对象已换为 `tree.007`、`tree.008`。树冠覆盖约5.0～6.6米，横向展开同时保留不对称分枝。近景保留7,718 / 16,000 / 12,500片原始叶片，叶片几何和朝向来自原模型，仅放大至1.3倍；中远景分别为1.35和1.75倍。与上一版大幅抽稀后放大叶片不同，本版提高各档叶量，以保留自然层次。

正式地图使用 `scenes/vegetation/tree_pack_world.tscn`，按位置固定分配三种树，保留原34个位置与缩放。也可单独使用 `golden_broadleaf.tscn`、`green_columnar.tscn`、`open_green.tscn`。运行时带叶片柔和着色、微风、手动 LOD 及简化碰撞。请保留 `.glb.import` 中关闭自动 LOD、动画导入和启用顶点色后导入脚本的设置。

自动细节在相机距离约 20 / 45 米切换，距离按树的缩放修正，带 2 米滞回；每 0.25 秒检查一次，只实例化需要的细节等级并缓存模型。树干碰撞层 1、半径0.5米，树冠层4，两者带 `golf_obstacle` 标记。碰撞不随 LOD 切换消失。当前地图沿用原树木的网格障碍位置；另行新增树木时仍需登记 NPC 导航障碍。

正式树场景启用 `terrain_roots`：仅下部树干和浅根按所在坡面的局部高度梯度贴地，各LOD第一次加载时处理一次，叶片网格仍共享。独立美术预览使用平面根部。高尔夫树坑原有的棕色圆环已从场景生成代码移除，树根处不再另画底盘。

灌木由 `scripts/farm3d/landscape_shrubs.gd` 在读档后布置，共64丛丘陵、36丛山坡、32丛球场边缘灌木。使用固定种子、斜率和土地占用过滤，避开水面、陡坡、建筑种植邻近区域及球道/果岭/发球台。低矮灌木不增加人物或高尔夫球碰撞。按40米空间块和种类合批，45米切换至远景、110米停止绘制；灌木运行时没有逐株处理循环。

编辑源：`art/blender/tree_pack_samples.blend`，十五组模型按种类/LOD 排列；每个 GLB 的原点为根部。生成脚本会覆盖该衍生文件与本目录十五个 GLB，手工精修时应另存源文件：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --disable-autoexec --python scripts/tools/build_tree_pack_samples.py
```

预览：`./tools/preview_tree_pack.ps1`，或打开 `scenes/preview/tree_pack_preview.tscn` 后按 F6。包含三种树、两种灌木和人物比例参考。正式地图实景、验证和性能范围见 `docs/validation/2026-09-11-tree-pack-samples.md`。
