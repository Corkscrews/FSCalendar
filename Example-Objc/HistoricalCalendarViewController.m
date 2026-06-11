//
//  HistoricalCalendarViewController.m
//  FSCalendar
//

#import "HistoricalCalendarViewController.h"
#import "FSCalendar.h"
#import "FSCalendarExtensions.h"

@interface HistoricalCalendarViewController () <FSCalendarDataSource, FSCalendarDelegate>

@property (weak, nonatomic) FSCalendar *calendar;
@property (strong, nonatomic) NSDateFormatter *dateFormatter;

@end

@implementation HistoricalCalendarViewController

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.title = @"Historical Calendar";
    }
    return self;
}

- (void)loadView
{
    UIView *view = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    view.backgroundColor = [UIColor groupTableViewBackgroundColor];
    self.view = view;

    CGFloat height = [[UIDevice currentDevice].model hasPrefix:@"iPad"] ? 450 : 300;
    FSCalendar *calendar = [[FSCalendar alloc] initWithFrame:CGRectMake(0, CGRectGetMaxY(self.navigationController.navigationBar.frame), view.frame.size.width, height)];
    calendar.dataSource = self;
    calendar.delegate = self;
    calendar.appearance.headerDateFormat = @"MMMM yyyy";
    [view addSubview:calendar];
    self.calendar = calendar;

    UIButton *jumpButton = [UIButton buttonWithType:UIButtonTypeSystem];
    jumpButton.frame = CGRectMake(20, CGRectGetMaxY(calendar.frame) + 20, view.frame.size.width - 40, 44);
    [jumpButton setTitle:@"Jump to January 1900" forState:UIControlStateNormal];
    [jumpButton addTarget:self action:@selector(jumpTo1900) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:jumpButton];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.dateFormatter = [[NSDateFormatter alloc] init];
    self.dateFormatter.dateFormat = @"yyyy-MM-dd";

    NSDate *startDate = [self.dateFormatter dateFromString:@"1900-01-01"];
    [self.calendar selectDate:startDate scrollToDate:YES];
}

- (NSDate *)minimumDateForCalendar:(FSCalendar *)calendar
{
    return [self.dateFormatter dateFromString:@"1800-01-01"];
}

- (NSDate *)maximumDateForCalendar:(FSCalendar *)calendar
{
    return [self.dateFormatter dateFromString:@"2025-12-31"];
}

- (void)jumpTo1900
{
    NSDate *date = [self.dateFormatter dateFromString:@"1900-01-01"];
    [self.calendar selectDate:date scrollToDate:YES];
}

@end
