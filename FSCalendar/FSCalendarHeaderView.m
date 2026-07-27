//
//  FSCalendarHeader.m
//  Pods
//
//  Created by Wenchao Ding on 29/1/15.
//
//

#import "FSCalendar.h"
#import "FSCalendarExtensions.h"
#import "FSCalendarHeaderView.h"
#import "FSCalendarCollectionView.h"
#import "FSCalendarDynamicHeader.h"

@interface FSCalendarHeaderView ()<UICollectionViewDataSource,UICollectionViewDelegate,FSCalendarCollectionViewInternalDelegate>

- (void)scrollToOffset:(CGFloat)scrollOffset animated:(BOOL)animated;
- (void)configureCell:(FSCalendarHeaderCell *)cell atIndexPath:(NSIndexPath *)indexPath;
- (void)configureVisibleCells;
- (NSInteger)numberOfHeaderItems;
- (BOOL)isSentinelItemAtIndex:(NSInteger)item;

@end

@implementation FSCalendarHeaderView

#pragma mark - Life cycle

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self initialize];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self initialize];
    }
    return self;
}

- (void)initialize
{
    _scrollDirection = UICollectionViewScrollDirectionHorizontal;
    _scrollEnabled = YES;
    
    FSCalendarHeaderLayout *collectionViewLayout = [[FSCalendarHeaderLayout alloc] init];
    self.collectionViewLayout = collectionViewLayout;
    
    FSCalendarCollectionView *collectionView = [[FSCalendarCollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:collectionViewLayout];
    collectionView.scrollEnabled = NO;
    collectionView.userInteractionEnabled = NO;
    collectionView.backgroundColor = [UIColor clearColor];
    collectionView.dataSource = self;
    collectionView.delegate = self;
    collectionView.showsHorizontalScrollIndicator = NO;
    collectionView.showsVerticalScrollIndicator = NO;
    [self addSubview:collectionView];
    [collectionView registerClass:[FSCalendarHeaderCell class] forCellWithReuseIdentifier:@"cell"];
    self.collectionView = collectionView;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.collectionView.frame = CGRectMake(0, self.fs_height*0.1, self.fs_width, self.fs_height*0.9);
}

- (void)dealloc
{
    self.collectionView.dataSource = nil;
    self.collectionView.delegate = nil;
}

#pragma mark - <UICollectionViewDataSource>

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return [self numberOfHeaderItems];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    FSCalendarHeaderCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"cell" forIndexPath:indexPath];
    cell.header = self;
    [self configureCell:cell atIndexPath:indexPath];
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (![cell isKindOfClass:[FSCalendarHeaderCell class]]) {
        return;
    }
    ((FSCalendarHeaderCell *)cell).header = self;
    [self configureCell:(FSCalendarHeaderCell *)cell atIndexPath:indexPath];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self configureVisibleCells];
}

#pragma mark - Properties

- (void)setCalendar:(FSCalendar *)calendar
{
    _calendar = calendar;
    [self configureAppearance];
}

- (void)setScrollOffset:(CGFloat)scrollOffset
{
    [self setScrollOffset:scrollOffset animated:NO];
}

- (void)setScrollOffset:(CGFloat)scrollOffset animated:(BOOL)animated
{
    [self scrollToOffset:scrollOffset animated:animated];
}

- (void)scrollToOffset:(CGFloat)scrollOffset animated:(BOOL)animated
{
    if (self.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
        CGFloat step = self.collectionView.fs_width * 0.5;
        if (step <= 0 || !isfinite(step)) {
            return;
        }
        [_collectionView setContentOffset:CGPointMake((scrollOffset+0.5)*step, 0) animated:animated];
    } else {
        CGFloat step = self.collectionView.fs_height;
        if (step <= 0 || !isfinite(step)) {
            return;
        }
        [_collectionView setContentOffset:CGPointMake(0, scrollOffset*step) animated:animated];
    }
    if (!animated) {
        [_collectionView layoutIfNeeded];
        [self configureVisibleCells];
    }
}

- (void)setScrollDirection:(UICollectionViewScrollDirection)scrollDirection
{
    if (_scrollDirection != scrollDirection) {
        _scrollDirection = scrollDirection;
        _collectionViewLayout.scrollDirection = scrollDirection;
        [self setNeedsLayout];
    }
}

- (void)setScrollEnabled:(BOOL)scrollEnabled
{
    if (_scrollEnabled != scrollEnabled) {
        _scrollEnabled = scrollEnabled;
        [_collectionView.visibleCells makeObjectsPerformSelector:@selector(setNeedsLayout)];
    }
}

#pragma mark - Public

- (void)reloadData
{
    [_collectionView reloadData];
}

- (NSInteger)numberOfHeaderItems
{
    NSInteger numberOfSections = self.calendar.collectionView.numberOfSections;
    if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
        return numberOfSections;
    }
    return numberOfSections + 2;
}

- (BOOL)isSentinelItemAtIndex:(NSInteger)item
{
    if (self.scrollDirection == UICollectionViewScrollDirectionVertical) {
        return NO;
    }
    NSInteger numberOfItems = [self numberOfHeaderItems];
    return item == 0 || item == numberOfItems - 1;
}

- (void)configureCell:(FSCalendarHeaderCell *)cell atIndexPath:(NSIndexPath *)indexPath
{
    if (!cell || !indexPath) {
        return;
    }
    FSCalendarAppearance *appearance = self.calendar.appearance;
    cell.titleLabel.font = appearance.headerTitleFont;
    cell.titleLabel.textColor = appearance.headerTitleColor;
    cell.titleLabel.textAlignment = appearance.headerTitleAlignment; 
    _calendar.formatter.dateFormat = appearance.headerDateFormat;
    NSString *text = nil;
    switch (self.calendar.transitionCoordinator.representingScope) {
        case FSCalendarScopeMonth: {
            if (_scrollDirection == UICollectionViewScrollDirectionHorizontal) {
                // 多出的两项需要制空
                if ([self isSentinelItemAtIndex:indexPath.item]) {
                    text = nil;
                } else {
                    NSDate *minimumMonth = [self.calendar.gregorian fs_firstDayOfMonth:self.calendar.minimumDate];
                    NSDate *date = [self.calendar.gregorian dateByAddingUnit:NSCalendarUnitMonth value:indexPath.item-1 toDate:minimumMonth options:0];
                    text = [_calendar.formatter stringFromDate:date];
                }
            } else {
                NSDate *minimumMonth = [self.calendar.gregorian fs_firstDayOfMonth:self.calendar.minimumDate];
                NSDate *date = [self.calendar.gregorian dateByAddingUnit:NSCalendarUnitMonth value:indexPath.item toDate:minimumMonth options:0];
                text = [_calendar.formatter stringFromDate:date];
            }
            break;
        }
        case FSCalendarScopeWeek: {
            if ([self isSentinelItemAtIndex:indexPath.item]) {
                text = nil;
            } else {
                NSDate *date = [self.calendar.calculator pageForSection:indexPath.item - 1];
                text = [_calendar.formatter stringFromDate:date];
            }
            break;
        }
        default: {
            break;
        }
    }
    BOOL usesUpperCase   = (appearance.caseOptions & 15) == FSCalendarCaseOptionsHeaderUsesUpperCase;
    BOOL usesCapitalized = (appearance.caseOptions & 15) == FSCalendarCaseOptionsHeaderUsesCapitalized;
    if (usesUpperCase) {
        text = text.uppercaseString;
    } else if (usesCapitalized) {
        text = text.capitalizedString;
    }
    cell.titleLabel.text = text;
    [cell setNeedsLayout];
}

- (void)configureVisibleCells
{
    [self.collectionView.visibleCells enumerateObjectsUsingBlock:^(__kindof FSCalendarHeaderCell * _Nonnull cell, NSUInteger idx, BOOL * _Nonnull stop) {
        NSIndexPath *indexPath = [self.collectionView indexPathForCell:cell];
        if (!indexPath) {
            return;
        }
        [self configureCell:cell atIndexPath:indexPath];
    }];
}

- (void)configureAppearance
{
    [self configureVisibleCells];
}

@end


@implementation FSCalendarHeaderCell

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
        titleLabel.numberOfLines = 0;
        [self.contentView addSubview:titleLabel];
        self.titleLabel = titleLabel;
    }
    return self;
}

- (void)prepareForReuse
{
    [super prepareForReuse];
    self.titleLabel.text = nil;
    self.contentView.alpha = 1.0;
}

- (void)setBounds:(CGRect)bounds
{
    [super setBounds:bounds];
    self.titleLabel.frame = bounds;
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    CGPoint titleHeaderOffset = self.header.calendar.appearance.headerTitleOffset;
    self.titleLabel.frame = CGRectOffset(self.contentView.bounds,
                                         titleHeaderOffset.x,
                                         titleHeaderOffset.y);
    
    if (self.header.scrollDirection == UICollectionViewScrollDirectionHorizontal) {
        CGFloat width = self.fs_width;
        if (width <= 0 || !isfinite(width)) {
            self.contentView.alpha = 1.0;
            return;
        }
        CGFloat position = [self.contentView convertPoint:CGPointMake(CGRectGetMidX(self.contentView.bounds), CGRectGetMidY(self.contentView.bounds)) toView:self.header].x;
        CGFloat center = CGRectGetMidX(self.header.bounds);
        if (self.header.scrollEnabled) {
            CGFloat alpha = 1.0 - (1.0-self.header.calendar.appearance.headerMinimumDissolvedAlpha)*ABS(center-position)/width;
            if (!isfinite(alpha)) {
                alpha = 1.0;
            }
            self.contentView.alpha = MIN(1.0, MAX(0.0, alpha));
        } else {
            self.contentView.alpha = (position > self.header.fs_width*0.25 && position < self.header.fs_width*0.75);
        }
    } else if (self.header.scrollDirection == UICollectionViewScrollDirectionVertical) {
        CGFloat height = self.fs_height;
        if (height <= 0 || !isfinite(height)) {
            self.contentView.alpha = 1.0;
            return;
        }
        CGFloat position = [self.contentView convertPoint:CGPointMake(CGRectGetMidX(self.contentView.bounds), CGRectGetMidY(self.contentView.bounds)) toView:self.header].y;
        CGFloat center = CGRectGetMidY(self.header.bounds);
        CGFloat alpha = 1.0 - (1.0-self.header.calendar.appearance.headerMinimumDissolvedAlpha)*ABS(center-position)/height;
        if (!isfinite(alpha)) {
            alpha = 1.0;
        }
        self.contentView.alpha = MIN(1.0, MAX(0.0, alpha));
    }
}

@end


@implementation FSCalendarHeaderLayout

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        self.minimumInteritemSpacing = 0;
        self.minimumLineSpacing = 0;
        self.sectionInset = UIEdgeInsetsZero;
        self.itemSize = CGSizeMake(1, 1);
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(didReceiveOrientationChangeNotification:) name:UIDeviceOrientationDidChangeNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
}

- (void)prepareLayout
{
    [super prepareLayout];
    
    self.itemSize = CGSizeMake(
                               self.collectionView.fs_width*((self.scrollDirection==UICollectionViewScrollDirectionHorizontal)?0.5:1),
                               self.collectionView.fs_height
                              );
    
}

- (void)didReceiveOrientationChangeNotification:(NSNotification *)notificatino
{
    [self invalidateLayout];
}

- (BOOL)flipsHorizontallyInOppositeLayoutDirection
{
    return YES;
}

@end

@implementation FSCalendarHeaderTouchDeliver

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *hitView = [super hitTest:point withEvent:event];
    if (hitView == self) {
        return _calendar.collectionView ?: hitView;
    }
    return hitView;
}

@end
