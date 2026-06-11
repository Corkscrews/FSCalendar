//
//  DateInputCalendarViewController.m
//  FSCalendar
//

#import "DateInputCalendarViewController.h"
#import "FSCalendar.h"

@interface DateInputCalendarViewController () <FSCalendarDataSource, FSCalendarDelegate, UITextFieldDelegate>

@property (weak, nonatomic) FSCalendar *calendar;
@property (weak, nonatomic) UITextField *dateTextField;
@property (weak, nonatomic) UILabel *statusLabel;
@property (strong, nonatomic) NSDateFormatter *dateFormatter;

@end

@implementation DateInputCalendarViewController

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.title = @"Date Input";
    }
    return self;
}

- (void)loadView
{
    UIView *view = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    view.backgroundColor = [UIColor groupTableViewBackgroundColor];
    self.view = view;

    CGFloat height = [[UIDevice currentDevice].model hasPrefix:@"iPad"] ? 450 : 300;
    CGFloat top = CGRectGetMaxY(self.navigationController.navigationBar.frame);

    FSCalendar *calendar = [[FSCalendar alloc] initWithFrame:CGRectMake(0, top, view.frame.size.width, height)];
    calendar.dataSource = self;
    calendar.delegate = self;
    calendar.appearance.headerDateFormat = @"MMMM yyyy";
    [view addSubview:calendar];
    self.calendar = calendar;

    CGFloat margin = 20;
    CGFloat fieldY = CGRectGetMaxY(calendar.frame) + 20;
    CGFloat fieldWidth = view.frame.size.width - margin * 2 - 70;

    UITextField *dateTextField = [[UITextField alloc] initWithFrame:CGRectMake(margin, fieldY, fieldWidth, 44)];
    dateTextField.borderStyle = UITextBorderStyleRoundedRect;
    dateTextField.placeholder = @"yyyy-MM-dd";
    dateTextField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    dateTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    dateTextField.autocorrectionType = UITextAutocorrectionTypeNo;
    dateTextField.returnKeyType = UIReturnKeyGo;
    dateTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    dateTextField.delegate = self;
    [view addSubview:dateTextField];
    self.dateTextField = dateTextField;

    UIButton *goButton = [UIButton buttonWithType:UIButtonTypeSystem];
    goButton.frame = CGRectMake(CGRectGetMaxX(dateTextField.frame) + 10, fieldY, 60, 44);
    [goButton setTitle:@"Go" forState:UIControlStateNormal];
    [goButton addTarget:self action:@selector(loadEnteredDate) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:goButton];

    UILabel *statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(margin, CGRectGetMaxY(dateTextField.frame) + 12, view.frame.size.width - margin * 2, 40)];
    statusLabel.font = [UIFont systemFontOfSize:14];
    statusLabel.textColor = [UIColor darkGrayColor];
    statusLabel.numberOfLines = 2;
    statusLabel.text = @"Enter a date and tap Go to jump the calendar.";
    [view addSubview:statusLabel];
    self.statusLabel = statusLabel;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.dateFormatter = [[NSDateFormatter alloc] init];
    self.dateFormatter.dateFormat = @"yyyy-MM-dd";
    self.dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];

    self.dateTextField.text = @"1900-01-01";
    [self loadEnteredDate];
}

#pragma mark - Actions

- (void)loadEnteredDate
{
    NSString *text = [self.dateTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        self.statusLabel.text = @"Please enter a date.";
        self.statusLabel.textColor = [UIColor redColor];
        return;
    }

    NSDate *date = [self.dateFormatter dateFromString:text];
    if (!date) {
        self.statusLabel.text = @"Invalid format. Use yyyy-MM-dd (e.g. 1850-06-15).";
        self.statusLabel.textColor = [UIColor redColor];
        return;
    }

    NSDate *minimumDate = [self minimumDateForCalendar:self.calendar];
    NSDate *maximumDate = [self maximumDateForCalendar:self.calendar];
    if ([date compare:minimumDate] == NSOrderedAscending || [date compare:maximumDate] == NSOrderedDescending) {
        self.statusLabel.text = [NSString stringWithFormat:@"Date must be between %@ and %@.",
                                 [self.dateFormatter stringFromDate:minimumDate],
                                 [self.dateFormatter stringFromDate:maximumDate]];
        self.statusLabel.textColor = [UIColor redColor];
        return;
    }

    [self.dateTextField resignFirstResponder];
    [self.calendar selectDate:date scrollToDate:YES];
    self.statusLabel.text = [NSString stringWithFormat:@"Showing %@", text];
    self.statusLabel.textColor = [UIColor darkGrayColor];
}

#pragma mark - <UITextFieldDelegate>

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [self loadEnteredDate];
    return YES;
}

#pragma mark - <FSCalendarDataSource>

- (NSDate *)minimumDateForCalendar:(FSCalendar *)calendar
{
    return [self.dateFormatter dateFromString:@"1800-01-01"];
}

- (NSDate *)maximumDateForCalendar:(FSCalendar *)calendar
{
    return [self.dateFormatter dateFromString:@"2025-12-31"];
}

@end
