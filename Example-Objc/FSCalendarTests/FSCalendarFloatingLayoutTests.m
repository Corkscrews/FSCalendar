//
//  FSCalendarFloatingLayoutTests.m
//  FSCalendarTests
//
//  Copyright © 2026 Wenchao Ding. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "FSCalendar.h"
#import "FSCalendarDynamicHeader.h"
#import "FSCalendarExtensions.h"
#import "FSCalendarSectionMetrics.h"

@interface FSCalendarFloatingLayoutBoundsDataSource : NSObject <FSCalendarDataSource>
@property (strong, nonatomic) NSDate *minimumDate;
@property (strong, nonatomic) NSDate *maximumDate;
@end

@implementation FSCalendarFloatingLayoutBoundsDataSource

- (NSDate *)minimumDateForCalendar:(FSCalendar *)calendar
{
    return self.minimumDate;
}

- (NSDate *)maximumDateForCalendar:(FSCalendar *)calendar
{
    return self.maximumDate;
}

@end

@interface FSCalendarFloatingLayoutTests : XCTestCase

@property (strong, nonatomic) NSDateFormatter *formatter;
@property (strong, nonatomic) FSCalendarFloatingLayoutBoundsDataSource *dataSource;

@end

@implementation FSCalendarFloatingLayoutTests

- (void)setUp
{
    [super setUp];
    self.formatter = [[NSDateFormatter alloc] init];
    self.formatter.dateFormat = @"yyyy-MM-dd";
}

- (void)tearDown
{
    self.dataSource = nil;
    [super tearDown];
}

- (NSDate *)dateFromString:(NSString *)string
{
    return [self.formatter dateFromString:string];
}

- (FSCalendar *)floatingCalendarWithMinimum:(NSString *)minimum maximum:(NSString *)maximum
{
    FSCalendar *calendar = [[FSCalendar alloc] initWithFrame:CGRectMake(0, 0, 320, 300)];
    calendar.scrollEnabled = YES;
    calendar.pagingEnabled = NO;
    calendar.scope = FSCalendarScopeMonth;
    self.dataSource = [[FSCalendarFloatingLayoutBoundsDataSource alloc] init];
    self.dataSource.minimumDate = [self dateFromString:minimum];
    self.dataSource.maximumDate = [self dateFromString:maximum];
    calendar.dataSource = self.dataSource;
    [calendar reloadData];
    [calendar layoutIfNeeded];
    return calendar;
}

- (FSCalendarSectionMetrics *)metricsForCalendar:(FSCalendar *)calendar
{
    FSCalendarCollectionViewLayout *layout = calendar.collectionViewLayout;
    [layout prepareLayout];
    FSCalendarSectionMetrics *metrics = [[FSCalendarSectionMetrics alloc] init];
    metrics.calendar = calendar;
    metrics.layout = layout;
    CGFloat headerHeight = calendar.preferredWeekdayHeight * 1.5 + calendar.preferredHeaderHeight;
    [metrics configureWithHeaderHeight:headerHeight
                             rowHeight:calendar.rowHeight
                      numberOfSections:calendar.calculator.numberOfSections];
    return metrics;
}

- (CGFloat)eagerHeightForSection:(NSInteger)section
                        calendar:(FSCalendar *)calendar
                    headerHeight:(CGFloat)headerHeight
                       rowHeight:(CGFloat)rowHeight
{
    NSInteger rowCount = [calendar.calculator numberOfRowsInSection:section];
    return headerHeight + rowCount * rowHeight;
}

- (void)testFloatingLayoutMetricsMatchEagerBaseline
{
    FSCalendar *calendar = [self floatingCalendarWithMinimum:@"1900-01-01" maximum:@"2100-01-01"];
    FSCalendarSectionMetrics *metrics = [self metricsForCalendar:calendar];
    CGFloat headerHeight = calendar.preferredWeekdayHeight * 1.5 + calendar.preferredHeaderHeight;
    CGFloat rowHeight = calendar.rowHeight;
    NSInteger sections = calendar.calculator.numberOfSections;

    CGFloat top = 0;
    for (NSInteger section = 0; section < sections; section++) {
        CGFloat expectedHeight = [self eagerHeightForSection:section calendar:calendar headerHeight:headerHeight rowHeight:rowHeight];
        XCTAssertEqualWithAccuracy([metrics topForSection:section], top, 0.01, @"Top mismatch at section %ld", (long)section);
        XCTAssertEqualWithAccuracy([metrics heightForSection:section], expectedHeight, 0.01, @"Height mismatch at section %ld", (long)section);
        XCTAssertEqual([metrics rowCountForSection:section], [calendar.calculator numberOfRowsInSection:section]);
        top += expectedHeight;
    }
}

- (void)testFloatingContentHeightConsistency
{
    FSCalendar *calendar = [self floatingCalendarWithMinimum:@"1960-01-01" maximum:@"2040-01-01"];
    FSCalendarSectionMetrics *metrics = [self metricsForCalendar:calendar];
    CGFloat headerHeight = calendar.preferredWeekdayHeight * 1.5 + calendar.preferredHeaderHeight;
    CGFloat rowHeight = calendar.rowHeight;
    CGFloat expectedTotal = 0;
    NSInteger sections = calendar.calculator.numberOfSections;
    for (NSInteger section = 0; section < sections; section++) {
        expectedTotal += [self eagerHeightForSection:section calendar:calendar headerHeight:headerHeight rowHeight:rowHeight];
    }
    XCTAssertEqualWithAccuracy([metrics totalContentHeight], expectedTotal, 0.01);
    XCTAssertEqualWithAccuracy(calendar.collectionViewLayout.collectionViewContentSize.height, expectedTotal, 0.01);
}

- (void)testFloatingScrollToDateWideRange
{
    FSCalendar *calendar = [self floatingCalendarWithMinimum:@"0001-01-01" maximum:@"4000-12-31"];
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    [window addSubview:calendar];
    [window layoutIfNeeded];
    NSArray<NSString *> *dates = @[@"1500-06-15", @"1969-12-31", @"2025-03-20", @"3999-11-11"];

    for (NSString *dateString in dates) {
        NSDate *date = [self dateFromString:dateString];
        XCTAssertNoThrow([calendar setCurrentPage:date animated:NO]);
        NSIndexPath *indexPath = [calendar.calculator indexPathForDate:date scope:FSCalendarScopeMonth];
        XCTAssertNotNil(indexPath);
        CGFloat expectedTop = [calendar.collectionViewLayout floatingTopForSection:indexPath.section];
        CGFloat maxOffset = MAX(0, calendar.collectionView.contentSize.height - calendar.fs_height);
        XCTAssertEqualWithAccuracy(calendar.collectionView.contentOffset.y, MIN(expectedTop, maxOffset), 0.01, @"Scroll mismatch for %@", dateString);
    }
}

- (void)testFloatingCycleTableBoundaries
{
    FSCalendar *calendar = [self floatingCalendarWithMinimum:@"0001-01-01" maximum:@"4000-12-31"];
    FSCalendarSectionMetrics *metrics = [self metricsForCalendar:calendar];

    CGFloat cycleHeight = [metrics topForSection:4800] - [metrics topForSection:0];
    XCTAssertGreaterThan(cycleHeight, 0);
    XCTAssertEqualWithAccuracy([metrics topForSection:9600] - [metrics topForSection:4800], cycleHeight, 0.01);
    XCTAssertEqual([metrics rowCountForSection:4800], [metrics rowCountForSection:0]);
    XCTAssertEqual([metrics rowCountForSection:4799], [calendar.calculator numberOfRowsInSection:4799]);
}

- (void)testFloatingMinimumMonthAnchorInvalidatesMetrics
{
    FSCalendar *calendarA = [self floatingCalendarWithMinimum:@"1900-01-01" maximum:@"2100-01-01"];
    FSCalendar *calendarB = [self floatingCalendarWithMinimum:@"1900-06-01" maximum:@"2100-01-01"];
    XCTAssertEqual(calendarA.calculator.numberOfSections, calendarB.calculator.numberOfSections);

    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:0 inSection:0];
    [calendarA layoutIfNeeded];
    [calendarB layoutIfNeeded];
    CGRect headerA = [calendarA.collectionViewLayout layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionHeader atIndexPath:indexPath].frame;
    CGRect headerB = [calendarB.collectionViewLayout layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionHeader atIndexPath:indexPath].frame;
    XCTAssertEqualWithAccuracy(headerA.origin.y, 0, 0.01);
    XCTAssertEqualWithAccuracy(headerB.origin.y, 0, 0.01);
    XCTAssertEqualWithAccuracy(headerA.size.height, headerB.size.height, 0.01);

    NSDate *juneDate = [self dateFromString:@"1900-07-01"];
    NSIndexPath *juneIndexPathA = [calendarA.calculator indexPathForDate:juneDate scope:FSCalendarScopeMonth];
    NSIndexPath *juneIndexPathB = [calendarB.calculator indexPathForDate:juneDate scope:FSCalendarScopeMonth];
    XCTAssertNotEqual(juneIndexPathA.section, juneIndexPathB.section);
}

- (void)testFloatingSearchAtContentBounds
{
    FSCalendar *calendar = [self floatingCalendarWithMinimum:@"1900-01-01" maximum:@"2100-01-01"];
    FSCalendarSectionMetrics *metrics = [self metricsForCalendar:calendar];
    XCTAssertEqual([metrics sectionForMinVerticalOffset:0], 0);
    XCTAssertEqual([metrics sectionForMaxVerticalOffset:0], 0);

    CGFloat totalHeight = [metrics totalContentHeight];
    NSInteger lastSection = calendar.calculator.numberOfSections - 1;
    XCTAssertEqual([metrics sectionForMinVerticalOffset:totalHeight - 1], lastSection);
    XCTAssertEqual([metrics sectionForMaxVerticalOffset:totalHeight], lastSection);
}

- (void)testFloatingLayoutPrepareLayoutDoesNotScanAllSections
{
    FSCalendar *calendar = [self floatingCalendarWithMinimum:@"0001-01-01" maximum:@"4000-12-31"];
    NSDate *before = [NSDate date];
    [calendar.collectionViewLayout prepareLayout];
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:before];
    XCTAssertLessThan(elapsed, 0.5);
    XCTAssertGreaterThan(calendar.collectionViewLayout.collectionViewContentSize.height, 0);
}

- (void)testFloatingFillSixRowsUsesFixedHeightMath
{
    FSCalendar *calendar = [self floatingCalendarWithMinimum:@"1900-01-01" maximum:@"2100-01-01"];
    calendar.placeholderType = FSCalendarPlaceholderTypeFillSixRows;
    [calendar reloadData];
    [calendar layoutIfNeeded];

    FSCalendarSectionMetrics *metrics = [self metricsForCalendar:calendar];
    CGFloat headerHeight = calendar.preferredWeekdayHeight * 1.5 + calendar.preferredHeaderHeight;
    CGFloat fixedHeight = headerHeight + 6 * calendar.rowHeight;
    XCTAssertEqualWithAccuracy([metrics heightForSection:10], fixedHeight, 0.01);
    XCTAssertEqualWithAccuracy([metrics topForSection:10], 10 * fixedHeight, 0.01);
    XCTAssertEqualWithAccuracy([metrics totalContentHeight], calendar.calculator.numberOfSections * fixedHeight, 0.01);
}

@end
