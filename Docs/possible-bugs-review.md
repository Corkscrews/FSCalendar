# FSCalendar — Possible Bugs Review

**Date:** 2026-06-12  
**Scope:** Core library sources under `FSCalendar/` (13 implementation files)  
**Method:** Static code review of date math, layout, transitions, delegate contracts, cache invalidation, and nil-safety. Cross-checked against existing tests in `Example-Objc/FSCalendarTests/`.

This document lists **possible bugs and behavioral inconsistencies** found during review. Items are ordered by severity. Each entry includes location, description, reproduction hints, and a suggested fix where obvious.

---

## Executive Summary

| Severity | Count | Fixed |
|----------|-------|-------|
| Critical | 3 | 3 |
| High | 7 | 7 |
| Medium | 8 | 8 |
| Low | 5 | 5 |

The highest-impact areas are **scope transitions** (`FSCalendarTransitionCoordinator.m`), **calculator cache invalidation** after timezone/first-weekday changes, **programmatic select/deselect delegate callbacks**, and **nil-unsafe layout lookups**.

---

## Critical

### 1. Animated scope transition stalls without `boundingRectWillChange:animated:`

**File:** `FSCalendarTransitionCoordinator.m` (~361–374)

When `performTransition:fromProgress:toProgress:animated:` runs with `animated == YES`, completion logic only runs if the delegate implements `calendar:boundingRectWillChange:animated:`. If the delegate does not implement that method, neither the animation branch nor the non-animated fallback executes after scope is changed via KVC. The coordinator can remain in a finishing state, scope gestures may be blocked, and the UI can be half-updated.

**Reproduce:** Call `setScope:animated:YES` (or use the scope pan gesture) without implementing `boundingRectWillChange:animated:` on the delegate.

**Suggested fix:** Always call `performTransitionCompletionAnimated:` and apply bounds. Use animation only for visual interpolation; mirror the non-animated path (~371–374).

**Status:** **Fixed** — `performTransition:fromProgress:toProgress:animated:` now always calls `performTransitionCompletionAnimated:` in both animated and non-animated branches; `boundingRectWillChange:animated:` is invoked inside the animation block rather than gating completion.

---

### 2. Nil `indexPath` crash in `frameForDate:`

**File:** `FSCalendar.m` (~856–863)

`indexPathForDate:` can return `nil` for out-of-range dates or dates that cannot be resolved. The result is passed directly to `layoutAttributesForItemAtIndexPath:` and `.frame` is accessed without a nil check.

**Reproduce:** Call `[calendar frameForDate:]` with a date outside the configured min/max range or otherwise unresolvable by the calculator.

**Suggested fix:** Guard the index path; return `CGRectZero` when nil.

**Status:** **Fixed** — `frameForDate:` returns `CGRectZero` when `indexPathForDate:` returns nil.

---

### 3. Nil `focusedDate` during scope transition

**File:** `FSCalendarTransitionCoordinator.m` (~276–307, ~404–408)

`createTransitionAttributesTargetingScope:` builds a list of candidate dates (selection, today, current page) and filters to the visible section. If no candidate matches, `focusedDate` is nil. `calculateOffsetForProgress:` then calls `indexPathForDate:nil` and dereferences layout attributes without checking.

**Reproduce:** Trigger a scope transition with no selection, `today == nil`, and no visible candidate in the target section.

**Suggested fix:** Fallback to `currentPage` or the middle of the visible section; nil-check before accessing layout attributes.

**Status:** **Fixed** — `createTransitionAttributesTargetingScope:` falls back to `currentPage` when no visible candidate matches; `calculateOffsetForProgress:` uses `focusedDate ?: currentPage` and returns `0` when index path or layout attributes are nil.

---

## High

### 4. `setFirstWeekday:` does not invalidate calculator caches

**Files:** `FSCalendar.m` (~760–769), `FSCalendarCalculator.m` (cached `weeks`, `monthHeads`, `rowCounts`, `numberOfWeeks`)

Changing `firstWeekday` reloads the collection view and invalidates date tools, but never calls `[calculator reloadSections]` or `clearCaches`. Cached week starts, month heads, and row counts remain computed with the previous weekday.

**Reproduce:** Load the calendar, then set `firstWeekday` to a different value. Compare `weekForSection:` / placeholder layout against a freshly created calendar with the same setting.

**Suggested fix:** Call `[self.calculator reloadSections]` (or `clearCaches`) inside `setFirstWeekday:`.

**Status:** **Fixed** — `setFirstWeekday:` now calls `[self.calculator reloadSections]` and `invalidateLayout`.

---

### 5. `setTimeZone:` does not clear calculator caches when bounds are unchanged

**Files:** `FSCalendar.m` (~301–333), `FSCalendarCalculator.m` (~310–316)

`requestBoundingDatesIfNecessary` only calls `reloadSections` when min/max dates change. A timezone-only change reloads the collection view but leaves cached `weeks` / `monthHeads` / `months` from the prior timezone.

**Reproduce:** Load calendar, scroll to a distant month, change `timeZone`. Week sections and index paths can drift. `FSCalendarTimeZoneTests.m` covers selection/index paths but not cache invalidation.

**Suggested fix:** Call `[self.calculator clearCaches]` or `reloadSections` in `setTimeZone:`.

**Status:** **Fixed** — `setTimeZone:` now calls `[self.calculator reloadSections]` after `invalidateDateTools`.

---

### 6. Programmatic `selectDate:` skips `didSelectDate:` for current-month path

**File:** `FSCalendar.m` (~1185–1195 vs ~1162, ~1178)

User taps go through `collectionView:didSelectItemAtIndexPath:`, which fires the delegate. Programmatic selection for the **current** month updates internal state via `performSelectingForCell:` and `enqueueSelectedDate:` but does not notify the delegate. Cross-month paths explicitly call `didSelectItemAtIndexPath:`.

**Reproduce:** `[calendar selectDate:date scrollToDate:NO]` for a date on the current page. Delegate never receives `calendar:didSelectDate:atMonthPosition:`.

**Suggested fix:** Invoke the delegate after successful programmatic selection, mirroring the collection delegate path.

**Status:** **Fixed** — current-month programmatic selection now calls `calendar:didSelectDate:atMonthPosition:` after `enqueueSelectedDate:`.

---

### 7. Programmatic `deselectDate:` skips `didDeselectDate:`

**File:** `FSCalendar.m` (~1113–1127 vs ~592)

Removes the date from `_selectedDates` and updates the visible cell, but never calls the delegate. User-driven deselect in `collectionView:didDeselectItemAtIndexPath:` does call `didDeselectDate:`. This is a known long-standing issue (GitHub #283, noted in CHANGELOG).

**Reproduce:** `[calendar deselectDate:date]` — delegate is not called.

**Suggested fix:** Call `calendar:didDeselectDate:atMonthPosition:` after deselection with the correct month position.

**Status:** **Fixed** — `deselectDate:` now invokes `calendar:didDeselectDate:atMonthPosition:` with the resolved month position.

---

### 8. Floating-mode scroll clamp uses `fs_bottom` instead of height

**File:** `FSCalendar.m` (~1269)

```objc
MAX(0, _collectionViewLayout.collectionViewContentSize.height - _collectionView.fs_bottom)
```

`fs_bottom` is `CGRectGetMaxY` (origin + height), not the view height. The max scroll offset calculation is incorrect and often clamps to 0.

**Reproduce:** Floating mode (`scope = Month`, `pagingEnabled = NO`, `scrollEnabled = YES`); call `scrollToDate:animated:` for a late-month date.

**Suggested fix:** Use `_collectionView.fs_height` or `bounds.size.height`.

**Status:** **Fixed** — floating-mode scroll clamp now uses `_collectionView.fs_height`.

---

### 9. Layout `prepareLayout` early-return misses row-count changes

**File:** `FSCalendarCollectionViewLayout.m` (~100–102)

`prepareLayout` returns early when collection view size, section count, and separator setting are unchanged. It does not account for `placeholderType`, `adjustsBoundingRectWhenChangingMonths`, per-month row count (4/5/6), or `firstWeekday`. Stale `itemAttributes` can persist after month-to-month row changes.

**Reproduce:** Enable `adjustsBoundingRectWhenChangingMonths`, scroll between months with 5 vs 6 rows; cell frames may be wrong until a full relayout trigger.

**Suggested fix:** Include a row-count signature or invalidate item attributes on month change.

**Status:** **Fixed** — `prepareLayout` early-return now compares a `layoutSignature` derived from `firstWeekday`, `placeholderType`, `adjustsBoundingRectWhenChangingMonths`, scope, and per-section row counts in floating mode.

---

### 10. `scrollToDate:` silently scrolls to section 0 when index path is nil

**File:** `FSCalendar.m` (~1252)

```objc
NSInteger scrollOffset = [self.calculator indexPathForDate:date atMonthPosition:FSCalendarMonthPositionCurrent].section;
```

Messaging `nil` for `.section` returns 0 in Objective-C, so a failed lookup scrolls to the first page instead of no-op or error.

**Reproduce:** `scrollToDate:` with a date that `indexPathForDate:atMonthPosition:Current` cannot resolve.

**Suggested fix:** Nil-check the index path; return early or assert in debug builds.

**Status:** **Fixed** — `scrollToDate:animated:` returns early when `indexPathForDate:atMonthPosition:Current` returns nil.

---

## Medium

### 11. `FSCalendarAppearance` init writes `borderColors` before dictionary allocation

**File:** `FSCalendarAppearance.m` (~68–75)

Assignments to `_borderColors[...]` occur **before** `_borderColors = [NSMutableDictionary dictionaryWithCapacity:2]`. The assignments are no-ops; default border colors are never stored.

**Reproduce:** Inspect a fresh `FSCalendarAppearance`; `borderDefaultColor` / `borderSelectionColor` resolve to nil until explicitly set.

**Suggested fix:** Allocate `_borderColors` before default assignments.

**Status:** **Fixed** — `_borderColors` is now allocated before default color assignments in `-init`.

---

### 12. `handleSwipeToChoose` double-invokes selection pipeline

**File:** `FSCalendar.m` (~1583–1588)

Calls `selectDate:...` and then manually invokes `collectionView:didSelectItemAtIndexPath:`. This can redundantly enqueue selection, call `selectCounterpartDate`, and in some branches produce duplicate delegate callbacks.

**Reproduce:** Enable `swipeToChooseGesture`, long-press and drag across dates.

**Suggested fix:** Use only `selectDate:` **or** only the collection delegate path, not both.

**Status:** **Fixed** — swipe-to-choose now relies on `selectDate:` / `deselectDate:` only; redundant collection delegate calls removed.

---

### 13. Week-scope header titles use different anchor math than calculator

**Files:** `FSCalendarHeaderView.m` (~184–186), `FSCalendarCalculator.m` (~217–224)

Header week titles anchor on `fs_middleDayOfWeek(minimumDate)` + `NSCalendarUnitWeekOfYear`. The calculator uses `fs_firstDayOfWeek(minimumDate)` + day offset (`section * 7`). These can diverge at ISO week-year boundaries.

**Reproduce:** Week scope, scroll across year/week boundaries; compare header title to the selected week.

**Suggested fix:** Align header math with `weekForSection:` / calculator day-based offsets.

**Status:** **Fixed** — week-scope header titles now use `[calculator pageForSection:]`, matching calculator section math.

---

### 14. `setScrollOffset:animated:` ignores the `animated` parameter

**File:** `FSCalendarHeaderView.m` (~114–117)

`setScrollOffset:scrollOffset animated:` always calls `scrollToOffset:scrollOffset animated:NO`.

**Reproduce:** Any caller passing `animated:YES` to the header scroll offset API.

**Suggested fix:** Pass through the `animated` argument.

**Status:** **Fixed** — `setScrollOffset:animated:` now forwards the `animated` flag to `scrollToOffset:animated:`.

---

### 15. `isDateSelected:` can return false positives

**File:** `FSCalendar.m` (~1348–1350)

Returns YES if **either** `_selectedDates` **or** `indexPathsForSelectedItems` contains the date. Stale collection view selection state can disagree with the internal array after programmatic operations.

**Reproduce:** Programmatic select/deselect without fully syncing collection view state; call `isDateSelected:`.

**Suggested fix:** Treat `_selectedDates` as the source of truth.

**Status:** **Fixed** — `isDateSelected:` now checks only `_selectedDates` (with start-of-day normalization).

---

### 16. `prepareLayout` triggers scroll adjustment during layout

**File:** `FSCalendarCollectionViewLayout.m` (~248)

`prepareLayout` ends with `[self.calendar adjustMonthPosition]`, which calls `scrollToPageForDate:` and `setContentOffset:` during layout. This can cause reentrant layout, jank, or unexpected page jumps.

**Reproduce:** Resize the calendar or invalidate layout while not idle; observe content offset shifts during layout.

**Suggested fix:** Defer scroll adjustment to the next run loop, or only adjust when offset is actually wrong.

**Status:** **Fixed** — `adjustMonthPosition` is deferred to the next main-queue turn after `prepareLayout`.

---

### 17. Memory warning clears calculator and layout caches separately

**Files:** `FSCalendarCalculator.m` (~320–324), `FSCalendarCollectionViewLayout.m` (~517–521)

Calculator clears date caches on memory warning; layout clears attribute dictionaries in a separate handler. Between the two, layout can briefly combine stale geometry with freshly recomputed dates.

**Reproduce:** Simulate memory warning while calendar is visible; rare transient misalignment until next full invalidation.

**Suggested fix:** Single invalidation path: clear caches and call `invalidateLayout` together.

**Status:** **Fixed** — layout memory-warning handler now clears calculator caches, layout attribute caches, and calls `invalidateLayout`; calculator’s separate handler was removed.

---

### 18. `setFs_right:` setter ignores the parameter (UIView and CALayer)

**File:** `FSCalendarExtensions.m` (~69–71, ~134–136)

```objc
- (void)setFs_right:(CGFloat)fs_right {
    self.fs_left = self.fs_right - self.fs_width;  // uses current fs_right, not parameter
}
```

Setting the right edge has no effect. Not used in this repo today but is a latent API bug.

**Suggested fix:** `self.fs_left = fs_right - self.fs_width;`

**Status:** **Fixed** — both `UIView` and `CALayer` `setFs_right:` now use the parameter value.

---

## Low

### 19. KVC access to gesture recognizer `_targets`

**File:** `FSCalendarTransitionCoordinator.m` (~87)

Uses `valueForKey:@"_targets"` on `UIPanGestureRecognizer` to detect whether the calendar is a gesture target. This relies on private API surface and may break across iOS versions.

**Status:** **Fixed** — replaced KVC target inspection with `isScopeTransitionPanGesture:`, matching `scopeGesture` or legacy custom pans attached to the calendar view.

---

### 20. Shared mutable `NSDateComponents` on `NSCalendar`

**File:** `FSCalendarExtensions.m` (~234–241)

A shared mutable `NSDateComponents` instance is stored on `NSCalendar` via associated objects. Unsafe if the same calendar instance is used concurrently off the main thread.

**Status:** **Fixed** — week date helpers now allocate local `NSDateComponents` instances; shared associated-object cache removed.

---

### 21. `FSCalendarCell` compares `shapeLayer.opacity` (float) to BOOL

**File:** `FSCalendarCell.m` (~218–220)

```objc
if (_shapeLayer.opacity == shouldHideShapeLayer) {
    _shapeLayer.opacity = !shouldHideShapeLayer;
}
```

Fractional opacity values (e.g. mid-animation) can cause incorrect show/hide decisions.

**Status:** **Fixed** — shape layer visibility now compares against explicit target opacity (`0.0` / `1.0`) using `FLT_EPSILON`.

---

### 22. Missing deprecation mapping yields NULL selector

**File:** `FSCalendarDelegationProxy.m` (~62–66)

If `deprecations[selectorString]` is nil, `NSSelectorFromString(nil)` returns NULL. Downstream forwarding may silently fail for unmapped deprecated selectors.

**Status:** **Fixed** — `deprecatedSelectorOfSelector:` returns the original selector when no deprecation mapping exists.

---

### 23. `setToday:` uses KVC instead of property API on cell

**File:** `FSCalendar.m` (~782)

Updates today highlight via `setValue:@YES forKey:@"dateIsToday"` instead of the public property setter. Fragile if the property name or KVO behavior changes.

**Status:** **Fixed** — `setToday:` now sets `dateIsToday` via the property on visible cells directly.

---

## Test Coverage Gaps

| Area | Covered? | Notes |
|------|----------|-------|
| Pre-1970 dates | Yes | `FSCalendarPre1970Tests.m` |
| Default minimum (1900) | Yes | `testDefaultMinimumIsPre1970` |
| Out-of-bounds exceptions | Yes | `FSCalendarTests.m` |
| Timezone (Mazatlan) | Partial | Selection/index path only; not cache invalidation |
| Scope transition | **No** | Critical bug #1 fixed; still untested |
| Programmatic select/deselect delegates | **No** | Bugs #6, #7 fixed; still untested (known #283) |
| `firstWeekday` cache invalidation | **No** | Bug #4 fixed; still untested |
| Floating mode scroll | **No** | Bug #8 fixed; still untested |
| `frameForDate:` with invalid date | **No** | Bug #2 fixed; still untested |
| Swipe-to-choose | **No** | Bug #12 untested |

---

## Recommended Fix Priority

1. ~~**Scope transition completion** (#1)~~ — fixed  
2. ~~**Nil-safe layout lookups** (#2, #3, #10)~~ — fixed  
3. ~~**Calculator cache invalidation** (#4, #5)~~ — fixed  
4. ~~**Delegate contract for programmatic APIs** (#6, #7)~~ — fixed  
5. ~~**Floating scroll clamp** (#8)~~ — fixed  
6. ~~**Layout cache invalidation** (#9)~~ — fixed (partial; #16, #17 remain)  
7. ~~**Layout-time scroll / memory-warning coordination** (#16, #17)~~ — fixed  
8. ~~**Medium-severity items** (#11–#18)~~ — fixed  
9. ~~**Low-severity items** (#19–#23)~~ — fixed  

---

## Files Reviewed

| File | Primary concerns |
|------|------------------|
| `FSCalendar.m` | Delegate callbacks, nil safety, scroll math, cache invalidation |
| `FSCalendarCalculator.m` | Stale caches, week/month section math |
| `FSCalendarTransitionCoordinator.m` | Stalled transitions, nil focused date, private KVC |
| `FSCalendarCollectionViewLayout.m` | Stale early-return, layout-time scroll |
| `FSCalendarAppearance.m` | Init order for `borderColors` |
| `FSCalendarHeaderView.m` | Week header anchor, ignored `animated` |
| `FSCalendarExtensions.m` | Broken `setFs_right:`, shared components |
| `FSCalendarCell.m` | Opacity vs BOOL comparison |
| `FSCalendarDelegationProxy.m` | NULL selector from missing deprecation map |
| `FSCalendarCollectionView.m` | No major issues found |
| `FSCalendarWeekdayView.m` | No major issues found |
| `FSCalendarStickyHeader.m` | No major issues found |
| `FSCalendarConstants.m` | No major issues found |

---

*This is a static review document. Items marked "possible" should be confirmed with unit tests or reproduction cases before treating them as confirmed defects.*
