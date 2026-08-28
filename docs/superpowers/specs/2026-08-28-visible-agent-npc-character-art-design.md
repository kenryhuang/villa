# Visible Agent NPC Character Art Design

## Goal

Replace the three visible Agent NPC placeholder capsules with distinct hand-painted characters that communicate their roles at a glance. NPCs use four static directions and do not include walking animation in this phase.

## Character Direction

All three characters match the existing player art: warm, cozy, lightly chibi proportions; painted lighting and fabric detail; a clear silhouette at the current isometric camera distance; and a transparent background. Characters share comparable body scale and grounding so they feel like one cast.

### Ahe — Farmer

- Young woman with a practical, dependable silhouette.
- Warm green headscarf, cream work shirt, brown-green apron, sturdy boots, and a seed satchel.
- Earthy green, wheat, cream, and brown palette.
- No held tool, so future farming actions can add tools without conflicting with the base model.

### Lao Li — Merchant

- Middle-aged man with a slightly broader silhouette.
- Chestnut vest, dark trousers, neat moustache, waist ledger, and coin pouch.
- Chestnut, burgundy, brass, cream, and charcoal palette.
- Friendly but shrewd expression that supports his talkative merchant personality.

### Scholar Lin — Explorer-Scholar

- Young man with a slimmer, field-ready silhouette.
- Teal-blue short coat, round glasses, light backpack, rolled map, and notebook.
- Teal, navy, parchment, leather brown, and muted gold palette.
- Curious but careful expression, combining exploration equipment with scholarly details.

## Asset Format

Each character uses one transparent PNG atlas:

- `assets/characters/npcs/farmer_ahe/farmer_ahe_directions.png`
- `assets/characters/npcs/lao_li/lao_li_directions.png`
- `assets/characters/npcs/xuezhe_lin/xuezhe_lin_directions.png`

The atlas is a two-by-two grid with equal-sized cells:

| Cell | Direction |
|---|---|
| Top left | Back / north |
| Top right | Right / east |
| Bottom left | Front / south |
| Bottom right | Left / west |

Every cell contains one neutral standing pose. There are no animation frames. Left and right are authored views rather than runtime mirroring, preserving asymmetric accessories such as satchels, ledgers, maps, and backpacks.

## Runtime Architecture

Add `scripts/visual/npc_visual.gd`, a focused `NpcVisual` component based on `Sprite3D`, beneath the shared NPC scene. It owns atlas validation, region selection, billboard configuration, and last-facing state. It derives `pixel_size` from the atlas cell height against a fixed character world height, so generated source resolution does not alter in-game scale.

`Main.AGENT_NPC_BINDINGS` receives a visual atlas path for each Agent. After the existing three-argument `configure_agent()` call succeeds, `Main` loads the atlas and configures `NpcVisual` through a separate visual method. This preserves the stable dialogue-binding interface.

`Npc` passes its planar velocity and the active camera basis to `NpcVisual`. The component converts motion into four camera-relative sectors: front, back, left, and right. A moving NPC switches directly to the corresponding static atlas cell. A stopped NPC keeps its last direction; the initial direction is front.

The sprite uses billboard rendering, opaque alpha prepass, no shadow, unshaded color, and linear filtering to match the existing player presentation. Collision, physics, nameplates, dialogue prompts, click handling, Agent routing, and schedules remain unchanged.

## Failure Behavior

The existing capsule mesh remains available as a fallback. `NpcVisual` starts hidden and validates that its atlas exists, has usable dimensions, and divides evenly into a two-by-two grid. Only successful configuration shows the sprite and hides the capsule. Invalid assets produce a clear Godot error while leaving the NPC visible and interactable as a capsule.

## Verification

Automated tests verify:

- Every Agent binding declares the expected atlas path.
- All three atlas files load and divide into equal two-by-two cells.
- `NpcVisual` begins facing front and maps camera-relative motion to all four directions.
- Stopping preserves the last direction.
- Successful configuration shows the sprite and hides the capsule.
- Invalid configuration keeps the sprite hidden and the capsule visible.
- Nameplates, dialogue prompts, collision, and dialogue behavior remain unchanged.

Rendered full-scene captures verify the three role silhouettes, relative scale, transparent edges, four direction cells, nameplate clearance, and dialogue-icon clearance at the production camera angle.

## Out of Scope

- Walking, idle, work, or conversation animation.
- Held farming, trading, or exploration action props.
- Portrait art for the dialogue window.
- Changes to NPC AI, schedules, physics, collision, or dialogue behavior.
