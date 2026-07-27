# Grain Crop Four-Stage Models Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans and follow RED/GREEN for integration behavior.

**Goal:** Create four native Godot low-poly grain crop models and connect them to FarmingSystem stage switching.

**Architecture:** Four explicit PackedScenes use shared StandardMaterial3D resources and primitive meshes. CropData exposes stage scene paths; FarmingSystem instantiates the current model and replaces it when the CropInstance stage changes, with the existing box visual retained as fallback.

**Tech Stack:** Godot 4.7.1, GDScript, Node3D, MeshInstance3D, CylinderMesh, SphereMesh, BoxMesh.

## Task 1: RED model and integration contract

- Create `tests/test_grain_crop_models.gd`.
- Add it to `tests/run_farming_system_tests.gd`.
- Assert all four assets exist, contain meshes, fit within one cell, increase in complexity and can be selected by FarmingSystem.
- Run the farming runner and confirm failure because assets and `stage_scenes` do not exist.

## Task 2: Model assets

- Create six shared material `.tres` resources.
- Create four explicit stage `.tscn` scenes.
- Run the model contract and correct any size or load errors.

## Task 3: Production integration

- Add `stage_scenes` to CropData.
- Make CropInstance calculate stages from scenes first.
- Change FarmingSystem visual storage to Node3D and replace models on stage changes.
- Preserve the MeshInstance3D fallback path.
- Run farming and grid regression tests.

## Task 4: Visual acceptance

- Configure the farming visual verifier with the four grain scene paths.
- Update its labels/status to assert 3D model usage.
- Capture and inspect `/tmp/villa-farming-system-verification.png`.

## Task 5: Final verification

- Run editor parse, farming tests, grid tests, Main binding, farming visual scene, graphical Main launch and `git diff --check`.
