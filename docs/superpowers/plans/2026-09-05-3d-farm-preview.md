# 3D Farm Preview Implementation Plan

> Execute with subagent-driven-development: independent modeling and Godot preview implementation, followed by integration review.

**Goal:** 在新分支交付可编辑的玩家、树、田地和谷物 3D 模型及可运行的第三人称预览。

**Architecture:** Blender 脚本生成源文件与 GLB，Godot 独立场景加载环境与角色，单独的控制器负责移动和镜头。预览不连接生产游戏保存或 Agent。

**Tech Stack:** Blender 5.2 Python, glTF 2.0, Godot 4.7 GDScript。

- [x] 从 main 创建 feature/3d-farm-preview；确认已有玩家逻辑基线 35 项通过。
- [x] 创建 scripts/tools/build_3d_farm_assets.py，以固定种子生成 assets/models/farm_preview 下的 GLB 和 art/blender/farm_preview.blend（源目录放置 .gdignore）。角色草帽背带裤，导出 Idle/Walk；树木分枝树冠；田地垄沟；谷物绿苗和成熟两阶段。环境以模型副本组成，批量合并静态网格降低绘制开销。
- [x] 创建 scenes/preview/farm_3d_preview.tscn 与 scripts/preview 下脚本，加载 farm_environment.glb 和 player_farmer.glb。添加玩家胶囊、地面及树干碰撞、SpringArm3D 透视镜头、移动跳跃、中文控制说明和复位；支持 --capture-preview=路径 输出实际渲染。
- [x] 添加 tools/preview_3d.ps1 方便启动；测试资源加载、玩家落地、移动与镜头碰撞。运行 Godot headless 导入和定向测试；用实际图形后端捕获预览截图并人工检查模型效果。
- [x] 更新预览说明与验证记录。检查差异、资产大小与 Git 分支，保留新分支供后续开发。
