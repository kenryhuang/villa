# Apple-Aligned Economy UI Design

**Date:** 2026-08-09  
**Status:** Approved by prior user authorization  
**Scope:** Market and building production interfaces only; economy rules and transactions remain unchanged.

## 1. Goal

Replace the current undersized and visually scattered economy panels with a larger, orderly interface inspired by iPadOS utility panels. The result must feel like a polished game control surface rather than a dense software dashboard: generous but controlled whitespace, aligned widgets, obvious information hierarchy, and consistent interaction geometry.

The user selected:

- Visual direction B: iPadOS card console.
- Size direction B: a 1400×760 maximum at desktop resolutions.
- Information strategy A by automatic approval: core data remains visible; secondary prose moves to tooltips or contextual detail.

## 2. Design Principles

### 2.1 Eight-point grid

All authored spacing uses multiples of four, with eight as the primary rhythm:

- Window inset: 24 px.
- Major card gap: 16 px.
- Card internal padding: 16 px.
- Widget vertical gap: 8 px.
- Section gap: 24 px.
- Standard control height: 44 px.
- Compact list row height: 52 px.
- Header height: 48 px minimum.

No form row may use arbitrary local spacing. Labels, inputs, buttons, and summaries align to shared column edges.

### 2.2 Apple-like hierarchy, game palette

Use Apple-inspired layout behavior without copying macOS chrome or abandoning the game's hand-painted palette:

- Window surface: warm neutral `#F2F0E9` at 97% opacity.
- Card surface: `#FFFEFA` at 92% opacity.
- Primary text: `#2D332F`.
- Secondary text: `#747A75`.
- Accent: muted garden green `#5F8768`.
- Selected fill: pale green `#E5EEE5`.
- Warning: `#C0873E`.
- Error: `#B65C4B`.
- Hairline border: dark neutral at 16% opacity, 1 px.
- Focus border: accent, 2 px.
- Window radius: 18 px; card radius: 14 px; controls: 10 px.
- One soft window shadow; cards use either no shadow or a 1 px ambient shadow.

Text sizes remain readable in-game:

- Window title: 28 px, semibold.
- Card/section title: 22 px, semibold.
- Body and form labels: 18 px.
- Secondary annotations: 16 px.
- Buttons: 18 px, semibold.

### 2.3 Progressive disclosure

The default view shows only information required to understand or act:

- Market: item, prices, stock state, seven-day curve, holdings, quantity, and buy/sell actions.
- Production: recipe, material flow, duration/value, batch action, queue, and stored output.

Long source/use/processing descriptions remain hidden and are exposed through existing tooltips. Failure and validation messages appear beside the control that caused them, not as unrelated text blocks.

## 3. Shared Window Shell

Both market and building economy windows use the same shell geometry and header system.

### 3.1 Geometry

- Desktop maximum: 1400×760.
- On smaller viewports: viewport size minus 20 px on every edge.
- Centered in the viewport.
- Market and production share the same maximum geometry so switching contexts does not visually resize the application.
- Modal CanvasLayer remains above the HUD because the original defect was the HUD covering the menu.

### 3.2 Header

The header is one aligned horizontal row:

- Left: 28 px title.
- Center-left: equal-size top tabs, 112×44.
- Right: contextual status, gold/date, and a 44×44 close button.
- All items align to the same vertical center.

Selected tabs visually join the content surface:

- Equal width and height for all tabs.
- Selected tab uses the content card color and a 1 px border with no bottom border.
- Unselected tabs are transparent or use a very light neutral fill.
- Tab baseline and gaps never change on selection.

## 4. Market Layout

The market page uses a stable three-column grid at 1120 logical pixels and above:

```text
MarketPage
  GoodsCard       280 px
  PriceCard       flexible, minimum 520 px
  TradeCard       300 px
  Gaps             16 px each
```

### 4.1 Goods card

- Section title and item count share one header row.
- Categories form a two-column segmented grid of equal 44 px controls.
- Sort control spans the full card width at 44 px.
- Product rows are 52 px tall and share fixed internal columns:
  - 36 px icon.
  - Flexible product name and compact price/trend.
  - 6 px stock state bar.
  - Optional compact urgency badge.
- Long text clips with a tooltip and must never expand the card.
- Only the product list scrolls.

### 4.2 Price card

- Header: selected item and compact stock state badge.
- Three aligned metric cells: mid price, buy price, sell price.
- The seven-day curve owns the flexible central area and never competes with prose.
- Footer: stock/target, daily supply, demand, and liquidity in an aligned four-cell strip.
- Latest curve point uses gold; curve and fill use muted green.
- With no history, show `历史积累中` centered in the chart area.

### 4.3 Trade card

Use a two-column form grid:

- Left column: fixed-width labels.
- Right column: values and controls.
- Holdings and market stock appear as aligned summary rows.
- Quantity row uses a 44 px SpinBox plus 44 px Max button.
- Price, total, and impact rows share the same baseline.
- Buy and Sell are equal-width 44 px buttons in one row.
- Validation text reserves one 40 px area so the card does not jump when messages appear.
- Large-trade confirmation is an inset card inside the trade column and cannot change any parent minimum width.

## 5. Production Layout

The production page mirrors the market grid:

```text
ProductionPage
  RecipeCard      280 px
  ProcessCard     flexible, minimum 520 px
  ActivityCard    300 px
  Gaps             16 px each
```

### 5.1 Recipe card

- Title and available recipe count align in one row.
- Recipe rows are 52 px tall.
- Each row uses fixed columns for name, readiness, duration, and profitability.
- Long recipe text clips and exposes the full value through a tooltip.
- Only the recipe list scrolls.

### 5.2 Process card

- Header shows recipe name and readiness badge.
- Input and output appear as two equal token groups connected by a centered process arrow.
- Below the flow, duration, fuel, input value, and output reference value use a 2×2 aligned metric grid.
- Batch controls occupy a single bottom row: label, 44 px quantity field, Max, flexible spacer, 148×44 Start button.
- Missing-material feedback is placed directly above the action row with a reserved height.

### 5.3 Activity card

- Split into Queue and Output sections with a 16 px divider gap.
- Queue rows use fixed columns for recipe, state, remaining time, and a thin progress bar.
- Queue content scrolls without changing card width or window height.
- Output rows align product name/quantity and a 72×44 Collect button.
- Collect All spans the card width and remains pinned to the bottom.

## 6. Responsive Behavior

- `>=1120` logical width: three-column layout.
- `<1120` logical width: drawer layout.
- Drawer opens the product/recipe list first and moves details/actions into the existing detail state.
- In a drawer, keep the price chart when logical content height is at least 420 px; hide it below that threshold.
- Lists scroll internally. The complete modal must not grow beyond its calculated rectangle.
- Resize and UI scale changes preserve selected tab, product, category, recipe, batch count, and scroll positions.

## 7. Motion and Interaction

- Open: 160 ms opacity plus scale 0.985→1.0, ease out.
- Tab/page transition: 120 ms opacity.
- Hover color transition target: 80 ms where supported.
- Close remains immediate to guarantee the modal releases input without a ghost overlay.
- Interrupted tweens reset scale and alpha before starting a new transition.
- Keyboard focus remains visible with a 2 px accent ring.

## 8. Technical Boundaries

The redesign changes presentation only:

- Keep `ShopUI`, `MarketPanel`, `TradePanel`, `BuildingEconomyUI`, and `BuildingProductionPanel` public APIs.
- Keep market, inventory, production, save, queue, and collection transactions unchanged.
- Preserve existing stable node names when practical; update paths and scene-contract tests together when hierarchy changes.
- Shared dimensions and style variations live in `EconomyLayout` and `economy_theme.tres`, not scattered script constants.
- Dynamic rows must use shared construction helpers so authored and runtime widgets follow the same geometry.

## 9. Verification

Automated tests must cover:

- 1400×760 maximum geometry and 20 px viewport margins.
- Equal tab sizes and stable positions.
- Exact three-column minimum widths and 16 px gaps.
- Standard 44 px controls and 52 px list rows.
- Dynamic product and recipe text clipping.
- All controls inside the shell at 1920×1080, 1600×900, and 1280×720.
- Drawer chart height threshold.
- CanvasLayer/root visibility synchronization.
- Existing buy/sell, recipe start, queue, and collection behavior.

Deterministic screenshots must include:

- Market normal at 1920×1080.
- Market normal at 1280×720.
- Large trade confirmation.
- Production running.
- Output ready.

Visual acceptance criteria:

- Every major card begins and ends on the same vertical grid.
- Equivalent widgets have identical heights.
- Labels and values share clear vertical baselines.
- No text or modal state changes the parent panel size.
- The interface feels larger and calmer than the previous compact version without becoming full-screen.
