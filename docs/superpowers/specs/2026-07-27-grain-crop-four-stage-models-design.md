# 谷物作物四阶段低多边形模型设计

## 目标

为 FarmingSystem 制作首套真正的 Godot 原生低多边形作物资产，并验证四阶段随生长进度正确切换。模型无需外部图片或 Blender 文件，可在 Godot 场景编辑器中直接查看和调整。

## 资产

```text
assets/crops/grain/
├── materials/
│   ├── seed_brown.tres
│   ├── sprout_green.tres
│   ├── leaf_green.tres
│   ├── stalk_green.tres
│   ├── stalk_gold.tres
│   └── grain_gold.tres
├── grain_stage_0_seed.tscn
├── grain_stage_1_sprout.tscn
├── grain_stage_2_growing.tscn
└── grain_stage_3_mature.tscn
```

四个场景根节点均为 Node3D，模型中心对准单个1×1网格中心，底部为 y=0，不包含碰撞体。

## 四阶段造型

- 种子：3颗棕褐色扁球谷粒，最大高度0.1、覆盖直径0.4。
- 幼苗：中心嫩茎和3片倾斜嫩叶，高度约0.32、覆盖直径0.45。
- 生长期：3根绿色低面数茎秆，每根带两片叶和未成熟小穗，高度约0.72、覆盖直径0.62。
- 成熟期：5根金黄色茎秆，每根带下垂叶片和由多颗谷粒组成的麦穗，高度约1.05、覆盖直径0.78。

茎使用低径向段数 CylinderMesh，谷粒使用低面数 SphereMesh，叶片使用压扁的 BoxMesh 并旋转。所有材质为高粗糙度、非金属材质，接受场景光照和阴影。

## 数据接口

CropData 新增：

```gdscript
@export var stage_scenes: Array[String] = []
```

CropInstance 的阶段数量优先使用 `stage_scenes`，为空时回退到 `stage_textures`。现有作物数据和测试仍可继续使用字符串阶段标记。

## FarmingSystem 集成

- 当前阶段存在有效 `stage_scenes` 路径时，实例化对应 PackedScene。
- 阶段变化时释放旧阶段节点并实例化新阶段节点。
- 模型根节点放在格子中心的真实地形高度。
- 模型节点记录 crop ID、stage 和 scene path 元数据，便于测试与调试。
- 没有 stage scene 或资源加载失败时，继续使用现有 MeshInstance3D 色块回退方案。
- `get_crop_visual()` 返回 Node3D，而不限定 MeshInstance3D。

## 验收

- 四个场景均可独立加载。
- 每阶段至少包含一个 MeshInstance3D，节点复杂度随阶段增加。
- 合并AABB高度和直径不超过单格限制。
- 四阶段材质颜色可区分。
- FarmingSystem 能从阶段0依次切换到阶段3。
- 读档视觉重建能恢复正确阶段模型。
- 独立种植视觉场景同时展示四个真实模型。
- 图形截图中能明确识别种子、叶片、茎秆和成熟麦穗。
