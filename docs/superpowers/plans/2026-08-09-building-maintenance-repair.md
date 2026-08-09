# Building Maintenance Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the non-interactive “修” marker with visible building damage and a complete 14-day, in-panel, three-second repair flow.

**Architecture:** `ProductionSystem` remains the authoritative maintenance state machine and repair clock. `EconomyProgressionSystem` calculates footprint/upgrade-scaled quotes and delegates atomic repair starts. A focused `BuildingMaintenanceVisual` renders damage and repair animation, while `BuildingStatusPanel` exposes the same command inside the building UI.

**Tech Stack:** Godot 4.7, typed GDScript, `.tscn` scenes, SVG Sprite3D overlays, EventBus, headless GDScript tests.

---

### Task 1: Maintenance states and 14-day lifecycle

**Files:**
- Modify: `scripts/systems/production_system.gd`
- Modify: `tests/test_production_system.gd`

- [x] **Step 1: Write failing lifecycle tests**

Add boundary assertions:

```gdscript
assertions.equal(production.get_maintenance_due_day(building), 15, "new building gets 14-day deadline")
production.begin_day(14)
assertions.equal(production.get_maintenance_state(building), "warning", "one day remaining warns")
production.begin_day(15)
assertions.equal(production.get_maintenance_state(building), "overdue", "deadline stops building")
assertions.truthy(production.is_maintenance_paused(building), "overdue maintenance pauses production")
```

- [x] **Step 2: Run `godot --headless --path . --script res://tests/run_economy_system_tests.gd`**

Expected: FAIL because the state API is missing and the interval is still 7 days.

- [x] **Step 3: Implement the state model**

Set `MAINTENANCE_INTERVAL_DAYS := 14` and `MAINTENANCE_WARNING_DAYS := 1`. Add `get_maintenance_state()`, `get_maintenance_days_remaining()`, and `is_maintenance_paused()`. Include state, days remaining, and repair seconds in snapshots. Replace production/effect pause checks with `is_maintenance_paused()`.

```gdscript
func get_maintenance_state(building: BuildingInstance) -> String:
    var key := building_key(building) if building != null else ""
    if repair_remaining_seconds.has(key): return "repairing"
    var remaining := get_maintenance_due_day(building) - _current_day
    if remaining <= 0: return "overdue"
    if remaining <= MAINTENANCE_WARNING_DAYS: return "warning"
    return "normal"
```

- [x] **Step 4: Run the production suite and require PASS**

- [x] **Step 5: Commit `feat: add building maintenance lifecycle`**

### Task 2: Scaled quotes and timed atomic repair

**Files:**
- Modify: `scripts/systems/production_system.gd`
- Modify: `scripts/systems/economy_progression_system.gd`
- Modify: `tests/test_economy_progression.gd`
- Modify: `tests/test_production_system.gd`

- [x] **Step 1: Write failing quote and timing tests**

Cover all footprint tiers, summed upgrade levels, warning-period repair, exact one-time deductions, double-start rejection, and the 3-second boundary.

```gdscript
production.set_maintenance_due_day(building, production.get_current_day() + 1)
assertions.truthy(progression.maintain(building), "warning-period repair starts")
assertions.equal(production.get_maintenance_state(building), "repairing", "repair is timed")
assertions.truthy(not progression.maintain(building), "repair cannot start twice")
production.advance_repair_time(2.9)
assertions.equal(production.get_maintenance_state(building), "repairing", "repair does not finish early")
production.advance_repair_time(0.1)
assertions.equal(production.get_maintenance_state(building), "normal", "repair finishes at three seconds")
```

- [x] **Step 2: Run progression and production suites and verify RED**

- [x] **Step 3: Implement quote policy and timed repair**

Quote table: 1–2 cells = 20 gold + 1 wood + 1 stone; 3–4 cells = 35 + 2 + 2; 5+ cells = 55 + 3 + 3. Add `10 × total upgrade level` gold and `ceil(total upgrade level / 2)` of each material. `ProductionSystem.maintain()` receives the quote, commits payment atomically, records `3.0` seconds, and uses `PROCESS_MODE_ALWAYS`. `advance_repair_time(delta)` completes by setting due day to current day + 14.

- [x] **Step 4: Run both suites and require PASS**

- [x] **Step 5: Commit `feat: add timed scaled building repairs`**

### Task 3: Versioned repair persistence

**Files:**
- Modify: `scripts/systems/production_system.gd`
- Modify: `tests/test_economy_progression.gd`
- Modify: `tests/test_production_chain_integration.gd`

- [x] **Step 1: Write failing persistence tests**

```gdscript
var saved := production.to_dict()
assertions.equal(saved.version, 2, "maintenance writes version two")
assertions.equal(saved.repairing[0].remaining_seconds, 2.0, "repair time persists")
```

Also test strict malformed-value rejection, version-one migration with no active repairs, restored continuation, and no second payment.

- [x] **Step 2: Run economy progression and production chain suites and verify RED**

- [x] **Step 3: Implement version two**

Write exact keys `version`, `maintenance`, `speed_accumulators`, and `repairing`. Accept strict version-one payloads and migrate them to an empty repairing dictionary. Validate unique canonical building keys and finite remaining seconds in `(0, 3]`. Remove repair records when a building is unregistered.

- [x] **Step 4: Run both suites and require PASS**

- [x] **Step 5: Commit `feat: persist in-progress building repairs`**

### Task 4: Damage overlays and repair hammer

**Files:**
- Create: `assets/buildings/maintenance/maintenance_warning.svg`
- Create: `assets/buildings/maintenance/maintenance_broken.svg`
- Create: `scripts/buildings/building_maintenance_visual.gd`
- Modify: `scripts/buildings/building_instance.gd`
- Create: `tests/test_building_maintenance_visual.gd`
- Modify: `tests/run_building_system_tests.gd`
- Modify: `tests/test_building_construction_state.gd`

- [x] **Step 1: Write failing visual tests**

Assert normal hides damage, warning shows the subtle overlay, overdue shows the broken overlay, repairing shows the painted hammer, the component runs while paused, and `EconomyIndicator.text` is never “修”.

```gdscript
visual.set_state("warning", 0.0)
assertions.truthy(visual.warning_overlay.visible, "warning shows subtle damage")
visual.set_state("repairing", 1.5)
assertions.truthy(visual.hammer_pivot.visible, "repairing shows painted hammer")
```

- [x] **Step 2: Run building suite and verify RED**

- [x] **Step 3: Implement `BuildingMaintenanceVisual`**

Use two transparent, irregular hand-painted SVG overlays. Scale them from `visual_size` and ground anchor. Reuse the painted construction hammer texture/shader with a 0.6-second pivot cycle, omit the construction progress disk, and add a 0.35-second completion fade. Expose only `configure()`, `set_state()`, and `play_completion()`.

- [x] **Step 4: Integrate with `BuildingInstance`**

Add `set_maintenance_visual_state()`. The legacy indicator keeps only `full`; `should_play_activity()` returns false for overdue/repairing.

- [x] **Step 5: Run building suite and require PASS**

- [x] **Step 6: Commit `feat: render building damage and repair animation`**

### Task 5: In-building maintenance card

**Files:**
- Create: `scripts/ui/building_maintenance_card.gd`
- Create: `scenes/ui/economy/building_maintenance_card.tscn`
- Modify: `scripts/ui/building_status_panel.gd`
- Modify: `scenes/ui/economy/building_status_panel.tscn`
- Modify: `scripts/ui/building_economy_ui.gd`
- Modify: `tests/test_building_economy_ui.gd`

- [ ] **Step 1: Write failing UI tests**

Test normal, warning, overdue, repairing, insufficient assets, direct click, and repair progress. Warning/overdue/repairing buildings must open on the status page.

```gdscript
ui.open_for(building)
assertions.truthy(ui.status_panel.visible, "maintenance attention opens status page")
assertions.equal(card.action_button.text, "开始维修", "overdue exposes repair")
card.action_button.pressed.emit()
assertions.equal(production.get_maintenance_state(building), "repairing", "button starts repair")
```

- [ ] **Step 2: Run economy UI suite and verify RED**

- [ ] **Step 3: Build and wire the card**

The compact card contains a colored state dot, state/deadline labels, gold/wood/stone ownership rows, a progress bar, action button, and feedback. Pass progression into `BuildingStatusPanel`. Refresh the quote immediately before commands. Add `well` to supported status buildings. Crafting buildings under maintenance default to status but retain both tabs.

- [ ] **Step 4: Run economy UI and responsive suites and require PASS**

- [ ] **Step 5: Commit `feat: add building repair controls`**

### Task 6: Service overview, notifications, and synchronization

**Files:**
- Modify: `scripts/systems/economy_progression_system.gd`
- Modify: `scripts/ui/service_panel.gd`
- Modify: `scripts/systems/economy_notification_system.gd`
- Modify: `scripts/systems/production_system.gd`
- Modify: `tests/test_service_panel.gd`
- Modify: `tests/test_economy_notifications.gd`
- Modify: `tests/test_main_farming_building_integration.gd`

- [ ] **Step 1: Write failing integration tests**

Assert a single warning notification, a single overdue notification, service-row states, visual refresh after direct date jumps, and the same repair command from both UI locations.

- [ ] **Step 2: Run economy UI, economy system, and main integration suites and verify RED**

- [ ] **Step 3: Synchronize consumers**

Service rows show `距到期 N 天`, `可提前维修`, `破损停产`, or `维修中 %.1f 秒`. Notifications distinguish warning from overdue. Every daily/maintenance event refreshes the building visual and open UI from the production snapshot; no consumer recreates state locally.

- [ ] **Step 4: Run affected suites and require PASS**

- [ ] **Step 5: Commit `feat: integrate maintenance status across game UI`**

### Task 7: Final verification

**Files:**
- Modify only when a verification failure identifies an in-scope defect.

- [ ] **Step 1: Run `git diff --check` and inspect `git status --short`**

- [ ] **Step 2: Run affected suites with full output**

```powershell
godot --headless --path . --script res://tests/run_economy_system_tests.gd 2>&1 | Out-String
godot --headless --path . --script res://tests/run_economy_progression_tests.gd 2>&1 | Out-String
godot --headless --path . --script res://tests/run_building_system_tests.gd 2>&1 | Out-String
godot --headless --path . --script res://tests/run_economy_ui_tests.gd 2>&1 | Out-String
godot --headless --path . --script res://tests/run_economy_ui_responsive_tests.gd 2>&1 | Out-String
godot --headless --path . --script res://tests/run_economy_system_tests.gd 2>&1 | Out-String
godot --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd 2>&1 | Out-String
```

- [ ] **Step 3: Re-read every design acceptance criterion**

Confirm no “修” text, warning/overdue visuals, in-building repair button, scaled cost, resumable three-second repair, 14-day reset, paused queue preservation, service overview, notifications, and version-one migration.

- [ ] **Step 4: Commit any final correction as `fix: complete building maintenance repair flow`**
