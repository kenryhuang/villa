# Visible Agent NPC Binding Fix Design

## Problem

`NpcNorthwest` and `NpcEast` do not reliably appear as their intended Agent characters. They can lack a readable nameplate and their nearby dialogue prompt can appear absent.

The full scene configures all three Agent IDs correctly after startup, but each NPC enters the scene tree with the scene default `villager_id` of `lao_li`. NPC child `_ready()` callbacks also run before `Main` creates `VillagerSystem`, so their attempted self-registration cannot succeed. Later Agent configuration changes the node property but does not register the node with the newly created system.

Rendered-scene diagnostics show that every nameplate has the right text and is visible in the scene tree, but the GL Compatibility renderer draws only one of the three transparent `Label3D` instances while they share the same render priority. Giving the three labels distinct priorities makes all names render immediately.

The dialogue prompt is also too close to the nameplate. When it becomes visible, the two elements overlap, and the prompt can be hidden by the player or world geometry from common approach angles.

## Selected Approach

Give every NPC instance its final `villager_id` in `main.tscn`, before the child `_ready()` callbacks run:

- `NpcNorthwest`: `farmer_ahe`
- `NpcSouth`: `lao_li`
- `NpcEast`: `xuezhe_lin`

Keep the existing Agent binding in `Main` as the authoritative runtime association and display-name setup. After Agent configuration, `Main` explicitly registers each node with the already-created `VillagerSystem`, using the same Agent ID.

Assign a distinct visual priority pair to every binding: one priority for the nameplate and the next priority for its prompt. Keep the nameplate visible while the dialogue prompt is active. Move the prompt above the nameplate and render its icon without depth testing, so the player model, terrain, other Agent labels, and the nameplate cannot conceal it.

## Runtime Flow

1. Godot instantiates the three NPC scene instances with distinct exported IDs.
2. `Main` creates `VillagerSystem` during its own initialization.
3. `Main._setup_npcs()` positions each NPC, binds the corresponding Agent, assigns its display name and visual priority pair, enables Agent dialogue, and registers the node with `VillagerSystem` under its correct ID.
4. The NPC continuously evaluates horizontal distance to the player.
5. Within the existing three-metre interaction distance, the dialogue icon appears above the always-visible nameplate and remains clickable.
6. Leaving the interaction range hides only the dialogue icon; the nameplate remains visible.

## Scope

This fix does not change Agent scheduling, dialogue transport, NPC models, interaction distance, or the legacy villager registration API. It only corrects instance identity, registration timing, and presentation of the existing dialogue affordance.

## Verification

Automated regression coverage will verify:

- The three main-scene instances carry distinct expected IDs before `Main` performs Agent configuration.
- `VillagerSystem` receives one registration for each expected Agent NPC ID.
- Agent configuration preserves the expected IDs and display names.
- The three nameplates use distinct render priorities.
- At interaction range, both the nameplate and dialogue prompt are visible.
- The prompt is positioned above the nameplate and uses the intended depth/render ordering.
- Leaving interaction range hides the prompt without hiding the nameplate.

A full-scene visual probe will then place the player near Northwest and East independently and confirm that the correct name and complete dialogue icon are visible in rendered output.
