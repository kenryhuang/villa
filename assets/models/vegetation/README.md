# 手绘风格橡树

`painted_oak.glb` 是独立的完整 3D 橡树，参考项目原有 `assets/vegetation/tree-oak-large.png` 的轮廓、根干结构和绘制颜色。

- 根、干、主枝为同一个连续平滑网格，带纵向树皮起伏、笔触色差和根部苔色。
- 树冠由 7,460 片有弯曲和圆润叶缘的独立叶片组成；不存在可见的球体或多面体树冠外壳。
- 叶片的 UV 采样原橡树图片里的有效叶冠区域，保留原美术笔触；整棵树不使用朝向相机的图片。
- 两个网格、两个材质，手绘图片内嵌于 GLB。顶点色保存树皮绘制与树冠上下色彩过渡。
- Godot 专用后导入脚本 `scripts/tools/import_painted_oak.gd` 启用材质的顶点色参与反照率，避免原生导入后树干变白。请保留 `.glb.import` 的 `import_script/path` 设置。

可复用游戏场景：`scenes/vegetation/painted_oak.tscn`。根部为地面原点，GLB Y 向上，米为单位。树干简化碰撞位于层 1；镜头专用树冠碰撞位于层 4，玩家碰撞遮罩应不包含层 4。

源文件：`art/blender/painted_oak.blend`，其中 `Oak • sculpt and painted leaves` 集合包含模型，`Studio • not exported` 仅供源文件预览。手绘参考图片已打包，可直接打开编辑。

运行 `./tools/preview_tree.ps1` 或在 Godot 中打开 `scenes/preview/tree_3d_preview.tscn` 后按 F6。按住右键环绕，滚轮缩放，空格切换自动转台，1/2/3 选择正侧背面，R 复位，F12 截图。

重新生成（覆盖本树的生成资产，手工精修版本应先另存）：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --python scripts/tools/build_painted_oak.py -- --render
```

这是单树造型和材质评审版本，优先保留叶片细节；Godot 导入会生成 LOD，但尚未验证大量树木同时显示的性能。旧农庄原型模型保持独立，避免相互覆盖。
