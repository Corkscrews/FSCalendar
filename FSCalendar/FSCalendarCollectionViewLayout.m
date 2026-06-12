//
//  FSCalendarCollectionViewLayout.m
//  FSCalendar
//
//  Created by dingwenchao on 1/3/16.
//  Copyright © 2016 Wenchao Ding. All rights reserved.
//

#import "FSCalendarCollectionViewLayout.h"
#import "FSCalendar.h"
#import "FSCalendarDynamicHeader.h"
#import "FSCalendarCollectionView.h"
#import "FSCalendarExtensions.h"
#import "FSCalendarConstants.h"
#import "FSCalendarSeparatorDecorationView.h"
#import "FSCalendarSectionMetrics.h"

#define kFSCalendarSeparatorInterRows @"FSCalendarSeparatorInterRows"
#define kFSCalendarSeparatorInterColumns @"FSCalendarSeparatorInterColumns"

@interface FSCalendarCollectionViewLayout ()

@property (assign, nonatomic) CGFloat *widths;
@property (assign, nonatomic) CGFloat *heights;
@property (assign, nonatomic) CGFloat *lefts;
@property (assign, nonatomic) CGFloat *tops;

@property (assign, nonatomic) CGSize estimatedItemSize;

@property (assign, nonatomic) CGSize contentSize;
@property (assign, nonatomic) CGSize collectionViewSize;
@property (assign, nonatomic) CGSize headerReferenceSize;
@property (assign, nonatomic) NSInteger numberOfSections;

@property (assign, nonatomic) FSCalendarSeparators separators;
@property (assign, nonatomic) NSInteger layoutSignature;

@property (strong, nonatomic) FSCalendarSectionMetrics *sectionMetrics;

@property (strong, nonatomic) NSMutableDictionary<NSIndexPath *, UICollectionViewLayoutAttributes *> *itemAttributes;
@property (strong, nonatomic) NSMutableDictionary<NSIndexPath *, UICollectionViewLayoutAttributes *> *headerAttributes;
@property (strong, nonatomic) NSMutableDictionary<NSIndexPath *, UICollectionViewLayoutAttributes *> *rowSeparatorAttributes;

- (void)didReceiveNotifications:(NSNotification *)notification;
- (CGFloat)calculateRowOffset:(NSInteger)row totalRows:(NSInteger)totalRows;

@end

@implementation FSCalendarCollectionViewLayout

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.estimatedItemSize = CGSizeZero;
        self.widths = NULL;
        self.heights = NULL;
        self.tops = NULL;
        self.lefts = NULL;
        
        self.sectionMetrics = [[FSCalendarSectionMetrics alloc] init];
        
        self.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        self.sectionInsets = UIEdgeInsetsMake(5, 0, 5, 0);
        
        self.itemAttributes = NSMutableDictionary.dictionary;
        self.headerAttributes = NSMutableDictionary.dictionary;
        self.rowSeparatorAttributes = NSMutableDictionary.dictionary;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveNotifications:) name:UIDeviceOrientationDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveNotifications:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        
        [self registerClass:FSCalendarSeparatorDecorationView.class forDecorationViewOfKind:kFSCalendarSeparatorInterRows];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
    
    free(self.widths);
    free(self.heights);
    free(self.tops);
    free(self.lefts);
}

- (NSInteger)layoutSignatureForCurrentState
{
    NSInteger signature = self.calendar.firstWeekday;
    signature = signature * 31 + self.calendar.placeholderType;
    signature = signature * 31 + self.calendar.adjustsBoundingRectWhenChangingMonths;
    signature = signature * 31 + self.calendar.transitionCoordinator.representingScope;
    signature = signature * 31 + self.collectionView.numberOfSections;
    if (self.calendar.floatingMode) {
        NSDate *minimumMonth = [self.calendar.gregorian fs_firstDayOfMonth:self.calendar.minimumDate];
        NSDateComponents *components = [self.calendar.gregorian components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:minimumMonth];
        signature = signature * 31 + components.year;
        signature = signature * 31 + components.month;
        signature = signature * 31 + (NSInteger)(self.calendar.rowHeight * 100);
        signature = signature * 31 + (NSInteger)(self.calendar.preferredHeaderHeight * 100);
        signature = signature * 31 + (NSInteger)(self.calendar.preferredWeekdayHeight * 100);
        signature = signature * 31 + (NSInteger)(self.sectionInsets.top * 100);
        signature = signature * 31 + (NSInteger)(self.sectionInsets.bottom * 100);
        signature = signature * 31 + (NSInteger)(self.sectionInsets.left * 100);
        signature = signature * 31 + (NSInteger)(self.sectionInsets.right * 100);
        signature = signature * 31 + (NSInteger)self.calendar.timeZone.hash;
    }
    return signature;
}

- (void)prepareLayout
{
    NSInteger layoutSignature = [self layoutSignatureForCurrentState];
    if (CGSizeEqualToSize(self.collectionViewSize, self.collectionView.frame.size) && self.numberOfSections == self.collectionView.numberOfSections && self.separators == self.calendar.appearance.separators && self.layoutSignature == layoutSignature) {
        return;
    }
    self.collectionViewSize = self.collectionView.frame.size;
    self.separators = self.calendar.appearance.separators;
    self.layoutSignature = layoutSignature;
    
    [self.itemAttributes removeAllObjects];
    [self.headerAttributes removeAllObjects];
    [self.rowSeparatorAttributes removeAllObjects];
    
    self.headerReferenceSize = ({
        CGSize headerSize = CGSizeZero;
        if (self.calendar.floatingMode) {
            CGFloat headerHeight = self.calendar.preferredWeekdayHeight*1.5+self.calendar.preferredHeaderHeight;
            headerSize = CGSizeMake(self.collectionView.fs_width, headerHeight);
        }
        headerSize;
    });
    self.estimatedItemSize = ({
        CGFloat width = (self.collectionView.fs_width-self.sectionInsets.left-self.sectionInsets.right)/7.0;
        CGFloat height = ({
            CGFloat height = FSCalendarStandardRowHeight;
            if (!self.calendar.floatingMode) {
                switch (self.calendar.transitionCoordinator.representingScope) {
                    case FSCalendarScopeMonth: {
                        height = (self.collectionView.fs_height-self.sectionInsets.top-self.sectionInsets.bottom)/6.0;
                        break;
                    }
                    case FSCalendarScopeWeek: {
                        height = (self.collectionView.fs_height-self.sectionInsets.top-self.sectionInsets.bottom);
                        break;
                    }
                    default:
                        break;
                }
            } else {
                height = self.calendar.rowHeight;
            }
            height;
        });
        CGSize size = CGSizeMake(width, height);
        size;
    });
    
    // Calculate item widths and lefts
    free(self.widths);
    self.widths = ({
        NSInteger columnCount = 7;
        size_t columnSize = sizeof(CGFloat)*columnCount;
        CGFloat *widths = malloc(columnSize);
        CGFloat contentWidth = self.collectionView.fs_width - self.sectionInsets.left - self.sectionInsets.right;
        FSCalendarSliceCake(contentWidth, columnCount, widths);
        widths;
    });
    
    free(self.lefts);
    self.lefts = ({
        NSInteger columnCount = 7;
        size_t columnSize = sizeof(CGFloat)*columnCount;
        CGFloat *lefts = malloc(columnSize);
        lefts[0] = self.sectionInsets.left;
        for (int i = 1; i < columnCount; i++) {
            lefts[i] = lefts[i-1] + self.widths[i-1];
        }
        lefts;
    });
    
    // Calculate item heights and tops
    free(self.heights);
    self.heights = ({
        NSInteger rowCount = self.calendar.transitionCoordinator.representingScope == FSCalendarScopeWeek ? 1 : 6;
        size_t rowSize = sizeof(CGFloat)*rowCount;
        CGFloat *heights = malloc(rowSize);
        if (!self.calendar.floatingMode) {
            CGFloat contentHeight = self.collectionView.fs_height - self.sectionInsets.top - self.sectionInsets.bottom;
            FSCalendarSliceCake(contentHeight, rowCount, heights);
        } else {
            for (int i = 0; i < rowCount; i++) {
                heights[i] = self.estimatedItemSize.height;
            }
        }
        heights;
    });
    
    free(self.tops);
    self.tops = ({
        NSInteger rowCount = self.calendar.transitionCoordinator.representingScope == FSCalendarScopeWeek ? 1 : 6;
        size_t rowSize = sizeof(CGFloat)*rowCount;
        CGFloat *tops = malloc(rowSize);
        tops[0] = self.sectionInsets.top;
        for (int i = 1; i < rowCount; i++) {
            tops[i] = tops[i-1] + self.heights[i-1];
        }
        tops;
    });
    
    // Calculate content size
    self.numberOfSections = self.collectionView.numberOfSections;
    self.contentSize = ({
        CGSize contentSize = CGSizeZero;
        if (!self.calendar.floatingMode) {
            CGFloat width = self.collectionView.fs_width;
            CGFloat height = self.collectionView.fs_height;
            switch (self.scrollDirection) {
                case UICollectionViewScrollDirectionHorizontal: {
                    width *= self.numberOfSections;
                    break;
                }
                case UICollectionViewScrollDirectionVertical: {
                    height *= self.numberOfSections;
                    break;
                }
                default:
                    break;
            }
            contentSize = CGSizeMake(width, height);
        } else {
            [self.sectionMetrics invalidateMetrics];
            self.sectionMetrics.calendar = self.calendar;
            self.sectionMetrics.layout = self;
            [self.sectionMetrics configureWithHeaderHeight:self.headerReferenceSize.height
                                                 rowHeight:self.estimatedItemSize.height
                                          numberOfSections:self.numberOfSections];
            CGFloat width = self.collectionView.fs_width;
            CGFloat height = [self.sectionMetrics totalContentHeight];
            contentSize = CGSizeMake(width, height);
        }
        contentSize;
    });
    
    __weak FSCalendar *calendar = self.calendar;
    dispatch_async(dispatch_get_main_queue(), ^{
        [calendar adjustMonthPosition];
    });
}

- (CGFloat)floatingTopForSection:(NSInteger)section
{
    return [self.sectionMetrics topForSection:section];
}

- (CGSize)collectionViewContentSize
{
    return self.contentSize;
}

- (NSArray *)layoutAttributesForElementsInRect:(CGRect)rect
{
    // Clipping
    rect = CGRectIntersection(rect, CGRectMake(0, 0, self.contentSize.width, self.contentSize.height));
    if (CGRectIsEmpty(rect)) return nil;
    
    // Calculating attributes
    NSMutableArray<UICollectionViewLayoutAttributes *> *layoutAttributes = [NSMutableArray array];
    
    if (!self.calendar.floatingMode) {
        
        switch (self.scrollDirection) {
            case UICollectionViewScrollDirectionHorizontal: {
                
                NSInteger startColumn = ({
                    NSInteger startSection = rect.origin.x/self.collectionView.fs_width;
                    CGFloat widthDelta = FSCalendarMod(CGRectGetMinX(rect), self.collectionView.fs_width)-self.sectionInsets.left;
                    widthDelta = MIN(MAX(0, widthDelta), self.collectionView.fs_width-self.sectionInsets.left);
                    NSInteger countDelta = FSCalendarFloor(widthDelta/self.estimatedItemSize.width);
                    NSInteger startColumn = startSection*7 + countDelta;
                    startColumn;
                });
                
                NSInteger endColumn = ({
                    NSInteger endColumn;
                    CGFloat section = CGRectGetMaxX(rect)/self.collectionView.fs_width;
                    CGFloat remainder = FSCalendarMod(section, 1);
                    // https://stackoverflow.com/a/10335601/2398107
                    if (remainder <= MAX(100*FLT_EPSILON*ABS(remainder), FLT_MIN)) {
                        endColumn = FSCalendarFloor(section)*7 - 1;
                    } else {
                        CGFloat widthDelta = FSCalendarMod(CGRectGetMaxX(rect), self.collectionView.fs_width)-self.sectionInsets.left;
                        widthDelta = MIN(MAX(0, widthDelta), self.collectionView.fs_width - self.sectionInsets.left);
                        NSInteger countDelta = FSCalendarCeil(widthDelta/self.estimatedItemSize.width);
                        endColumn = FSCalendarFloor(section)*7 + countDelta - 1;
                    }
                    endColumn;
                });
                
                NSInteger numberOfRows = self.calendar.transitionCoordinator.representingScope == FSCalendarScopeMonth ? 6 : 1;
                
                for (NSInteger column = startColumn; column <= endColumn; column++) {
                    for (NSInteger row = 0; row < numberOfRows; row++) {
                        NSInteger section = column / 7;
                        NSInteger item = column % 7 + row * 7;
                        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];
                        UICollectionViewLayoutAttributes *itemAttributes = [self layoutAttributesForItemAtIndexPath:indexPath];
                        [layoutAttributes addObject:itemAttributes];
                        
                        UICollectionViewLayoutAttributes *rowSeparatorAttributes = [self layoutAttributesForDecorationViewOfKind:kFSCalendarSeparatorInterRows atIndexPath:indexPath];
                        if (rowSeparatorAttributes) {
                            [layoutAttributes addObject:rowSeparatorAttributes];
                        }
                    }
                }
                
                break;
            }
            case UICollectionViewScrollDirectionVertical: {
                
                NSInteger startRow = ({
                    NSInteger startSection = rect.origin.y/self.collectionView.fs_height;
                    CGFloat heightDelta = FSCalendarMod(CGRectGetMinY(rect), self.collectionView.fs_height)-self.sectionInsets.top;
                    heightDelta = MIN(MAX(0, heightDelta), self.collectionView.fs_height-self.sectionInsets.top);
                    NSInteger countDelta = FSCalendarFloor(heightDelta/self.estimatedItemSize.height);
                    NSInteger startRow = startSection*6 + countDelta;
                    startRow;
                });
                
                NSInteger endRow = ({
                    NSInteger endRow;
                    CGFloat section = CGRectGetMaxY(rect)/self.collectionView.fs_height;
                    CGFloat remainder = FSCalendarMod(section, 1);
                    // https://stackoverflow.com/a/10335601/2398107
                    if (remainder <= MAX(100*FLT_EPSILON*ABS(remainder), FLT_MIN)) {
                        endRow = FSCalendarFloor(section)*6 - 1;
                    } else {
                        CGFloat heightDelta = FSCalendarMod(CGRectGetMaxY(rect), self.collectionView.fs_height)-self.sectionInsets.top;
                        heightDelta = MIN(MAX(0, heightDelta), self.collectionView.fs_height-self.sectionInsets.top);
                        NSInteger countDelta = FSCalendarCeil(heightDelta/self.estimatedItemSize.height);
                        endRow = FSCalendarFloor(section)*6 + countDelta-1;
                    }
                    endRow;
                });
                
                for (NSInteger row = startRow; row <= endRow; row++) {
                    for (NSInteger column = 0; column < 7; column++) {
                        NSInteger section = row / 6;
                        NSInteger item = column + (row % 6) * 7;
                        NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];
                        UICollectionViewLayoutAttributes *itemAttributes = [self layoutAttributesForItemAtIndexPath:indexPath];
                        [layoutAttributes addObject:itemAttributes];
                        
                        UICollectionViewLayoutAttributes *rowSeparatorAttributes = [self layoutAttributesForDecorationViewOfKind:kFSCalendarSeparatorInterRows atIndexPath:indexPath];
                        if (rowSeparatorAttributes) {
                            [layoutAttributes addObject:rowSeparatorAttributes];
                        }
                        
                    }
                }
                
                break;
            }
            default:
                break;
        }
        
    } else {
        if (self.numberOfSections <= 0) {
            return @[];
        }
        
        NSInteger startSection = [self.sectionMetrics sectionForMinVerticalOffset:CGRectGetMinY(rect)];
        NSInteger sectionRowCount = [self.sectionMetrics rowCountForSection:startSection];
        NSInteger startRowIndex = ({
            CGFloat heightDelta1 = MIN([self.sectionMetrics bottomForSection:startSection]-CGRectGetMinY(rect)-self.sectionInsets.bottom, sectionRowCount*self.estimatedItemSize.height);
            NSInteger startRowCount = FSCalendarCeil(heightDelta1/self.estimatedItemSize.height);
            NSInteger startRowIndex = sectionRowCount-startRowCount;
            startRowIndex;
        });
        startRowIndex = MAX(0, MIN(startRowIndex, sectionRowCount - 1));
        
        NSInteger endSection = [self.sectionMetrics sectionForMaxVerticalOffset:CGRectGetMaxY(rect)];
        NSInteger endSectionRowCount = [self.sectionMetrics rowCountForSection:endSection];
        NSInteger endRowIndex = ({
            CGFloat heightDelta2 = MAX(CGRectGetMaxY(rect) - [self.sectionMetrics topForSection:endSection]- self.headerReferenceSize.height - self.sectionInsets.top, 0);
            NSInteger endRowCount = FSCalendarCeil(heightDelta2/self.estimatedItemSize.height);
            NSInteger endRowIndex = endRowCount - 1;
            endRowIndex;
        });
        endRowIndex = MAX(0, MIN(endRowIndex, endSectionRowCount - 1));
        
        for (NSInteger section = startSection; section <= endSection; section++) {
            NSInteger rowCount = [self.sectionMetrics rowCountForSection:section];
            NSInteger startRow = (section == startSection) ? startRowIndex : 0;
            NSInteger endRow = (section == endSection) ? endRowIndex : rowCount-1;
            UICollectionViewLayoutAttributes *headerAttributes = [self layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionHeader atIndexPath:[NSIndexPath indexPathForItem:0 inSection:section]];
            [layoutAttributes addObject:headerAttributes];
            for (NSInteger row = startRow; row <= endRow; row++) {
                for (NSInteger column = 0; column < 7; column++) {
                    NSInteger item = row * 7 + column;
                    NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];
                    UICollectionViewLayoutAttributes *itemAttributes = [self layoutAttributesForItemAtIndexPath:indexPath];
                    [layoutAttributes addObject:itemAttributes];
                    UICollectionViewLayoutAttributes *rowSeparatorAttributes = [self layoutAttributesForDecorationViewOfKind:kFSCalendarSeparatorInterRows atIndexPath:indexPath];
                    if (rowSeparatorAttributes) {
                        [layoutAttributes addObject:rowSeparatorAttributes];
                    }
                }
            }
        }
        
    }
    return [NSArray arrayWithArray:layoutAttributes];
    
}

// Items
- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath
{
    FSCalendarCoordinate coordinate = [self.calendar.calculator coordinateForIndexPath:indexPath];
    NSInteger column = coordinate.column;
    NSInteger row = coordinate.row;
    NSInteger numberOfRows = [self.calendar.calculator numberOfRowsInSection:indexPath.section];
    UICollectionViewLayoutAttributes *attributes = self.itemAttributes[indexPath];
    if (!attributes) {
        attributes = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
        CGRect frame = ({
            CGFloat width = self.widths[column];
            CGFloat height = self.heights[row];
            CGFloat x, y;
            switch (self.scrollDirection) {
                case UICollectionViewScrollDirectionHorizontal: {
                    x = self.lefts[column] + indexPath.section * self.collectionView.fs_width;
                    y = [self calculateRowOffset:row totalRows:numberOfRows];
                    break;
                }
                case UICollectionViewScrollDirectionVertical: {
                    x = self.lefts[column];
                    if (!self.calendar.floatingMode) {
                        CGFloat sectionTop = indexPath.section * self.collectionView.fs_height;
                        CGFloat rowOffset = [self calculateRowOffset:row totalRows:numberOfRows];
                        y = sectionTop + rowOffset;
                    } else {
                        y = [self.sectionMetrics topForSection:indexPath.section] + self.headerReferenceSize.height + self.tops[row];
                    }
                    break;
                }
                default:
                    break;
            }
            CGRect frame = CGRectMake(x, y, width, height);
            frame;
        });
        attributes.frame = frame;
        self.itemAttributes[indexPath] = attributes;
    }
    return attributes;
}

// Section headers
- (UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath
{
    if ([elementKind isEqualToString:UICollectionElementKindSectionHeader]) {
        UICollectionViewLayoutAttributes *attributes = self.headerAttributes[indexPath];
        if (!attributes) {
            attributes = [UICollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionHeader withIndexPath:indexPath];
            attributes.frame = CGRectMake(0, [self.sectionMetrics topForSection:indexPath.section], self.collectionView.fs_width, self.headerReferenceSize.height);
            self.headerAttributes[indexPath] = attributes;
        }
        return attributes;
    }
    return nil;
}

// Separators
- (UICollectionViewLayoutAttributes *)layoutAttributesForDecorationViewOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath
{
    if ([elementKind isEqualToString:kFSCalendarSeparatorInterRows] && (self.separators & FSCalendarSeparatorInterRows)) {
        UICollectionViewLayoutAttributes *attributes = self.rowSeparatorAttributes[indexPath];
        if (!attributes) {
            FSCalendarCoordinate coordinate = [self.calendar.calculator coordinateForIndexPath:indexPath];
            if (coordinate.row >= [self.calendar.calculator numberOfRowsInSection:indexPath.section]-1) {
                return nil;
            }
            attributes = [UICollectionViewLayoutAttributes layoutAttributesForDecorationViewOfKind:kFSCalendarSeparatorInterRows withIndexPath:indexPath];
            CGFloat x, y;
            if (!self.calendar.floatingMode) {
                CGFloat rowOffset = [self calculateRowOffset:coordinate.row totalRows:[self.calendar.calculator numberOfRowsInSection:indexPath.section]] + self.heights[coordinate.row];
                switch (self.scrollDirection) {
                    case UICollectionViewScrollDirectionHorizontal: {
                        x = self.lefts[coordinate.column] + indexPath.section * self.collectionView.fs_width;
                        y = rowOffset;
                        break;
                    }
                    case UICollectionViewScrollDirectionVertical: {
                        x = 0;
                        y = indexPath.section * self.collectionView.fs_height + rowOffset;
                        break;
                    }
                    default:
                        break;
                }
            } else {
                x = 0;
                y = [self.sectionMetrics topForSection:indexPath.section] + self.headerReferenceSize.height + self.tops[coordinate.row] + self.heights[coordinate.row];
            }
            CGFloat width = self.collectionView.fs_width;
            CGFloat height = FSCalendarStandardSeparatorThickness;
            attributes.frame = CGRectMake(x, y, width, height);
            attributes.zIndex = NSIntegerMax;
            self.rowSeparatorAttributes[indexPath] = attributes;
        }
        return attributes;
    }
    return nil;
}

- (BOOL)flipsHorizontallyInOppositeLayoutDirection
{
    return YES;
}

#pragma mark - Notifications

- (void)didReceiveNotifications:(NSNotification *)notification
{
    if ([notification.name isEqualToString:UIDeviceOrientationDidChangeNotification]) {
        [self invalidateLayout];
    }
    if ([notification.name isEqualToString:UIApplicationDidReceiveMemoryWarningNotification]) {
        [self.calendar.calculator clearCaches];
        [self.sectionMetrics invalidateMetrics];
        [self.itemAttributes removeAllObjects];
        [self.headerAttributes removeAllObjects];
        [self.rowSeparatorAttributes removeAllObjects];
        self.layoutSignature = 0;
        [self invalidateLayout];
    }
}

#pragma mark - Private properties

- (void)setScrollDirection:(UICollectionViewScrollDirection)scrollDirection
{
    if (_scrollDirection != scrollDirection) {
        _scrollDirection = scrollDirection;
        self.collectionViewSize = CGSizeAutomatic;
        [self.sectionMetrics invalidateMetrics];
    }
}

#pragma mark - Private functions

- (CGFloat)calculateRowOffset:(NSInteger)row totalRows:(NSInteger)totalRows
{
    if (self.calendar.adjustsBoundingRectWhenChangingMonths) {
        return self.tops[row];
    }
    CGFloat height = self.heights[row];
    switch (totalRows) {
        case 4:
        case 5: {
            CGFloat contentHeight = self.collectionView.fs_height - self.sectionInsets.top - self.sectionInsets.bottom;
            CGFloat rowSpan = contentHeight/totalRows;
            return (row + 0.5) * rowSpan - height * 0.5 + self.sectionInsets.top;
        }
        case 6:
        default:
            return self.tops[row];
    }
}

@end


#undef kFSCalendarSeparatorInterColumns
#undef kFSCalendarSeparatorInterRows
