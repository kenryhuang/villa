# Contract Delivery Limit Design

## Goal

Keep legacy contracts with `quantity_per_day = 1000` deliverable through the real UI while enforcing one bounded contract-delivery quantity across persistence, runtime transactions, and presentation.

## Shared limit

The maximum delivery quantity is the default inventory's maximum same-item capacity: default slot count multiplied by the default item stack size. `InventorySystem` exposes `DEFAULT_MAX_SLOTS = 20`, `GameData` exposes `DEFAULT_MAX_STACK = 99`, and `EconomyLimits.MAX_DELIVERY_QUANTITY` derives `1980` from those constants. Existing inventory defaults continue to behave exactly as before.

`EconomyLimits` is the only owner of `MAX_DELIVERY_QUANTITY`. Consumers preload it instead of defining UI or domain copies. Multiplication is limited to the two small compile-time constants, and runtime reward multiplication retains its existing overflow guard.

## Validation flow

- Economy state normalization rejects a contract whose daily quantity exceeds the shared maximum before it can enter `_contracts`.
- Contract signing and delivery re-check the authoritative record against the same maximum so corrupted or future in-memory records cannot transact.
- The shared delivery-transfer boundary rejects quantities outside the same range before inventory or NPC operations.
- `ContractPanel.safe_delivery_quantity`, the spin-box maximum, and delivery enablement use `EconomyLimits.MAX_DELIVERY_QUANTITY` directly.

The current code has no separate public contract-creation API; validated `from_dict` normalization is the only contract ingestion path and therefore the creation boundary covered by this design.

## Compatibility and tests

A real `quantity_per_day = 1000` contract with 1,000 owned items must load, appear deliverable, and complete one same-frame UI delivery with the correct inventory, NPC, gold, and unread changes. A contract at `MAX_DELIVERY_QUANTITY + 1` must fail validation/from-dict atomically, and direct runtime sign/delivery defenses must reject out-of-range authoritative data without asset mutation or quantity-sized loops.

The tests also assert that the shared maximum equals the inventory default slot count multiplied by the default stack size, preventing the domain and capacity definitions from drifting apart.
