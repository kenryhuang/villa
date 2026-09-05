# Painted Oak Implementation Plan

**Goal:** 做出匹配原手绘风格的一棵真实立体橡树。

**Architecture:** 独立 Blender 建模脚本生成根干枝连续网格与带手绘色彩的叶片，导出单树资源。Godot 独立树场景封装模型与简化碰撞，观察场景提供旋转、缩放、自动转台和实际截图。

**Tech Stack:** Blender 5.2 Python, glTF 2.0, Godot 4.7。使用 subagent-driven-development 分别完成模型与观察场景，再审查整合。

- [x] scripts/tools/build_painted_oak.py：生成弯曲分枝与根系，合并平滑；加入树皮色彩、细碎叶片与黄绿到深绿层次；导出 assets/models/vegetation/painted_oak.glb 与 art/blender/painted_oak.blend。
- [x] scenes/vegetation/painted_oak.tscn：独立可复用树资源；scenes/preview/tree_3d_preview.tscn 与 scripts/preview/tree_3d_preview.gd：单树可旋转缩放观察；tools/preview_tree.ps1：启动与截图。
- [x] 实际导入模型、重新打开 Blender 文件、正面/侧面/背面/近景截图检查。修正 Godot 默认没有启用材质顶点色的问题，以专用后导入脚本保留手绘色彩。
- [x] 更新资源说明，保留当前 3D 分支和本轮修改，交付单树预览供用户检查。
