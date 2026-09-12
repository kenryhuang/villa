# 鸡舍

正式入口：`scenes/farm3d/buildings/chicken_coop.tscn`。

参考原游戏 `assets/buildings/painted/chicken_coop/`：暖色木板、红陶瓦顶、石墩、入口斜坡、金属网窗及小围栏。建筑与院子完整落在原有 3×3 占地内，不包含旧图片的地面或阴影。两只母鸡是独立模型，具有可活动的头部和双脚。

- `chicken_coop.glb`：五个建造阶段分组，27,324 三角面；木板、陶瓦、石材三张 512×512 原创纹理。
- `hen.glb`：单只母鸡 3,398 三角面，两只共用模型资源；身体、头、左右脚分别保留节点，供游戏播放走路和啄食。
- `chicken_coop_Coop *.png` 及 `.import`：Godot 提取的运行贴图和导入配置，随 GLB 一同保留。
- `art/blender/chicken_coop.blend`：可编辑源文件，纹理已打包；灯光与相机仅供编辑查看，不导出。

重建：

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --disable-autoexec --python scripts/tools/build_chicken_coop.py
```

生产沿用原 `ProductionSystem`：每日 1 份动物饲料换 2 枚鸡蛋，最多暂存 6 枚；缺料、满仓或维护停产不扣饲料。建造成本仍是木板×8、石砖×4、绳索×1。饲料、鸡蛋、归属和维护状态沿用现有存档。

从南面靠近鸡舍后点击，添加 1 / 5 份饲料或收取鸡蛋；也可以直接点击院前的蛋篮收取。面板打开时暂停时间，Esc 恢复。饲料可由风车加工或从市场购买，鸡蛋可交易或供食品工坊使用。NPC 拥有的鸡舍由其主人管理。

鸡只动画不影响产蛋判定，45 米外停止逐帧动画；建造预览和未完成建筑不展示活动母鸡。建筑按建造阶段合并网格，使用 Godot 自动 LOD。

验证：`tests/run_3d_chicken_coop_tests.gd -- --farm-test`；GPU 截图：`tests/capture_3d_chicken_coop.gd -- --farm-test`。
