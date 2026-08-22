# HUD Shell and Message Stream Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Replace the scattered HUD mode menu and transient notifications with direct mouse mode controls and one collapsible right-side message stream.

**Architecture:** Main owns a session-scoped HudMessageBus and injects it into the existing HUD scene. HudMessageStream owns only presentation, unread and follow state; VillaHud keeps compatibility methods but forwards them to the bus. EconomyNotificationUI keeps the persistent center and drops its independent ToastStack.

**Tech Stack:** Godot 4.7, GDScript, Control/CanvasLayer scenes, existing TestAssert runners.

---

### Task 1: Session-scoped HudMessageBus

**Files:**
- Create: scripts/ui/hud_message_bus.gd
- Create: tests/test_hud_message_bus.gd
- Create: tests/run_hud_shell_tests.gd

- [ ] **Step 1: Write the failing message-bus test**

Create a real bus, publish deterministic records with metadata timestamp_msec, and assert validation, order, merge identity and the 100-record cap:

~~~gdscript
extends RefCounted

const BusScript := preload("res://scripts/ui/hud_message_bus.gd")

func run(assertions: TestAssert, tree: SceneTree) -> void:
    var bus := BusScript.new()
    tree.root.add_child(bus)
    assertions.truthy(not bus.publish("", "info", "missing source"), "empty source is rejected")
    assertions.truthy(not bus.publish("debug", "unknown", "bad level"), "unknown severity is rejected")
    assertions.truthy(bus.publish("farming", "success", "已播种", {"timestamp_msec": 1000}), "valid message publishes")
    assertions.truthy(bus.publish("farming", "success", "已播种", {"timestamp_msec": 1500}), "same message merges")
    var recent: Array[Dictionary] = bus.get_recent()
    assertions.equal(recent.size(), 1, "one-second duplicate keeps one record")
    assertions.equal(int(recent[0].count), 2, "merged record increments count")
    assertions.truthy(bus.publish("farming", "success", "已播种", {"timestamp_msec": 2501}), "late duplicate publishes")
    assertions.equal(bus.get_recent().size(), 2, "outside merge window creates a record")
    for index in range(105):
        bus.publish("debug", "debug", "trace %d" % index, {"timestamp_msec": 3000 + index})
    recent = bus.get_recent()
    assertions.equal(recent.size(), 100, "message history is capped")
    assertions.equal(str(recent[-1].text), "trace 104", "newest record remains last")
    bus.free()
~~~

The runner loads this suite first and exits with the established PASS/FAIL summary format.

- [ ] **Step 2: Run the new runner and verify RED**

Run:

~~~powershell
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script tests/run_hud_shell_tests.gd
~~~

Expected: parser/load failure because hud_message_bus.gd does not exist.

- [ ] **Step 3: Implement the minimal bus**

Implement these public contracts:

~~~gdscript
class_name HudMessageBus
extends Node

signal message_added(record: Dictionary)
signal message_updated(record: Dictionary)
signal message_rejected(reason: String)

const VALID_SEVERITIES := ["info", "success", "warning", "error", "debug"]
const MAX_RECORDS := 100
const MERGE_WINDOW_MSEC := 1000

var _records: Array[Dictionary] = []
var _next_id := 1

func publish(source: String, severity: String, text: String, metadata: Dictionary = {}) -> bool:
    source = source.strip_edges()
    text = text.strip_edges()
    if source.is_empty() or text.is_empty() or severity not in VALID_SEVERITIES:
        message_rejected.emit("invalid_message")
        return false
    var timestamp_msec := int(metadata.get("timestamp_msec", Time.get_ticks_msec()))
    var target_type := str(metadata.get("target_type", ""))
    var target_id := str(metadata.get("target_id", ""))
    if not _records.is_empty():
        var previous: Dictionary = _records[-1]
        if (
            str(previous.source) == source
            and str(previous.severity) == severity
            and str(previous.text) == text
            and str(previous.target_type) == target_type
            and str(previous.target_id) == target_id
            and timestamp_msec - int(previous.timestamp_msec) <= MERGE_WINDOW_MSEC
        ):
            previous.count = int(previous.count) + 1
            previous.timestamp_msec = timestamp_msec
            _records[-1] = previous
            message_updated.emit(previous.duplicate(true))
            return true
    var record := {
        "message_id": "hud-%d" % _next_id,
        "source": source,
        "severity": severity,
        "text": text,
        "timestamp_msec": timestamp_msec,
        "game_time": str(metadata.get("game_time", "")),
        "target_type": target_type,
        "target_id": target_id,
        "count": 1,
    }
    _next_id += 1
    _records.append(record)
    if _records.size() > MAX_RECORDS:
        _records.pop_front()
    message_added.emit(record.duplicate(true))
    return true

func get_recent() -> Array[Dictionary]:
    return _records.duplicate(true)

func clear() -> void:
    _records.clear()
~~~

- [ ] **Step 4: Run the runner and verify GREEN**

Expected: HudMessageBus checks pass with no test failure.

- [ ] **Step 5: Commit**

~~~powershell
git add scripts/ui/hud_message_bus.gd tests/test_hud_message_bus.gd tests/run_hud_shell_tests.gd
git commit -m "feat: add session hud message bus"
~~~

### Task 2: Collapsible HudMessageStream

**Files:**
- Create: scripts/ui/hud_message_stream.gd
- Create: scenes/ui/hud_message_stream.tscn
- Create: tests/test_hud_message_stream.gd
- Modify: tests/run_hud_shell_tests.gd

- [ ] **Step 1: Add failing stream behavior tests**

Instantiate the scene in a 1280×720 SubViewport, configure the real bus, and assert:

~~~gdscript
var stream = preload("res://scenes/ui/hud_message_stream.tscn").instantiate()
viewport.add_child(stream)
assertions.truthy(stream.configure(bus), "stream accepts real bus")
stream.set_collapsed(true)
bus.publish("debug", "debug", "推进到第 6 天", {"timestamp_msec": 1000})
assertions.truthy(stream.is_collapsed(), "new messages do not auto-expand")
assertions.equal(stream.get_unread_count(), 1, "collapsed stream increments unread")
stream.set_collapsed(false)
stream.return_to_latest()
assertions.equal(stream.get_unread_count(), 0, "returning to latest clears unread")
assertions.equal(stream.get_message_card_count(), 1, "expanded stream renders the record")
var top_height := stream.get_collapsed_header_height()
assertions.near(top_height, 62.0, 0.001, "collapsed header matches top HUD height")
~~~

Also assert added records append at the bottom, updated records reuse the same card, manual follow false preserves scroll and increments the new-message indicator, and reconfigure/re-enter leaves one signal connection.

- [ ] **Step 2: Run and verify RED**

Expected: stream scene is missing.

- [ ] **Step 3: Author the scene**

Create a right-anchored MarginContainer with:

- Header/TitleLabel
- Header/UnreadLabel
- Header/ToggleButton
- MessageScroll/MessageList
- Footer/HistoryButton
- Footer/ReturnLatestButton

Expanded background uses Color(0.08, 0.11, 0.086, 0.45); individual cards use alpha 0.60 and a four-pixel severity strip. Collapsed mode hides MessageScroll and Footer, sets minimum height to 62, and keeps the full 304-pixel title width.

- [ ] **Step 4: Implement stream state**

Implement configure(bus), set_collapsed(value), is_collapsed(), set_following_latest(value), return_to_latest(), get_unread_count(), get_message_card_count() and get_collapsed_header_height(). Connect message_added and message_updated idempotently, restore bus.get_recent() on configure, and disconnect on exit.

HistoryButton emits history_requested. ToggleButton flips collapsed state. A record is unread when collapsed or not following latest; expanded records at the latest position are immediately read.

- [ ] **Step 5: Run and verify GREEN**

Run the HUD shell runner. Expected: bus and stream suites pass.

- [ ] **Step 6: Commit**

~~~powershell
git add scripts/ui/hud_message_stream.gd scenes/ui/hud_message_stream.tscn tests/test_hud_message_stream.gd tests/run_hud_shell_tests.gd
git commit -m "feat: add collapsible hud message stream"
~~~

### Task 3: Rebuild the HUD shell and direct mode controls

**Files:**
- Modify: scenes/ui/hud.tscn
- Modify: scripts/ui/hud.gd
- Create: assets/ui/hud/hud_theme.tres
- Modify: tests/test_hud_action_bar.gd
- Modify: tests/test_runtime_ui_scenes.gd

- [ ] **Step 1: Replace old-scene expectations with failing shell expectations**

Assert that HUD has MessageStream and BottomBar/ActionRow/ModeSwitch/FarmingModeButton plus BuildingModeButton. Assert ModeMenu, BuildFeedbackToast, ActionHintToast and UrgentSummaries do not exist. Assert the two mode buttons are visible, toggle-style and show P/B shortcuts.

Configure the real PlayerActionController, place the HUD in a SubViewport, and use Input.parse_input_event() to send left-button press/release events at each mode button's global center. Require the same ActionMode change and palette rebuild as keyboard switch_mode(). This exercises Godot's native Button input path instead of manually emitting a signal.

- [ ] **Step 2: Run action-mode runner and verify RED**

Expected failures name missing ModeSwitch/MessageStream and legacy nodes still present.

- [ ] **Step 3: Re-author hud.tscn**

Keep stable public paths for TopBar, MaterialsPanel, BottomBar/ActionRow/QuickBar and BuildLockPanel. Set TopBar and the collapsed message header to the same 62-pixel height. Replace the popup mode tile with a ModeSwitch HBoxContainer containing two 148×56 toggle buttons. Instance hud_message_stream.tscn at the root and reserve its right-side safe area. Remove both Toast panels, their timers, ModeMenu and UrgentSummaries. Put the shared dark-green, gold-border, high-contrast font rules in assets/ui/hud/hud_theme.tres so the HUD and seed selector use one visual contract.

- [ ] **Step 4: Update VillaHud**

Add:

~~~gdscript
@onready var message_stream: HudMessageStream = $MessageStream
@onready var farming_mode_button: Button = $BottomBar/ActionRow/ModeSwitch/FarmingModeButton
@onready var building_mode_button: Button = $BottomBar/ActionRow/ModeSwitch/BuildingModeButton
var message_bus: HudMessageBus

func configure_message_bus(bus: HudMessageBus) -> bool:
    if not is_instance_valid(bus) or not message_stream.configure(bus):
        return false
    message_bus = bus
    return true

func _on_mode_requested(mode: int) -> void:
    if action_controller != null:
        action_controller.switch_mode(mode)

func _sync_mode_buttons(mode: int) -> void:
    farming_mode_button.button_pressed = mode == PlayerActionController.ActionMode.FARMING
    building_mode_button.button_pressed = mode == PlayerActionController.ActionMode.BUILDING

func show_build_feedback(message: String, details: Dictionary = {}) -> void:
    if message_bus != null:
        message_bus.publish("building", "error", message, details)

func show_action_hint(text: String, _duration := 2.5) -> void:
    if message_bus != null:
        message_bus.publish("action", "info", text)
~~~

Connect mode buttons once in ready, call sync from _on_action_mode_changed(), and forward stream history_requested to notifications_requested. Delete popup hover/token/timer logic and urgent-summary generation.

- [ ] **Step 5: Run and verify GREEN**

Run run_action_mode_debug_day_regression_tests.gd and run_hud_shell_tests.gd. Expected: existing action palette behavior remains green and new direct mode tests pass.

- [ ] **Step 6: Commit**

~~~powershell
git add scenes/ui/hud.tscn scripts/ui/hud.gd assets/ui/hud/hud_theme.tres tests/test_hud_action_bar.gd tests/test_runtime_ui_scenes.gd
git commit -m "feat: rebuild hud shell with direct mode controls"
~~~

### Task 4: Main wiring and removal of duplicate notification outlets

**Files:**
- Modify: scripts/main.gd
- Modify: scenes/ui/economy/economy_notification_ui.tscn
- Modify: scripts/ui/economy_notification_ui.gd
- Modify: tests/test_debug_crop_day.gd
- Modify: tests/test_economy_notifications.gd
- Modify: tests/test_main_item_container_wiring.gd
- Modify: tests/test_runtime_ui_scenes.gd

- [ ] **Step 1: Write failing integration expectations**

Require Main to create a child named HudMessageBus before UI setup and configure HUD with it. Advancing N must append one debug-level record. Applying the debug panel must append success or error. Emitting action_failure_hint and build_feedback_requested must create bus records.

Update economy notification tests to require NotificationCenter but no ToastStack. Pushing a real economy notification must append one bus record with its target_type and target_id; opening history must still toggle NotificationCenter.

- [ ] **Step 2: Run HUD, economy and debug runners to verify RED**

Expected: Main has no bus, debug hints still target transient HUD methods, and ToastStack still exists.

- [ ] **Step 3: Wire the bus in Main**

Preload hud_message_bus.gd, instantiate it as HudMessageBus in _initialize_systems(), add it before dependent systems, and call hud.configure_message_bus(hud_message_bus) in _setup_ui().

Connect economy_notification_system.notification_pushed to:

~~~gdscript
func _on_economy_notification_pushed(record: Dictionary, _merged: bool) -> void:
    hud_message_bus.publish(
        "economy",
        "warning" if EconomyNotificationSystem.is_urgent_kind(str(record.kind)) else "info",
        str(record.body),
        {
            "target_type": str(record.target_type),
            "target_id": str(record.target_id),
            "game_time": "第%d天" % int(record.total_day),
        }
    )
~~~

Publish N advancement as debug, debug apply as success/error, action failures as warning, and build feedback through the compatibility adapter. Connections must be idempotent.

- [ ] **Step 4: Reduce EconomyNotificationUI to persistent center**

Remove ToastStack, timeout constants, toast dictionaries and toast lifecycle methods. Keep configure(), show_center(), hide_center(), toggle_center(), mark_all_read(), activate_notification(), center card creation and target routing unchanged.

- [ ] **Step 5: Run and verify GREEN**

Run:

~~~powershell
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script tests/run_hud_shell_tests.gd
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script tests/run_action_mode_debug_day_regression_tests.gd
& 'C:\Users\Administrator\AppData\Local\Microsoft\WinGet\Links\godot_console.exe' --headless --path . --script tests/run_economy_ui_tests.gd
~~~

Expected: new HUD/debug assertions pass; economy runner may retain only its previously documented contract-delivery baseline failure.

- [ ] **Step 6: Commit**

~~~powershell
git add scripts/main.gd scenes/ui/economy/economy_notification_ui.tscn scripts/ui/economy_notification_ui.gd tests/test_debug_crop_day.gd tests/test_economy_notifications.gd tests/test_main_item_container_wiring.gd tests/test_runtime_ui_scenes.gd
git commit -m "feat: route runtime feedback through hud message bus"
~~~

### Task 5: Responsive shell regression and visual capture

**Files:**
- Modify: tests/test_hud_action_bar.gd
- Create: tests/capture_hud_shell.gd

- [ ] **Step 1: Add failing geometry assertions**

At 1280×720 and 1920×1080, require TopBar not to intersect MessageStream, BottomBar not to intersect expanded MessageStream, collapsed stream height to equal TopBar height, and expanded panel/background alpha to be near 0.45. Require all message labels to retain font outline or an opaque-enough card.

- [ ] **Step 2: Run and verify RED if layout is not yet responsive**

Expected: any fixed-offset collision is reported by exact node path and viewport size.

- [ ] **Step 3: Add responsive layout code**

Anchor MessageStream to the right with a width clamped between 280 and 360. Set TopBar right offset from that width. Clamp BottomBar to the remaining safe width. Recompute on viewport.size_changed without rebuilding message cards or the action palette.

- [ ] **Step 4: Capture expanded and collapsed states**

capture_hud_shell.gd instantiates Main, publishes success/warning/error/debug records, writes one expanded screenshot, collapses the stream, and writes one collapsed screenshot under output/hud/.

- [ ] **Step 5: Verify and commit**

Run targeted HUD runners and inspect both screenshots. Then:

~~~powershell
git add scripts/ui/hud.gd scenes/ui/hud.tscn tests/test_hud_action_bar.gd tests/capture_hud_shell.gd
git commit -m "test: cover responsive hud shell layout"
~~~
