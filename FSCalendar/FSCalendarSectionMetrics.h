//
//  FSCalendarSectionMetrics.h
//  FSCalendar
//
//  Copyright © 2026 Wenchao Ding. All rights reserved.
//
//  Internal lazy section geometry for floating layout.
//

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class FSCalendar;
@class FSCalendarCollectionViewLayout;

NS_ASSUME_NONNULL_BEGIN

static const NSInteger kFSCalendarSectionMetricsCycleLength = 4800; // 400 Gregorian years × 12 months
static const NSInteger kFSCalendarSectionMetricsSmallRangeThreshold = 600;

@interface FSCalendarSectionMetrics : NSObject

@property (nonatomic, weak, nullable) FSCalendar *calendar;
@property (nonatomic, weak, nullable) FSCalendarCollectionViewLayout *layout;

- (void)configureWithHeaderHeight:(CGFloat)headerHeight
                        rowHeight:(CGFloat)rowHeight
                 numberOfSections:(NSInteger)numberOfSections;

- (void)invalidateMetrics;

- (NSInteger)rowCountForSection:(NSInteger)section;
- (CGFloat)heightForSection:(NSInteger)section;
- (CGFloat)topForSection:(NSInteger)section;
- (CGFloat)bottomForSection:(NSInteger)section;
- (CGFloat)totalContentHeight;

/// Section whose vertical span contains `y` using half-open range [top, bottom).
- (NSInteger)sectionForMinVerticalOffset:(CGFloat)y;

/// Section whose vertical span contains `y` using range (top, bottom].
- (NSInteger)sectionForMaxVerticalOffset:(CGFloat)y;

@end

NS_ASSUME_NONNULL_END
