# Agent harvest cleanup and farming context

The user approved extending `harvest` to clear withered crops without inventory rewards and supplying authoritative time, season, and planting information in every decision context.

## Behavior

- Visible NPC farm harvest accepts mature or withered crops. Withered cleanup uses `FarmingSystem.clear_withered`, returns the plot to tilled soil, and produces no items or experience. Growing/dormant crops remain rejected. Replaying an action stays idempotent. A cleanup followed by planting the same plot can execute in one batch.
- Existing public clock fields remain compatible. Add explicit season name/label, season day, year, and formatted time from `SeasonSystem` so numeric season 3 unambiguously means winter.
- `actor_context.crop_options` contains real, authorized crop definitions and current planting previews for owned plots, including seed inventory, season names, duration, plantable plot indices, and rejection reasons. `inspect_crop_options` returns this supplied context unchanged.
- Plot `season_valid` reflects the actual crop's allowed season; empty plots omit this crop-specific flag. Greenhouse/environment effects are evaluated by the existing planting preview. Include available farming actions to distinguish harvesting produce from clearing dead crops.
- The provider's harvest description explains cleanup without rewards. Plant description directs the Agent to actual planting options.
- Completed cleanup carries `cleared_withered`, publishes `CropCleared`, and cannot satisfy the cooperative supply task's productive-harvest milestone. Crop options require seed inventory for immediate planting and runtime filters them against the existing authorized seed contract.

## Validation and scope

Use regression tests for cleanup, inventory conservation, same-plot cleanup/replant, replay, growing/dormant rejection, normal harvest, winter crop restrictions, greenhouse exceptions, clock names, and context read-tool transport. Preserve existing uncommitted work. Memory timeline ordering and earlier unrelated aggregate-test failures are outside this change.
