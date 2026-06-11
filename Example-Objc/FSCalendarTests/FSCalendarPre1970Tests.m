//
//  FSCalendarPre1970Tests.m
//  FSCalendarTests
//
//  Copyright © 2026 Wenchao Ding. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "FSCalendar.h"
#import "FSCalendarDynamicHeader.h"
#import "FSCalendarExtensions.h"

@interface FSCalendarPre1970ExplicitBoundsDataSource : NSObject <FSCalendarDataSource>
@property (strong, nonatomic) NSDate *minimumDate;
@property (strong, nonatomic) NSDate *maximumDate;
@end

@implementation FSCalendarPre1970ExplicitBoundsDataSource

- (NSDate *)minimumDateForCalendar:(FSCalendar *)calendar
{
    return self.minimumDate;
}

- (NSDate *)maximumDateForCalendar:(FSCalendar *)calendar
{
    return self.maximumDate;
}

@end

@interface FSCalendarPre1970Tests : XCTestCase

@property (strong, nonatomic) NSDateFormatter *formatter;
@property (strong, nonatomic) NSCalendar *gregorian;
@property (strong, nonatomic) FSCalendarPre1970ExplicitBoundsDataSource *dataSource;

@end

@implementation FSCalendarPre1970Tests

- (void)setUp
{
    [super setUp];
    self.formatter = [[NSDateFormatter alloc] init];
    self.formatter.dateFormat = @"yyyy-MM-dd";
    self.gregorian = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
}

- (void)tearDown
{
    self.dataSource = nil;
    [super tearDown];
}

- (FSCalendar *)calendarWithMinimum:(NSString *)minimum maximum:(NSString *)maximum
{
    FSCalendar *calendar = [[FSCalendar alloc] initWithFrame:CGRectMake(0, 0, 320, 300)];
    self.dataSource = [[FSCalendarPre1970ExplicitBoundsDataSource alloc] init];
    self.dataSource.minimumDate = [self.formatter dateFromString:minimum];
    self.dataSource.maximumDate = [self.formatter dateFromString:maximum];
    calendar.dataSource = self.dataSource;
    [calendar reloadData];
    return calendar;
}

- (NSDate *)dateFromString:(NSString *)string
{
    return [self.formatter dateFromString:string];
}

- (void)testPre1970WorksWithExplicitBounds
{
    FSCalendar *calendar = [self calendarWithMinimum:@"1800-01-01" maximum:@"2300-01-01"];
    NSArray<NSString *> *dates = @[@"1850-06-15", @"1900-11-11", @"1969-12-31"];

    for (NSString *dateString in dates) {
        NSDate *date = [self dateFromString:dateString];
        XCTAssertNoThrow([calendar selectDate:date]);
        XCTAssertTrue([calendar.gregorian isDate:calendar.selectedDate inSameDayAsDate:date]);

        [calendar setCurrentPage:date animated:NO];
        XCTAssertTrue([calendar.gregorian isDate:calendar.currentPage inSameDayAsDate:[calendar.gregorian fs_firstDayOfMonth:date]]);

        NSIndexPath *indexPath = [calendar.calculator indexPathForDate:date scope:FSCalendarScopeMonth];
        XCTAssertNotNil(indexPath);
        NSDate *roundTripDate = [calendar.calculator dateForIndexPath:indexPath scope:FSCalendarScopeMonth];
        XCTAssertTrue([calendar.gregorian isDate:roundTripDate inSameDayAsDate:date]);
    }
}

- (void)testDefaultMinimumIsPre1970
{
    FSCalendar *calendar = [[FSCalendar alloc] initWithFrame:CGRectMake(0, 0, 320, 300)];
    [calendar reloadData];

    XCTAssertNoThrow([calendar selectDate:[self dateFromString:@"1969-12-31"]]);
    XCTAssertNoThrow([calendar selectDate:[self dateFromString:@"1900-01-01"]]);
    XCTAssertTrue([calendar.gregorian isDate:calendar.minimumDate inSameDayAsDate:[self dateFromString:@"1900-01-01"]]);
}

- (void)testSelectDate1900
{
    FSCalendar *calendar = [[FSCalendar alloc] initWithFrame:CGRectMake(0, 0, 320, 300)];
    [calendar reloadData];

    NSDate *date = [self dateFromString:@"1900-11-11"];
    [calendar selectDate:date scrollToDate:YES];
    XCTAssertTrue([calendar.gregorian isDate:calendar.selectedDate inSameDayAsDate:date]);
}

- (void)testScrollToPage1850
{
    FSCalendar *calendar = [self calendarWithMinimum:@"1800-01-01" maximum:@"2300-01-01"];
    NSDate *page = [self dateFromString:@"1850-06-01"];
    [calendar setCurrentPage:page animated:NO];
    XCTAssertTrue([calendar.gregorian isDate:calendar.currentPage inSameDayAsDate:page]);
}

- (void)testIndexPathRoundTripPre1970
{
    FSCalendar *calendar = [self calendarWithMinimum:@"1800-01-01" maximum:@"2300-01-01"];
    NSArray<NSString *> *dates = @[@"1850-03-20", @"1900-01-01", @"1969-07-04"];

    for (NSString *dateString in dates) {
        NSDate *date = [self dateFromString:dateString];
        NSIndexPath *indexPath = [calendar.calculator indexPathForDate:date scope:FSCalendarScopeMonth];
        NSDate *roundTripDate = [calendar.calculator dateForIndexPath:indexPath scope:FSCalendarScopeMonth];
        XCTAssertTrue([calendar.gregorian isDate:roundTripDate inSameDayAsDate:date], @"Round-trip failed for %@", dateString);
    }
}

- (void)testHeaderTitlePre1970
{
    FSCalendar *calendar = [self calendarWithMinimum:@"1800-01-01" maximum:@"2300-01-01"];
    NSDate *firstMonth = [calendar.calculator monthForSection:0];
    NSDateComponents *components = [calendar.gregorian components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:firstMonth];
    XCTAssertEqual(components.year, 1800);
    XCTAssertEqual(components.month, 1);
}

- (void)testHeaderAnchorUsesFirstDayOfMonth
{
    FSCalendar *calendar = [self calendarWithMinimum:@"1965-03-15" maximum:@"2300-01-01"];
    NSDate *firstMonth = [calendar.calculator monthForSection:0];
    NSDateComponents *components = [calendar.gregorian components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:firstMonth];
    XCTAssertEqual(components.year, 1965);
    XCTAssertEqual(components.month, 3);
    XCTAssertEqual(components.day, 1);
}

- (void)testOutOfBoundsBeforeNewMinimum
{
    FSCalendar *calendar = [[FSCalendar alloc] initWithFrame:CGRectMake(0, 0, 320, 300)];
    [calendar reloadData];

    XCTAssertThrows([calendar selectDate:[self dateFromString:@"1899-12-31"]]);
    XCTAssertThrows([calendar selectDate:[self dateFromString:@"2300-01-01"]]);
}

- (void)testWeekScopePre1970
{
    FSCalendar *calendar = [self calendarWithMinimum:@"1800-01-01" maximum:@"2300-01-01"];
    calendar.scope = FSCalendarScopeWeek;
    [calendar reloadData];

    NSDate *date = [self dateFromString:@"1950-03-15"];
    NSIndexPath *indexPath = [calendar.calculator indexPathForDate:date scope:FSCalendarScopeWeek];
    XCTAssertNotNil(indexPath);
    NSDate *roundTripDate = [calendar.calculator dateForIndexPath:indexPath scope:FSCalendarScopeWeek];
    XCTAssertTrue([calendar.gregorian isDate:roundTripDate inSameDayAsDate:date]);

    NSDate *weekStart = [calendar.calculator weekForSection:indexPath.section];
    NSDate *page = [calendar.gregorian fs_middleDayOfWeek:weekStart];
    XCTAssertTrue([calendar.gregorian isDate:page inSameDayAsDate:[calendar.gregorian fs_middleDayOfWeek:date]]);
}

- (void)testWeekScopeAcrossYearBoundaries
{
    FSCalendar *calendar = [self calendarWithMinimum:@"1899-01-01" maximum:@"2001-01-01"];
    calendar.scope = FSCalendarScopeWeek;
    [calendar reloadData];

    NSArray<NSString *> *dates = @[@"1899-12-25", @"1900-01-01", @"1969-12-31", @"1970-01-01", @"1999-12-31", @"2000-01-01"];
    for (NSString *dateString in dates) {
        NSDate *date = [self dateFromString:dateString];
        NSIndexPath *indexPath = [calendar.calculator indexPathForDate:date scope:FSCalendarScopeWeek];
        XCTAssertNotNil(indexPath, @"Missing week index path for %@", dateString);
        NSDate *roundTripDate = [calendar.calculator dateForIndexPath:indexPath scope:FSCalendarScopeWeek];
        XCTAssertTrue([calendar.gregorian isDate:roundTripDate inSameDayAsDate:date], @"Week round-trip failed for %@", dateString);
    }
}

- (void)testWeekScopeWithMondayFirstWeekday
{
    FSCalendar *calendar = [self calendarWithMinimum:@"1900-01-01" maximum:@"2000-01-01"];
    calendar.firstWeekday = 2;
    calendar.scope = FSCalendarScopeWeek;
    [calendar reloadData];

    NSDate *date = [self dateFromString:@"1950-06-15"];
    NSIndexPath *indexPath = [calendar.calculator indexPathForDate:date scope:FSCalendarScopeWeek];
    NSDate *roundTripDate = [calendar.calculator dateForIndexPath:indexPath scope:FSCalendarScopeWeek];
    XCTAssertTrue([calendar.gregorian isDate:roundTripDate inSameDayAsDate:date]);
}

@end
