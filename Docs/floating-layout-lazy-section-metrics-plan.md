# Plan: Lazy Section Metrics for Floating Layout

## Summary

FSCalendar **floating mode** (`scope = Month`, `scrollEnabled = YES`, `pagingEnabled = NO`) precomputes layout metadata for **every** collection section during `prepareLayout`. With the default date range now spanning the full **`NSDate` span** (0001-01-01 → 4000-12-31), that is roughly **48,012 month sections** and **~208,000 week sections** if week scope ever adopts the same pattern. The calculator already resolves individual months lazily, but the layout still allocates four O(n) arrays and walks all sections on each layout pass.

This document outlines a staged plan to make floating layout **O(visible sections)** instead of **O(total sections)**, without changing the public API or the section-based `UICollectionView` architecture.

**Review note (2026-06-12):** Strategy A alone is not enough for a correct implementation because `UICollectionView` still needs a stable, exact `collectionViewContentSize.height`. The plan now treats exact content-height computation as a first-class part of the metrics helper, using fixed-height math for six-row mode and a Gregorian cycle table for variable-row modes.

---

## Problem Statement

Consumers enabling floating mode over a wide date range (especially the new full-`NSDate` defaults) can hit noticeable main-thread stalls, memory spikes, and layout invalidation costs.

**Observed symptoms:**

- Slow first layout / rotation / `reloadData` when `floatingMode == YES` and the configured range spans centuries.
- `prepareLayout` allocates `sectionHeights`, `sectionTops`, `sectionBottoms`, and `sectionRowCounts` arrays sized to `numberOfSections`.
- `layoutSignatureForCurrentState` iterates all sections in floating mode to build a cache-invalidation hash.
- `scrollToDate:animated:` in floating mode triggers layout work that depends on fully materialized section offsets.

**Floating mode definition** (`FSCalendar.m`):

```objc
return _scope == FSCalendarScopeMonth && _scrollEnabled && !_pagingEnabled;
```

Paging mode (`pagingEnabled = YES`) is **not** affected — it uses `contentSize = viewport × sectionCount` without per-section height tables.

---

## Root Cause Analysis

Floating layout treats each month as a `UICollectionView` section with **variable height** (4–6 rows depending on month geometry). Unlike paging mode, vertical offsets cannot be derived from a fixed page height; the layout therefore builds cumulative Y positions up front.

| Location | Issue |
|---|---|
| `FSCalendarCollectionViewLayout.m` — `prepareLayout` (lines ~235–260) | Loops `0 ..< numberOfSections`, calls `numberOfRowsInSection:` for each, malloc's four arrays of length `numberOfSections`, builds prefix sums |
| `FSCalendarCollectionViewLayout.m` — `layoutSignatureForCurrentState` (lines ~105–109) | Loops all sections to hash row counts into `layoutSignature` |
| `FSCalendarCollectionViewLayout.m` — `searchStartSection:` / `searchEndSection:` (lines ~579–607) | Binary search is already O(log n), but each probe reads `sectionTops[mid]` / `sectionBottoms[mid]` from precomputed arrays |
| `FSCalendarCollectionViewLayout.m` — `layoutAttributesForItemAtIndexPath:` / header / separator paths | Read `sectionTops[section]` and `sectionRowCounts[section]` directly |
| `FSCalendar.m` — `scrollToDate:animated:` (floating branch, lines ~1303–1307) | Resolves header frame via layout attributes, which assumes section offsets are available |
| `FSCalendarCollectionViewLayout.m` — `sectionRowCounts` declaration | Declared as `CGFloat *` but allocated with `sizeof(NSInteger)` and used as an integer count; the metrics helper should make row-count typing explicit |

The calculator (`FSCalendarCalculator`) is **not** the bottleneck for floating layout:

- `numberOfMonths` / `numberOfWeeks` are single O(1) calendar-component calculations.
- `monthForSection:`, `numberOfRowsInMonth:`, etc. are already lazy and cached in `NSMutableDictionary`.

The bottleneck is **`FSCalendarCollectionViewLayout` eagerly materializing O(n) geometry for all sections**.

### Scale reference

| Range | Month sections | Approx. array memory (4 × CGFloat/NSInteger arrays) |
|---|---|---|
| 1900 → 2099 | ~2,400 | ~75 KB |
| 0001 → 4000 | ~48,012 | ~1.5 MB |
| Week scope (0001 → 4000) | ~208,571 | ~6.4 MB |

Array memory alone is tolerable on modern devices; the real cost is **main-thread iteration** on every layout invalidation (rotation, bounds changes, `reloadData`, memory-warning recovery) and **`numberOfRowsInSection:` fan-out** across tens of thousands of months.

---

## What Already Works

1. **Visible-rect layout is partially lazy** — `layoutAttributesForElementsInRect:` in floating mode binary-searches start/end sections, then lays out only the visible section range (lines ~386–418).
2. **Per-month row counts are lazy** — `numberOfRowsInMonth:` caches by `NSDate` key in `FSCalendarCalculator.rowCounts`.
3. **Paging mode is already O(1) for content size** — non-floating layout never builds section offset tables.
4. **Section ↔ date mapping is O(1)** — `indexPathForDate:` and `monthForSection:` derive positions from calendar math, not from layout arrays.

The gap is specifically **global prefix-sum geometry** (`sectionTops`, `sectionBottoms`, `contentSize.height`) and **layout signature** computation.

---

## Proposed Solution

### Goals

1. Eliminate the all-sections loop in floating `prepareLayout`.
2. Compute section top/bottom/height **on demand** for the sections actually needed (visible rect, scroll target, sticky headers).
3. Compute `collectionViewContentSize.height` without scanning every section.
4. Preserve pixel-identical layout for existing calendar configurations (row counts, headers, separators, sticky headers).
5. Add performance regression tests for wide ranges in floating mode.

### Non-Goals (for initial release)

- Replacing `UICollectionView` with a fully virtualized scroll engine.
- Changing floating mode semantics or public properties.
- Optimizing paging mode (already cheap).
- Optimizing week scope layout (separate follow-up unless it shares the same metrics helper).

---

## Key Design: `FSCalendarSectionMetrics`

Introduce a dedicated helper owned by `FSCalendarCollectionViewLayout` that handles **lazy section geometry** for floating layout while continuing to delegate calendar/date questions to `FSCalendarCalculator`.

### Responsibilities

| API | Purpose |
|---|---|
| `- (NSInteger)rowCountForSection:(NSInteger)section` | Thin wrapper over existing `numberOfRowsInSection:` |
| `- (CGFloat)heightForSection:(NSInteger)section` | Match the current section span formula exactly: `headerReferenceSize.height + rowCount × rowHeight` |
| `- (CGFloat)topForSection:(NSInteger)section` | Cumulative Y of section `section` |
| `- (CGFloat)bottomForSection:(NSInteger)section` | `topForSection: + heightForSection:` |
| `- (CGFloat)totalContentHeight` | Sum of all section heights (see strategies below) |
| `- (NSInteger)sectionForVerticalOffset:(CGFloat)y` | Binary search using `topForSection:` / `bottomForSection:` |
| `- (void)invalidateMetrics` | Clear caches when layout-affecting properties change |

### Strategy A — Exact cycle-backed metrics (recommended v1)

The first implementation should make **exact total height** cheap before optimizing individual probes. Without that, `UICollectionView` either gets an estimated content size or `totalContentHeight` secretly walks every section.

Use fast paths by placeholder type:

1. **`FSCalendarPlaceholderTypeFillSixRows`** — every month has 6 rows. Compute section height and total content height in O(1):
   - `height = headerReferenceSize.height + 6 * rowHeight`
   - `top = section * height`
   - `total = numberOfSections * height`
2. **`FSCalendarPlaceholderTypeNone` / `FillHeadTail`** — month row counts vary between 4 and 6. Build a 400-year Gregorian cycle table once per metrics configuration:
   - `rowCountForMonthIndexInCycle[0..4799]`
   - `prefixHeightWithinCycle[0..4800]`
   - `totalCycleHeight`

For a section relative to the normalized minimum-month anchor:

```
cycle = section / 4800
index = section % 4800
top = cycle * totalCycleHeight + prefixHeightWithinCycle[index]
height = headerReferenceSize.height + rowCount[index] * rowHeight
```

`sectionInsets` still matter for row Y coordinates (`tops[row]`) and row search math, but they should not be silently added to section height unless the current visual behavior is intentionally changed.

For `minimumDate` anchors that do not start at a 400-year cycle boundary, build the 4800-month table starting at the normalized minimum month. The sequence still repeats every 4800 months for a fixed `firstWeekday`, calendar identifier, timezone, and placeholder type.

**Properties:**

- `prepareLayout` no longer loops all sections; it only refreshes geometry inputs and invalidates metrics when needed.
- `totalContentHeight` is exact and O(1) after table construction.
- `topForSection:` is O(1) after table construction.
- Table build is bounded at 4800 month evaluations, not 48k, and only runs when layout-affecting inputs change.
- Implementation complexity: **medium**, but avoids shipping an estimated content-size workaround.

### Strategy B — Sparse prefix cache (fallback / local cache)

Store cumulative offsets at fixed strides (e.g. every **64** or **128** sections) plus an LRU cache for individual `topForSection:` queries.

```
topForSection(s):
  bucket = s / stride
  if sparseTop[bucket] is cached:
    return sparseTop[bucket] + sum(heightForSection(i) for i in bucket*stride ..< s)
  else:
    compute sparseTop[bucket] by summing from nearest lower cached bucket
    cache result
```

**Important limitation:** sparse prefixes do **not** solve exact `totalContentHeight` unless the final prefix is precomputed. Precomputing all final prefixes reintroduces O(total sections) work. Use this only as a fallback for unusual calendar behavior or as a small local cache layered on top of Strategy A.

**Properties:**

- `prepareLayout` no longer loops all sections; it only resets/invalidates metrics.
- Binary search calls `topForSection(mid)` → worst case O(stride) per probe, typically ≪ n.
- Memory: O(n / stride) sparse entries + small LRU — for 48k sections at stride 128 ≈ 375 buckets.
- Implementation complexity: **medium**.

### Strategy C — Small-range eager metrics

For narrow ranges (for example `< 600` months), the existing eager arrays are simple and cheap. The helper can keep an eager prefix array for small ranges if it makes correctness testing and migration easier, but the wide-range path must avoid arrays sized to `numberOfSections`.

### Strategy D — Full virtualization (future)

Expose only a sliding window of sections to `UICollectionView` and remap indices as the user scrolls. Highest engineering cost; defer unless Strategies A/B prove insufficient.

---

## Implementation Phases

### Phase 0 — Quick Wins (Low Risk)

Remove unnecessary O(n) work that does not contribute to correctness.

**Changes:**

1. **`layoutSignatureForCurrentState`** — Stop iterating all sections. Row counts in floating mode are deterministic for a given normalized minimum month, `firstWeekday`, `placeholderType`, calendar/timezone, and represented scope. Hash those inputs plus `preferredRowHeight`, `preferredHeaderHeight`, `preferredWeekdayHeight`, `sectionInsets`, separators, and `numberOfSections`.
2. **Guard `prepareLayout`** — If not `floatingMode`, keep existing early paths unchanged.
3. **Add timing tests** (see Phase 3) to establish baseline before deeper refactors.

**Acceptance criteria:**

- Floating layout signature no longer loops `numberOfSections`.
- No visual regressions in existing examples with narrow ranges (1900–2100).
- Changing `minimumDate` to a different month with the same section count cannot reuse stale item/header frames.

---

### Phase 1 — Extract Metrics Helper + Exact Content Height (Medium Risk)

**Changes:**

1. Add `FSCalendarSectionMetrics.{h,m}` owned by `FSCalendarCollectionViewLayout` so it can use layout geometry (`headerReferenceSize`, `estimatedItemSize`, `sectionInsets`) without expanding the public calculator contract.
2. Move height/top/bottom logic out of `prepareLayout` into the helper.
3. Implement exact metrics fast paths:
   - O(1) fixed-height math for `FSCalendarPlaceholderTypeFillSixRows`.
   - 4800-month Gregorian cycle table for `FSCalendarPlaceholderTypeNone` and `FSCalendarPlaceholderTypeFillHeadTail`.
   - Optional eager prefix array only for small ranges below a measured threshold.
4. Keep the helper internal. If `FSCalendar.m` needs direct offsets for `scrollToDate:`, expose a narrow internal layout method such as `-floatingTopForSection:` rather than exposing `FSCalendarSectionMetrics` as public API.
5. Make row-count storage typed as `NSInteger` in the helper; do not carry forward the current `CGFloat *sectionRowCounts` mismatch.
6. Replace direct array reads:
   - `self.sectionTops[i]` → `[metrics topForSection:i]`
   - `self.sectionBottoms[i]` → `[metrics bottomForSection:i]`
   - `self.sectionRowCounts[i]` → `[metrics rowCountForSection:i]`
   - `self.sectionHeights[i]` → `[metrics heightForSection:i]`
7. Remove malloc of full-length `sectionHeights` / `sectionTops` / `sectionBottoms` / `sectionRowCounts` arrays in floating mode.
8. `collectionViewContentSize.height` → `[metrics totalContentHeight]`.
9. Call `[metrics invalidateMetrics]` from existing invalidation paths:
   - `FSCalendarCalculator reloadSections` / `clearCaches`
   - `setFirstWeekday:`, `setTimeZone:`, bounds changes
   - memory-warning handler in layout
   - `placeholderType` / row height / header height / weekday height changes
   - `sectionInsets` / scroll direction changes on the layout

**Acceptance criteria:**

- Floating `prepareLayout` does **not** contain a `for (i = 0; i < numberOfSections; i++)` loop.
- Scrolling, sticky headers, separators, and `scrollToDate:` behave identically on narrow ranges.
- Floating mode over 0001–4000 completes initial layout in bounded time (target: **< 50 ms** on a recent simulator; tune after baseline).
- `collectionViewContentSize.height` is exact for small, medium, and full default ranges; no estimated content-height path ships.

---

### Phase 2 — Search, Scroll & Sticky Header Integration (Medium Risk)

**Changes:**

1. Replace `searchStartSection:` / `searchEndSection:` array probes with `[metrics sectionForVerticalOffset:]`.
2. Clamp rect searches explicitly for:
   - empty collection / zero sections
   - `rect.origin.y <= 0`
   - `CGRectGetMaxY(rect) >= totalContentHeight`
3. In `layoutAttributesForElementsInRect:`, derive start/end row indexes from metrics methods and clamp them to `0 ..< rowCount`.
4. In item, header, and separator attribute builders, compute Y positions from `[metrics topForSection:]`.
5. In `FSCalendar.m` floating `scrollToDate:animated:`, remove the priming call to `layoutAttributesForElementsInRect:` if metrics can supply the header offset directly. If the existing attribute path remains, verify it calls only lazy metrics and not visible-rect generation.
6. Audit `adjustMonthPosition`, `scrollViewDidScroll:`, and sticky header lookup for hidden full scans.

**Acceptance criteria:**

- `scrollToDate:` to arbitrary months (year 1, 1800, 2025, 4000) lands on the correct header offset.
- `currentPage` updates correctly while scrolling through wide ranges.
- Search never recurses outside `0 ..< numberOfSections`, including at the exact bottom of content.

---

### Phase 3 — Tests & Benchmarks (Low Risk)

**New tests** (`FSCalendarFloatingLayoutTests.m` or extend `FSCalendarPre1970Tests.m`):

| Test | Description |
|---|---|
| `testFloatingLayoutMetricsMatchEagerBaseline` | Compare lazy `topForSection:` / `heightForSection:` against current array implementation on a 200-year sample |
| `testFloatingScrollToDateWideRange` | Floating calendar 0001–4000; scroll to 1500, 1969, 2025, 3999 without exception |
| `testFloatingContentHeightConsistency` | `totalContentHeight` equals sum of per-section heights for a small known range |
| `testFloatingVisibleLayoutOnly` | Instrument layout to assert `heightForSection:` call count ≪ `numberOfSections` per frame |
| `testFloatingLayoutSignatureDoesNotScanAllSections` | Regression guard for Phase 0 |
| `testFloatingCycleTableBoundaries` | Sections 0, 4799, 4800, 9599, and dates near `minimumDate` / `maximumDate` |
| `testFloatingMinimumMonthAnchorInvalidatesMetrics` | Same section count but different `minimumDate` month produces updated frames |
| `testFloatingSearchAtContentBounds` | Search/layout attributes behave at y=0 and at exact content bottom |

**Performance harness (debug only or XCTest measure blocks):**

- Baseline vs lazy `prepareLayout` time for ranges: 200 years, 2000 years, full NSDate span.
- Memory high-water mark during initial layout.

---

### Phase 4 — Documentation (Low Risk)

**Update:**

1. `README.md` — note floating mode performance characteristics and recommendation to narrow bounds when possible.
2. `FSCalendar.h` — document that very wide ranges + floating mode rely on lazy layout internally; consumers should still prefer explicit bounds for domain-sized calendars.
3. `CHANGELOG.md` — performance improvement entry when shipped.
4. Cross-link from `Docs/pre-1970-date-support-plan.md` to this document.

---

## Files to Modify

| File | Phase | Change |
|---|---|---|
| `FSCalendar/FSCalendarSectionMetrics.h` | 1 | Internal lazy metrics API |
| `FSCalendar/FSCalendarSectionMetrics.m` | 1 | Fixed-row math + 4800-month cycle table + optional small-range eager prefixes |
| `FSCalendar/FSCalendarCollectionViewLayout.m` | 0, 1, 2 | Remove eager arrays; use metrics helper; update search and attribute builders |
| `FSCalendar/FSCalendarCollectionViewLayout.h` or private layout header | 1, 2 | Optional narrow internal offset API for floating scroll |
| `FSCalendar/FSCalendarCalculator.m` | 1 | Continue providing lazy row counts/month mapping; ensure cache clears invalidate metrics |
| `FSCalendar.m` | 2 | Floating scroll paths use lazy layout offsets without priming visible layout |
| `Example-Objc/FSCalendarTests/FSCalendarFloatingLayoutTests.m` | 3 | New tests |
| `README.md`, `FSCalendar.h`, `CHANGELOG.md` | 4 | Documentation |

---

## Risks & Mitigations

### 1. Floating-point drift in cumulative heights

Summing ~48k section heights can accumulate error; offset search may land on the wrong section.

**Mitigation:** Use `double` for prefix sums internally; unit-test monotonicity (`topForSection:i] <= topForSection:i+1]`); add epsilon tolerance in section search if needed.

### 2. `CGFloat` content size limits

Total content height for full range ≈ 48k × ~300 pt ≈ **14.4M pt**, within `CGFloat` range but large enough that offset math must avoid subtractive cancellation.

**Mitigation:** Prefer cycle-backed offsets (Strategy A) to reduce repeated summation; validate `scrollToDate:` at extremes.

### 3. Behavioral regressions in sticky headers / separators

Many code paths read section geometry; partial migration could leave stale array accesses.

**Mitigation:** Phase 1 replaces **all** array reads in floating paths; add snapshot tests on a fixed calendar configuration before/after.

### 4. Cycle table invalidation bugs

Forgetting to rebuild after `firstWeekday` or `placeholderType` change would misplace months.

**Mitigation:** Centralize invalidation in `invalidateMetrics`; include normalized minimum month, timezone, `firstWeekday`, placeholder type, row/header/weekday heights, and section count in the metrics configuration key; test each property change explicitly.

### 5. Hidden O(n) total-height path

It is easy to remove the visible arrays but accidentally compute `totalContentHeight` by summing all sections during `prepareLayout`.

**Mitigation:** Unit-test and benchmark `collectionViewContentSize` for the full default range; require fixed-row or cycle-backed exact totals before replacing the eager arrays.

### 6. Cycle-table assumptions differ from Foundation calendar behavior

Gregorian month geometry should repeat every 400 years, but implementation details around timezone normalization and very early years should be verified rather than assumed.

**Mitigation:** Build the table through the same `NSCalendar` and `FSCalendarCalculator` paths used today; compare cycle-backed metrics with a small eager baseline across cycle boundaries and at the default range edges.

---

## Verification Checklist

Before merging:

- [ ] Floating `prepareLayout` does not loop all sections
- [ ] `layoutSignatureForCurrentState` does not loop all sections
- [ ] Paging mode behavior unchanged
- [ ] Floating scroll / `scrollToDate:` correct at 0001, 1970, 2025, 4000
- [ ] Sticky headers and month separators align with cells
- [ ] Rotation and memory-warning recovery do not rebuild O(n) tables
- [ ] `totalContentHeight` matches UICollectionView scrollable area
- [ ] Exact content height is computed without summing all sections for the full default range
- [ ] Search handles y=0, visible rects spanning section boundaries, and exact content bottom
- [ ] Performance tests show ≥10× reduction in layout prep time for full NSDate range
- [ ] No new analyzer warnings

---

## Estimated Effort

| Phase | Effort |
|---|---|
| Phase 0 — Signature + baseline tests | ~2–3 hours |
| Phase 1 — Metrics helper + exact content height | ~1.5–2.5 days |
| Phase 2 — Search / scroll / sticky integration | ~0.5–1 day |
| Phase 3 — Tests & benchmarks | ~0.5–1 day |
| Phase 4 — Documentation | ~1 hour |
| **Total (Phases 0–1 minimum)** | **~2–3 days** |
| **Total (Phases 0–2 complete)** | **~3–4 days** |

Phases 0 and 1 remove the main O(n) layout preparation cost. Phase 2 is required before declaring full-range floating mode production-ready because search, visible attributes, and `scrollToDate:` are the user-visible paths that exercise the metrics helper.

---

## Open Questions

1. **Should the 4800-month cycle table always build for variable-row modes, or only above a threshold?** Always building is simpler and bounded; a small-range eager path can still help baseline comparisons.
2. **Should the metrics helper live entirely inside the layout or share row-count helpers with `FSCalendarCalculator`?** Keep ownership in the layout unless implementation reveals duplicated date math.
3. **What debug instrumentation should guard against accidental O(n) work?** A row-count/height call counter in tests may be enough.
4. **Do we add a runtime warning when floating mode is enabled over very wide implicit bounds?** Optional guardrail for consumers who enable floating mode unintentionally on the full NSDate default.

---

## References

- `FSCalendar/FSCalendarCollectionViewLayout.m` — floating `prepareLayout`, binary search, visible-rect layout
- `FSCalendar/FSCalendarCalculator.m` — lazy month/row caches, `numberOfSections`
- `FSCalendar/FSCalendar.m` — `floatingMode`, `scrollToDate:`, sticky headers
- `Docs/pre-1970-date-support-plan.md` — default range widening and section-count analysis
- `Docs/possible-bugs-review.md` — floating mode scroll clamp fixes (#8)
