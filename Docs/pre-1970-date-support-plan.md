# Plan: Support Dates Before 01/01/1970

## Summary

FSCalendar currently defaults its navigable date range to **1970-01-01 → 2099-12-31**. Dates before the Unix epoch are rejected unless the consumer implements `minimumDateForCalendar:` on the data source. This document outlines a staged plan to make pre-1970 dates a first-class, well-tested capability without accidentally widening the default calendar range so much that scrolling and layout performance regress.

---

## Problem Statement

Consumers who need historical calendars (birth records, genealogy, archival UIs, academic timelines, etc.) cannot use FSCalendar out of the box for years before 1970. Attempts to select or scroll to earlier dates fail with an out-of-bounds exception or silently clamp to the minimum date.

**Observed symptoms:**

- `selectDate:` / `scrollToDate:` raises `FSCalendar date out of bounds exception` for dates like `1900-01-01` when no custom data source is configured.
- Default calendar initialization pins `_minimumDate` to `1970-01-01`.
- Documentation does not explain that pre-1970 support requires implementing the data source, nor that the default is epoch-based.

---

## Root Cause Analysis

The limitation is **not** a fundamental `NSDate` constraint. `NSDate` can represent dates before 1970, and `NSCalendar` can calculate Gregorian components for historical dates. FSCalendar should avoid Unix-epoch assumptions and rely on `NSCalendar` component APIs for all date math.

The restriction comes from **hardcoded defaults** and **inconsistent anchor-date usage** inside FSCalendar:

| Location | Issue |
|---|---|
| `FSCalendar.m` — `init` (line ~163) | `_minimumDate` defaults to `"1970-01-01"` |
| `FSCalendar.m` — `requestBoundingDatesIfNecessary` (line ~1563) | Fallback minimum is `"1970-01-01"` when data source returns `nil` |
| `FSCalendarHeaderView.m` (lines ~169–173) | Header titles anchor on raw `minimumDate` instead of `fs_firstDayOfMonth:` — inconsistent with `FSCalendarCalculator` |
| `FSCalendarCalculator.m` (line ~131, ~274) | Week scope uses `NSCalendarUnitWeekOfYear` differences, which are harder to reason about across year boundaries than day-based week offsets |

The internal date math (`dateByAddingUnit:`, `components:fromDate:toDate:`, section indexing) already works for pre-1970 ranges when bounds are configured correctly — evidenced by existing tests that use `1900-01-01` as a minimum via the data source.

---

## What Already Works

1. **Data source override** — Implementing `minimumDateForCalendar:` and `maximumDateForCalendar:` allows arbitrary ranges, including pre-1970 (see `FSCalendarTests.m`, which uses `1900-01-01` → `2300-01-01`).
2. **Section-based navigation** — `FSCalendarCalculator` computes month/week sections relative to `fs_firstDayOfMonth:` / `fs_firstDayOfWeek:` of the minimum date; no epoch arithmetic is involved.
3. **Date extensions** — `FSCalendarExtensions` (`fs_firstDayOfMonth:`, `fs_lastDayOfMonth:`, etc.) use `NSCalendar` component APIs, which are epoch-independent.

---

## Proposed Solution

### Goals

1. Change the **default minimum date** to a historically useful boundary (recommended for v1: **1900-01-01**) while continuing to support earlier dates when consumers provide explicit data-source bounds.
2. Ensure **all subsystems** use a consistent anchor date (first day of month/week).
3. Add **automated tests** covering pre-1970 selection, scrolling, and index-path round-tripping.
4. Document the behavior and any practical limits (performance, week scope).
5. Maintain **backward compatibility** for consumers who already set explicit bounds via the data source.

### Non-Goals (for initial release)

- Supporting non-Gregorian calendars beyond what `NSCalendar` already provides.
- Making year 1 the default range before benchmarking the current section-based architecture.
- Replacing the section-based `UICollectionView` architecture with a windowed/virtualized approach (future enhancement if needed).

---

## Implementation Phases

### Phase 0 — Establish the Current Contract (Low Risk)

Before changing behavior, add a small baseline test proving that pre-1970 dates already work when the data source provides appropriate bounds. This protects the existing extension point and helps separate the real limitation (default bounds) from the date engine.

**Changes:**

1. Add or update a test calendar whose data source returns `1800-01-01` → `2300-01-01`.
2. Assert that `selectDate:`, `setCurrentPage:animated:`, `indexPathForDate:`, and `dateForIndexPath:` work for at least `1850-06-15`, `1900-11-11`, and `1969-12-31`.

**Acceptance criteria:**

- Pre-1970 dates pass with explicit data-source bounds before the default range changes.
- Any failures identify real calendar math defects rather than the hardcoded 1970 fallback.

---

### Phase 1 — Update Default Bounds (Medium Risk)

**Changes:**

1. Introduce named constants for default bounds in a single location (e.g., at the top of `FSCalendar.m`):

   ```objc
   static NSInteger const FSCalendarDefaultMinimumYear = 1900;
   static NSString * const FSCalendarDefaultMaximumDateString = @"2099-12-31";
   ```

2. Prefer constructing the default minimum with `NSCalendar` components instead of parsing a string. This avoids formatter leniency and makes very old years easier to test:

   ```objc
   static NSDate *FSCalendarDefaultMinimumDate(NSCalendar *calendar) {
       NSDateComponents *components = [[NSDateComponents alloc] init];
       components.era = 1;
       components.year = FSCalendarDefaultMinimumYear;
       components.month = 1;
       components.day = 1;
       return [calendar dateFromComponents:components];
   }
   ```

3. Replace hardcoded `"1970-01-01"` in:
   - `-[FSCalendar initWithFrame:]` (property initialization)
   - `-[FSCalendar requestBoundingDatesIfNecessary]` (data-source fallback)

4. Update `FSCalendarTests.m`:
   - `testOutOfBoundsException` should throw for dates outside the *configured* range, not the old 1970 default.
   - Ensure `setUp` calls `requestBoundingDatesIfNecessary` (or assigns the data source) before bound assertions.

**Acceptance criteria:**

- A freshly initialized `FSCalendar` (no data source) accepts `selectDate:` for `1969-12-31` and `1900-06-15`.
- Dates before the new default minimum still raise the out-of-bounds exception.
- Consumers can still support dates earlier than 1900 by implementing `minimumDateForCalendar:`.

---

### Phase 2 — Fix Anchor-Date Inconsistencies (Medium Risk)

**Problem:** `FSCalendarHeaderView` anchors month headers on `self.calendar.minimumDate` directly, while the calculator anchors on `[gregorian fs_firstDayOfMonth:minimumDate]`. If a consumer sets `minimumDate` to e.g. `1965-03-15`, header labels and grid cells can drift by up to a month.

**Changes:**

1. `FSCalendarHeaderView.m` — horizontal and vertical month headers:
   - Replace `self.calendar.minimumDate` with `[self.calendar.gregorian fs_firstDayOfMonth:self.calendar.minimumDate]`.

2. Audit all other `minimumDate` usages for the same pattern:
   - `FSCalendar.m` sticky headers and scroll offset math — already use `fs_firstDayOfMonth:` ✓
   - `FSCalendarCalculator.m` — already correct ✓
   - `FSCalendarHeaderView.m` week scope — verify `fs_middleDayOfWeek:` / `fs_firstDayOfWeek:` alignment

**Acceptance criteria:**

- Header title for section 0 matches the month displayed in the grid when `minimumDate` is any day within a month (not just the 1st).
- Pre-1970 months render correct year labels in the header (e.g., "November 1900").

---

### Phase 3 — Week Scope Hardening (Medium Risk)

**Problem:** `FSCalendarCalculator` uses `NSCalendarUnitWeekOfYear` differences for section counting and week navigation. That can be harder to validate around year boundaries and calendar configuration changes than deriving week sections from day offsets.

**Changes:**

1. Replace `weekOfYear` delta calculations with **day-based** math between normalized first-week dates:

   ```objc
   // Instead of weekOfYear component diff:
   NSInteger days = [gregorian components:NSCalendarUnitDay
                                   fromDate:firstWeekOfMinimum
                                     toDate:firstWeekOfTarget
                                    options:0].day;
   NSInteger section = days / 7;
   ```

2. Apply the same approach in:
   - `indexPathForDate:atMonthPosition:scope:` (week branch)
   - `reloadSections` (`numberOfWeeks` calculation)

   `weekForSection:` can continue using `dateByAddingUnit:NSCalendarUnitWeekOfYear value:section` because it adds whole weeks from a normalized first-week anchor. The risky part is calculating the section count from `weekOfYear` components.

3. Add regression tests for:
   - Week navigation across year 1900, 1969/1970 boundary, and 2000.
   - Different `firstWeekday` values (1 = Sunday, 2 = Monday).

**Acceptance criteria:**

- Week scope scrolls correctly to pre-1970 pages without section miscalculation.
- `indexPathForDate:` ↔ `dateForIndexPath:` round-trip holds for sample dates in 1850, 1900, 1969.

---

### Phase 4 — Tests & Examples (Low Risk)

**New unit tests** (`FSCalendarPre1970Tests.m` or extend `FSCalendarTests.m`):

| Test | Description |
|---|---|
| `testPre1970WorksWithExplicitBounds` | Calendar with `minimumDateForCalendar:` set to `1800-01-01` accepts pre-1970 dates |
| `testDefaultMinimumIsPre1970` | Fresh calendar accepts `1969-12-31` without data source |
| `testSelectDate1900` | Select `1900-11-11`, verify `selectedDate` and visible cell |
| `testScrollToPage1850` | `setCurrentPage:` to `1850-06-01`, verify `currentPage` |
| `testIndexPathRoundTripPre1970` | `indexPathForDate:` then `dateForIndexPath:` returns same day for multiple pre-1970 dates |
| `testHeaderTitlePre1970` | Section 0 header shows correct month/year when minimum is `1800-01-01` |
| `testOutOfBoundsBeforeNewMinimum` | A date before the chosen default minimum (e.g., `1899-12-31` if default is `1900-01-01`) still throws |
| `testWeekScopePre1970` | Week-mode navigation to `1950-03-15` lands on correct section |

**Example app addition:**

- Add a "Historical Calendar" example (ObjC and/or Swift) with `minimumDate = 1800-01-01`, `maximumDate = 2025-12-31`, and a button to jump to `1900-01-01`.

---

### Phase 5 — Documentation (Low Risk)

**Update:**

1. `README.md` — note the default date range and how to customize it via `FSCalendarDataSource`.
2. `FSCalendar.h` — document `minimumDate` / `maximumDate` properties with the new defaults and a note on performance for very wide ranges.
3. `CHANGELOG.md` — behavior-change note: default minimum moves from `1970-01-01` to the chosen pre-1970 minimum (recommended: `1900-01-01`). Consumers relying on the implicit 1970 floor without implementing the data source will see a wider range.

---

## Files to Modify

| File | Phase | Change |
|---|---|---|
| `FSCalendar/FSCalendar.m` | 1 | Default minimum date helper/constant |
| `FSCalendar/FSCalendarHeaderView.m` | 2 | Anchor on `fs_firstDayOfMonth:` |
| `FSCalendar/FSCalendarCalculator.m` | 3 | Week section math (optional but recommended) |
| `FSCalendar/FSCalendar.h` | 5 | Document new defaults |
| `Example-Objc/FSCalendarTests/FSCalendarTests.m` | 0, 1, 4 | Update and extend tests |
| `README.md` | 5 | Usage documentation |
| `CHANGELOG.md` | 5 | Release notes |

---

## Risks & Mitigations

### 1. Performance with very wide ranges

Each month in range = one `UICollectionView` section. A range of 0001–2099 is about **25,188 month sections** and about **109,500 week sections**. A range of 1900–2099 is about **2,400 month sections**. Floating mode previously allocated `sectionHeights`, `sectionTops`, and `sectionBottoms` arrays proportional to section count; see `Docs/floating-layout-lazy-section-metrics-plan.md` for the lazy metrics implementation.

**Mitigation:**

- Use `1900-01-01` as the default minimum for the first implementation unless benchmarks prove that year 1 is acceptable in month and week scopes.
- Document that consumers needing older dates should set explicit data-source bounds close to their real domain.
- Profile `reloadSections`, `scrollToDate:`, header reload, and week scope with 200-year, 500-year, and year-1 ranges during QA.

### 2. Breaking change for implicit 1970 floor

Apps that never set a data source and accidentally depended on the 1970 floor will suddenly see a wider scrollable range.

**Mitigation:**

- Treat as at least a minor semver bump (e.g., 2.8.5 → 2.9.0) with clear CHANGELOG entry.
- Consumers who need the old behavior can implement `minimumDateForCalendar:` returning `1970-01-01`.

### 3. `NSDateFormatter` and two-digit years

Not directly related to the 1970 bound, but historical UIs often use `yy` format strings, which are ambiguous.

**Mitigation:** Use `yyyy` in all internal formatters (already the case). Document this for consumers.

### 4. Gregorian calendar proleptic assumption

Dates before 1582-10-15 did not exist in the historical Gregorian adoption timeline. `NSCalendarIdentifierGregorian` uses the proleptic Gregorian calendar for all years.

**Mitigation:** Document that FSCalendar uses the proleptic Gregorian calendar via `NSCalendar`; this is standard for `NSDate` but may not match locale-specific historical calendars.

### 5. Negative `timeIntervalSince1970`

`NSDate` stores seconds relative to 1970-01-01 00:00:00 UTC. Pre-1970 dates have **negative** `timeIntervalSince1970`. FSCalendar does not use this API internally, so no code changes are needed — but consumers mixing `timeIntervalSince1970` with FSCalendar should be aware.

---

## Recommended Earliest Date

| Option | Pros | Cons |
|---|---|---|
| `0001-01-01` | Maximally permissive for proleptic Gregorian use cases | ~25,188 month sections and ~109,500 week sections to 2099; must be benchmarked before becoming the default |
| `1582-10-15` | Historically accurate Gregorian start | Still very wide; arbitrary for most apps |
| `1900-01-01` | Practical default; supports common pre-1970 use cases with about 2,400 month sections | Consumers needing older dates must provide explicit data-source bounds |
| `1970-01-01` (status quo) | No behavior change | Does not meet the goal |

**Recommendation:** Default to **`1900-01-01`** for the first release, while guaranteeing and documenting that consumers can set earlier bounds through `minimumDateForCalendar:`. Revisit `0001-01-01` only after profiling month and week scopes across the full range.

---

## Verification Checklist

Before merging:

- [ ] Default calendar selects `1969-12-31` without exception
- [ ] Default calendar selects `1900-01-01` without exception
- [ ] Calendar with explicit `1800-01-01` minimum selects and scrolls to `1850-06-15`
- [ ] Data-source-provided bounds still override defaults
- [ ] Header month title matches grid for non-1st minimum dates
- [ ] Month scope: scroll from 2025 back to 1900 smoothly
- [ ] Week scope: correct page at 1950-06-15 (after Phase 3)
- [ ] `testOutOfBoundsException` passes with updated expectations
- [ ] No new warnings or analyzer issues
- [ ] Example app historical calendar demo works on iOS Simulator
- [ ] CHANGELOG documents the default minimum change

---

## Estimated Effort

| Phase | Effort |
|---|---|
| Phase 0 — Baseline explicit-bound tests | ~1 hour |
| Phase 1 — Default bounds | ~1–2 hours |
| Phase 2 — Header anchor fix | ~2 hours |
| Phase 3 — Week scope hardening | ~4 hours |
| Phase 4 — Tests & example | ~3 hours |
| Phase 5 — Documentation | ~1 hour |
| **Total** | **~1–2 days** |

Phases 0, 1, 2, and 4 deliver the core user-facing fix. Phase 3 is recommended before declaring week-mode pre-1970 support complete.

---

## Open Questions

1. **Should the default minimum be `1900-01-01` or `0001-01-01`?** `1900-01-01` is safer for the current architecture; `0001-01-01` is more complete but should be benchmarked before becoming the default.
2. **Is week-scope pre-1970 support required for v1, or is month-scope sufficient?** Most historical use cases are month-based.
3. **Should FSCalendar expose `minimumDate` / `maximumDate` as writable properties** (not just read-only via data source) for simpler configuration?

---

## References

- `FSCalendar/FSCalendar.m` — default bounds and `FSCalendarAssertDateInBounds`
- `FSCalendar/FSCalendarCalculator.m` — section/date mapping
- `FSCalendar/FSCalendarHeaderView.m` — header title date computation
- `Example-Objc/FSCalendarTests/FSCalendarTests.m` — existing bounds test with `1900-01-01`
- [Apple Documentation: NSDate](https://developer.apple.com/documentation/foundation/nsdate) — date range limits
- [GitHub Issue #613](https://github.com/WenchaoD/FSCalendar/issues/613) — incorrect `NSDate` returned (related date math bug)
