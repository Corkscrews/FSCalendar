//
//  FSCalendarTests.m
//  FSCalendarTests
//
//  Created by dingwenchao on 8/24/16.
//  Copyright © 2016 Wenchao Ding. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "FSCalendar.h"
#import "FSCalendarDynamicHeader.h"
#import "FSCalendarExtensions.h"

@interface FSCalendarTests : XCTestCase <FSCalendarDataSource,FSCalendarDelegate>

@property (strong, nonatomic) FSCalendar *calendar;
@property (strong, nonatomic) NSDate *date;
@property (strong, nonatomic) NSIndexPath *indexPath;
@property (strong, nonatomic) NSMutableArray<NSIndexPath *> *indexPaths;
@property (strong, nonatomic) NSDateFormatter *formatter;

@end

@implementation FSCalendarTests

- (void)setUp
{
    [super setUp];
    self.calendar = [[FSCalendar alloc] initWithFrame:CGRectMake(0, 0, 320, 300)];
    self.calendar.dataSource = self;
    [self.calendar reloadData];
    [self.calendar.calculator reloadSections];
    self.indexPath = [NSIndexPath indexPathForItem:25 inSection:0];
    
    self.indexPaths = [NSMutableArray array];
    for (int i = 0; i < 42; i++) {
        [self.indexPaths addObject:[NSIndexPath indexPathForItem:i inSection:0]];
    }
    self.formatter = [[NSDateFormatter alloc] init];
    self.formatter.dateFormat = @"yyyy-MM-dd";
    self.date = [self.formatter dateFromString:@"1900-11-11"];
    
}

- (NSDate *)minimumDateForCalendar:(FSCalendar *)calendar
{
    return [self.formatter dateFromString:@"1900-01-01"];
}

- (NSDate *)maximumDateForCalendar:(FSCalendar *)calendar
{
    return [self.formatter dateFromString:@"2300-01-01"];
}

- (void)tearDown
{
    [super tearDown];
    self.calendar = nil;
    self.indexPath = nil;
    self.date = nil;
}

- (void)testOutOfBoundsException
{
    XCTAssertNoThrow([self.calendar selectDate:[self.formatter dateFromString:@"1900-01-01"]]);
    XCTAssertThrows([self.calendar selectDate:[self.formatter dateFromString:@"1899-12-31"]]);
    XCTAssertThrows([self.calendar selectDate:[self.formatter dateFromString:@"2300-01-01"]]);
}

- (void)testIndexPathForDatePerformance {
    [self measureBlock:^{
        [self.calendar.calculator indexPathForDate:self.date scope:FSCalendarScopeMonth];
    }];
}

- (void)testDateForIndexPathPerformance {
    [self measureBlock:^{
        [self.indexPaths enumerateObjectsUsingBlock:^(NSIndexPath * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [self.calendar.calculator dateForIndexPath:obj];
        }];
    }];
}

#pragma mark - Critical bug regressions

- (void)testFrameForDateReturnsZeroForOutOfRangeDate
{
    NSDate *outOfRange = [self.formatter dateFromString:@"1899-12-31"];
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 568)];
    [window addSubview:self.calendar];
    XCTAssertNoThrow([self.calendar frameForDate:outOfRange]);
    XCTAssertTrue(CGRectEqualToRect([self.calendar frameForDate:outOfRange], CGRectZero));
}

- (void)testAnimatedScopeTransitionCompletesWithoutBoundingRectDelegate
{
    FSCalendar *calendar = [[FSCalendar alloc] initWithFrame:CGRectMake(0, 0, 320, 300)];
    calendar.dataSource = self;

    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 568)];
    [window addSubview:calendar];
    [window layoutIfNeeded];
    [calendar layoutIfNeeded];

    calendar.scope = FSCalendarScopeWeek;
    [calendar layoutIfNeeded];

    [calendar setScope:FSCalendarScopeMonth animated:YES];

    XCTestExpectation *expectation = [self expectationWithDescription:@"scope transition"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        XCTAssertEqual(calendar.transitionCoordinator.state, FSCalendarTransitionStateIdle);
        XCTAssertEqual(calendar.scope, FSCalendarScopeMonth);
        [expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:2 handler:nil];
}

- (void)testScopeTransitionWithNoSelectionNoToday
{
    FSCalendar *calendar = [[FSCalendar alloc] initWithFrame:CGRectMake(0, 0, 320, 300)];
    calendar.dataSource = self;
    calendar.today = nil;

    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 320, 568)];
    [window addSubview:calendar];
    [window layoutIfNeeded];
    [calendar layoutIfNeeded];

    XCTAssertNoThrow([calendar setScope:FSCalendarScopeWeek animated:NO]);
    XCTAssertEqual(calendar.transitionCoordinator.state, FSCalendarTransitionStateIdle);
    XCTAssertNoThrow([calendar setScope:FSCalendarScopeMonth animated:NO]);
    XCTAssertEqual(calendar.transitionCoordinator.state, FSCalendarTransitionStateIdle);
}

@end
