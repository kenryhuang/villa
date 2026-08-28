# Visible Agent NPC Binding Fix Design

## Problem

`NpcNorthwest` and `NpcEast` do not reliably appear as their intended Agent characters. They can lack a readable nameplate and their nearby dialogue prompt can appear absent.

The full scene configures all three Agent IDs correctly after startup, but each NPC enters the scene tree with the scene default `villager_id` of `lao_li`. Every NPC therefore registers with `VillagerSystem` under the same key during its own `_ready()`. Later Agent configuration changes the node property but does not repair that initial registration. The result is a single effective legacy registration associated with Lao Li.

The dialogue prompt is also too close to the nameplate. When it becomes visible, the two elements overlap, and the prompt can be hidden by the player or world geometry from common approach angles.

## Selected Approach

Give every NPC instance its final `villager_id` in `main.tscn`, before the child `_ready()` callbacks run:

- `NpcNorthwest`: `farmer_ahe`
- `NpcSouth`: `lao_li`
- `NpcEast`: `xuezhe_lin`

Keep the existing Agent binding in `Main` as the authoritative runtime association and display-name setup. This avoids changing the initialization contract for other non-Agent NPC scenes.

Keep the nameplate visible while the dialogue prompt is active. Move the prompt above the nameplate and render its icon without depth testing at a higher render priority, so the player model, terrain, and nameplate cannot conceal it.

## Runtime Flow

1. Godot instantiates the three NPC scene instances with distinct exported IDs.
2. Each NPC registers itself with `VillagerSystem` using its correct ID during `_ready()`.
3. `Main._setup_npcs()` positions each NPC, binds the corresponding Agent, assigns its display name, and enables Agent dialogue.
4. The NPC continuously evaluates horizontal distance to the player.
5. Within the existing three-metre interaction distance, the dialogue icon appears above the always-visible nameplate and remains clickable.
6. Leaving the interaction range hides only the dialogue icon; the nameplate remains visible.

## Scope

This fix does not change Agent scheduling, dialogue transport, NPC models, interaction distance, or the legacy villager registration API. It only corrects initial instance identity and presentation of the existing dialogue affordance.

## Verification

Automated regression coverage will verify:

- The three main-scene instances carry distinct expected IDs before `Main` performs Agent configuration.
- `VillagerSystem` receives one registration for each expected Agent NPC ID.
- Agent configuration preserves the expected IDs and display names.
- At interaction range, both the nameplate and dialogue prompt are visible.
- The prompt is positioned above the nameplate and uses the intended depth/render ordering.
- Leaving interaction range hides the prompt without hiding the nameplate.

A full-scene visual probe will then place the player near Northwest and East independently and confirm that the correct name and complete dialogue icon are visible in rendered output.
