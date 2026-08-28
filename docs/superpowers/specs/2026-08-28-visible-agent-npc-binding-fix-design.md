# Visible Agent NPC Presentation Fix Design

## Problem

All three visible NPCs are correctly bound to their Agents and can open Agent dialogue when their bodies are clicked. `NpcNorthwest` and `NpcEast`, however, do not render their names or nearby dialogue icons; only Lao Li does.

Rendered-scene diagnostics show that every nameplate has the correct text and is visible in the scene tree. Under the GL Compatibility renderer, only one of the three transparent `Label3D` instances is drawn while all three share the same render priority. Assigning distinct priorities makes all three names render immediately.

The dialogue prompt uses the same default priority across all NPC instances, still participates in depth testing, and sits close enough to overlap the nameplate. This makes it vulnerable to the same priority conflict and to concealment by the player or world geometry.

## Selected Approach

Keep the existing Agent binding, click interaction, dialogue transport, NPC identity, and range calculation unchanged.

Assign a distinct visual priority pair to every Agent NPC binding: one priority for the nameplate and the next priority for its prompt. Keep the nameplate visible while the prompt is active. Move the prompt above the nameplate and disable depth testing for the icon so the player model, terrain, other Agent labels, and the nameplate cannot conceal it.

## Runtime Flow

1. `Main._setup_npcs()` positions each NPC and resolves its Agent display name as before.
2. `Main` preserves the existing three-argument `Npc.configure_agent()` contract, then passes the binding's visual priority to `Npc.configure_agent_visual_priority()`.
3. The NPC applies that priority to its nameplate and the next priority to its dialogue icon.
4. The nameplate remains visible whenever the NPC is alive.
5. Within the existing three-metre range, the prompt appears above the nameplate and remains clickable.
6. Leaving range hides only the prompt.

## Scope

This fix changes presentation only. It does not alter Agent scheduling, dialogue transport, NPC registration, click handling, interaction distance, or character models.

## Verification

Automated regression coverage will verify:

- The three Agent bindings declare distinct nameplate priorities.
- Agent configuration applies the expected name and prompt priority pair to every NPC.
- At interaction range, both the nameplate and prompt remain visible.
- The prompt is above the nameplate and ignores world depth.
- Leaving range hides the prompt without hiding the nameplate.

A rendered full-scene probe will confirm that all three names appear at once and that approaching Northwest and East shows a complete speech-bubble icon above their names.
