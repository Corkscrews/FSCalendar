//
//  FSCalendarSectionMetrics.m
//  FSCalendar
//
//  Copyright © 2026 Wenchao Ding. All rights reserved.
//

#import "FSCalendarSectionMetrics.h"
#import "FSCalendar.h"
#import "FSCalendarDynamicHeader.h"
#import "FSCalendarCollectionViewLayout.h"
#import "FSCalendarExtensions.h"

typedef NS_ENUM(NSUInteger, FSCalendarSectionMetricsMode) {
    FSCalendarSectionMetricsModeInvalid = 0,
    FSCalendarSectionMetricsModeFixedSixRows,
    FSCalendarSectionMetricsModeEager,
    FSCalendarSectionMetricsModeCycle,
};

@interface FSCalendarSectionMetrics ()

@property (assign, nonatomic) FSCalendarSectionMetricsMode mode;
@property (assign, nonatomic) CGFloat headerHeight;
@property (assign, nonatomic) CGFloat rowHeight;
@property (assign, nonatomic) NSInteger numberOfSections;

@property (assign, nonatomic) CGFloat fixedSectionHeight;

@property (assign, nonatomic) NSInteger *rowCounts;
@property (assign, nonatomic) double *prefixHeights;
@property (assign, nonatomic) NSInteger tableLength;

@property (assign, nonatomic) double totalCycleHeight;

@end

@implementation FSCalendarSectionMetrics

- (void)dealloc
{
    [self freeTables];
}

- (void)freeTables
{
    free(self.rowCounts);
    self.rowCounts = NULL;
    free(self.prefixHeights);
    self.prefixHeights = NULL;
    self.tableLength = 0;
    self.totalCycleHeight = 0;
}

- (void)invalidateMetrics
{
    self.mode = FSCalendarSectionMetricsModeInvalid;
    [self freeTables];
    self.fixedSectionHeight = 0;
    self.headerHeight = 0;
    self.rowHeight = 0;
    self.numberOfSections = 0;
}

- (void)configureWithHeaderHeight:(CGFloat)headerHeight
                        rowHeight:(CGFloat)rowHeight
                 numberOfSections:(NSInteger)numberOfSections
{
    if (self.mode != FSCalendarSectionMetricsModeInvalid &&
        headerHeight == self.headerHeight &&
        rowHeight == self.rowHeight &&
        numberOfSections == self.numberOfSections) {
        return;
    }
    self.mode = FSCalendarSectionMetricsModeInvalid;
    [self freeTables];
    self.headerHeight = headerHeight;
    self.rowHeight = rowHeight;
    self.numberOfSections = MAX(numberOfSections, 0);
    [self rebuildIfNeeded];
}

- (void)rebuildIfNeeded
{
    if (self.mode != FSCalendarSectionMetricsModeInvalid) {
        return;
    }
    if (self.numberOfSections <= 0 || !self.calendar) {
        self.mode = FSCalendarSectionMetricsModeFixedSixRows;
        self.fixedSectionHeight = 0;
        return;
    }

    if (self.calendar.placeholderType == FSCalendarPlaceholderTypeFillSixRows) {
        self.fixedSectionHeight = self.headerHeight + 6 * self.rowHeight;
        self.mode = FSCalendarSectionMetricsModeFixedSixRows;
        return;
    }

    if (self.numberOfSections <= kFSCalendarSectionMetricsSmallRangeThreshold) {
        [self buildEagerTableWithLength:self.numberOfSections];
        self.mode = FSCalendarSectionMetricsModeEager;
        return;
    }

    [self buildCycleTable];
    self.mode = FSCalendarSectionMetricsModeCycle;
}

- (CGFloat)sectionHeightForRowCount:(NSInteger)rowCount
{
    return self.headerHeight + rowCount * self.rowHeight;
}

- (void)buildEagerTableWithLength:(NSInteger)length
{
    [self freeTables];
    self.tableLength = length;
    self.rowCounts = malloc(sizeof(NSInteger) * length);
    self.prefixHeights = malloc(sizeof(double) * (length + 1));
    self.prefixHeights[0] = 0;

    for (NSInteger index = 0; index < length; index++) {
        NSInteger rowCount = [self.calendar.calculator numberOfRowsInSection:index];
        self.rowCounts[index] = rowCount;
        self.prefixHeights[index + 1] = self.prefixHeights[index] + [self sectionHeightForRowCount:rowCount];
    }
    self.totalCycleHeight = self.prefixHeights[length];
}

- (void)buildCycleTable
{
    [self buildEagerTableWithLength:kFSCalendarSectionMetricsCycleLength];
    self.totalCycleHeight = self.prefixHeights[kFSCalendarSectionMetricsCycleLength];
}

- (NSInteger)rowCountForSection:(NSInteger)section
{
    [self rebuildIfNeeded];
    if (section < 0 || section >= self.numberOfSections) {
        return 0;
    }
    switch (self.mode) {
        case FSCalendarSectionMetricsModeFixedSixRows:
            return 6;
        case FSCalendarSectionMetricsModeEager:
            return self.rowCounts[section];
        case FSCalendarSectionMetricsModeCycle: {
            NSInteger index = section % kFSCalendarSectionMetricsCycleLength;
            return self.rowCounts[index];
        }
        default:
            return [self.calendar.calculator numberOfRowsInSection:section];
    }
}

- (CGFloat)heightForSection:(NSInteger)section
{
    [self rebuildIfNeeded];
    if (section < 0 || section >= self.numberOfSections) {
        return 0;
    }
    switch (self.mode) {
        case FSCalendarSectionMetricsModeFixedSixRows:
            return self.fixedSectionHeight;
        case FSCalendarSectionMetricsModeEager:
            return (CGFloat)(self.prefixHeights[section + 1] - self.prefixHeights[section]);
        case FSCalendarSectionMetricsModeCycle: {
            NSInteger index = section % kFSCalendarSectionMetricsCycleLength;
            return [self sectionHeightForRowCount:self.rowCounts[index]];
        }
        default:
            return [self sectionHeightForRowCount:[self.calendar.calculator numberOfRowsInSection:section]];
    }
}

- (CGFloat)topForSection:(NSInteger)section
{
    [self rebuildIfNeeded];
    if (self.numberOfSections <= 0) {
        return 0;
    }
    if (section <= 0) {
        return 0;
    }
    if (section >= self.numberOfSections) {
        return [self totalContentHeight];
    }

    switch (self.mode) {
        case FSCalendarSectionMetricsModeFixedSixRows:
            return section * self.fixedSectionHeight;
        case FSCalendarSectionMetricsModeEager:
            return (CGFloat)self.prefixHeights[section];
        case FSCalendarSectionMetricsModeCycle: {
            NSInteger cycle = section / kFSCalendarSectionMetricsCycleLength;
            NSInteger index = section % kFSCalendarSectionMetricsCycleLength;
            return (CGFloat)(cycle * self.totalCycleHeight + self.prefixHeights[index]);
        }
        default:
            return 0;
    }
}

- (CGFloat)bottomForSection:(NSInteger)section
{
    return [self topForSection:section] + [self heightForSection:section];
}

- (CGFloat)totalContentHeight
{
    [self rebuildIfNeeded];
    if (self.numberOfSections <= 0) {
        return 0;
    }
    switch (self.mode) {
        case FSCalendarSectionMetricsModeFixedSixRows:
            return self.numberOfSections * self.fixedSectionHeight;
        case FSCalendarSectionMetricsModeEager:
            return (CGFloat)self.prefixHeights[self.numberOfSections];
        case FSCalendarSectionMetricsModeCycle: {
            NSInteger fullCycles = self.numberOfSections / kFSCalendarSectionMetricsCycleLength;
            NSInteger remainder = self.numberOfSections % kFSCalendarSectionMetricsCycleLength;
            return (CGFloat)(fullCycles * self.totalCycleHeight + self.prefixHeights[remainder]);
        }
        default:
            return 0;
    }
}

- (NSInteger)clampSection:(NSInteger)section
{
    if (self.numberOfSections <= 0) {
        return 0;
    }
    return MIN(MAX(section, 0), self.numberOfSections - 1);
}

- (NSInteger)sectionForMinVerticalOffset:(CGFloat)y
{
    [self rebuildIfNeeded];
    if (self.numberOfSections <= 0) {
        return 0;
    }
    if (y <= 0) {
        return 0;
    }
    CGFloat totalHeight = [self totalContentHeight];
    if (y >= totalHeight) {
        return self.numberOfSections - 1;
    }
    return [self binarySearchSectionForOffset:y useMaxEdge:NO];
}

- (NSInteger)sectionForMaxVerticalOffset:(CGFloat)y
{
    [self rebuildIfNeeded];
    if (self.numberOfSections <= 0) {
        return 0;
    }
    if (y <= 0) {
        return 0;
    }
    CGFloat totalHeight = [self totalContentHeight];
    if (y >= totalHeight) {
        return self.numberOfSections - 1;
    }
    return [self binarySearchSectionForOffset:y useMaxEdge:YES];
}

- (NSInteger)binarySearchSectionForOffset:(CGFloat)y useMaxEdge:(BOOL)useMaxEdge
{
    NSInteger left = 0;
    NSInteger right = self.numberOfSections - 1;
    while (left <= right) {
        NSInteger mid = left + (right - left) / 2;
        CGFloat top = [self topForSection:mid];
        CGFloat bottom = [self bottomForSection:mid];
        if (useMaxEdge) {
            if (y > top && y <= bottom) {
                return mid;
            }
            if (y <= top) {
                right = mid - 1;
            } else {
                left = mid + 1;
            }
        } else {
            if (y >= top && y < bottom) {
                return mid;
            }
            if (y < top) {
                right = mid - 1;
            } else {
                left = mid + 1;
            }
        }
    }
    return [self clampSection:left];
}

@end
