# 协作偏好

- 用户要求：不要使用任何 skills。模型直接按自己的方式计划、实现和验证。
- 在当前 3D 开发分支上直接推进已经授权的工作，不为常规实现选择反复请求确认。

- 后续持续在 `feature/3d-farm-preview` 分支开发；除非用户明确要求，不新建分支、不切换或合并到 main。
- 正式 3D 入口为 `scenes/farm3d/main.tscn`，对应脚本在 `scripts/farm3d/`；`preview` 仅放独立美术预览。目录职责与启动方式见根目录 `README.md`。
