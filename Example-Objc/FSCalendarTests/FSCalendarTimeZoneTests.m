//
//  FSCalendarTimeZoneTests.m
//  FSCalendarTests
//

#import <XCTest/XCTest.h>
#import "FSCalendar.h"
#import "FSCalendarDynamicHeader.h"
#import "FSCalendarExtensions.h"

@interface FSCalendarTimeZoneTests : XCTestCase
@property (strong, nonatomic) NSDateFormatter *formatter;
@end

@implementation FSCalendarTimeZoneTests

- (void)setUp
{
    [super setUp];
    self.formatter = [[NSDateFormatter alloc] init];
    self.formatter.dateFormat = @"yyyy-MM-dd";
}

- (void)testNormalizedTimeZoneUsesIANAIdentifier
{
    NSTimeZone *mazatlan = [NSTimeZone timeZoneWithName:@"America/Mazatlan"];
    XCTAssertNotNil(mazatlan);
    XCTAssertEqualObjects([mazatlan fs_normalizedTimeZone].name, @"America/Mazatlan");
}

- (void)testAmericaMazatlanProducesValidIndexPathAndSelection
{
    NSTimeZone *mazatlan = [NSTimeZone timeZoneWithName:@"America/Mazatlan"];
    XCTAssertNotNil(mazatlan);

    FSCalendar *calendar = [[FSCalendar alloc] initWithFrame:CGRectMake(0, 0, 320, 300)];
    calendar.timeZone = mazatlan;

    self.formatter.timeZone = mazatlan;
    self.formatter.calendar = calendar.gregorian;

    NSDate *date = [self.formatter dateFromString:@"2024-02-02"];
    calendar.today = date;
    calendar.currentPage = [calendar.gregorian fs_firstDayOfMonth:date];
    [calendar reloadData];
    [calendar layoutIfNeeded];

    NSIndexPath *indexPath = [calendar.calculator indexPathForDate:date scope:FSCalendarScopeMonth];
    XCTAssertNotNil(indexPath);
    XCTAssertLessThan(indexPath.item, 42);
    XCTAssertLessThan(indexPath.section, calendar.calculator.numberOfSections);

    NSDateComponents *pageComponents = [calendar.gregorian components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:calendar.currentPage];
    NSDateComponents *dateComponents = [calendar.gregorian components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:date];
    XCTAssertEqual(pageComponents.year, dateComponents.year);
    XCTAssertEqual(pageComponents.month, dateComponents.month);

    XCTAssertNoThrow([calendar selectDate:date scrollToDate:NO]);
    XCTAssertTrue([calendar isDateSelected:date]);
}

- (void)testChangingTimeZoneReloadsCurrentPageForToday
{
    FSCalendar *calendar = [[FSCalendar alloc] initWithFrame:CGRectMake(0, 0, 320, 300)];
    calendar.timeZone = [NSTimeZone timeZoneWithName:@"America/Mazatlan"];

    self.formatter.timeZone = calendar.timeZone;
    self.formatter.calendar = calendar.gregorian;
    NSDate *date = [self.formatter dateFromString:@"2024-02-02"];
    calendar.today = date;

    calendar.timeZone = [NSTimeZone timeZoneWithName:@"America/Los_Angeles"];
    self.formatter.timeZone = calendar.timeZone;

    NSDateComponents *pageComponents = [calendar.gregorian components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:calendar.currentPage];
    NSDateComponents *dateComponents = [calendar.gregorian components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:date];
    XCTAssertEqual(pageComponents.year, dateComponents.year);
    XCTAssertEqual(pageComponents.month, dateComponents.month);
}

@end
