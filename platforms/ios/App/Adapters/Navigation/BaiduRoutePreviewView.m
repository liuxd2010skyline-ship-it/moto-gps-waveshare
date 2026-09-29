#import "BaiduRoutePreviewView.h"

#import <BaiduMapAPI_Map/BMKMapView.h>
#import <BaiduMapAPI_Base/BMKTypes.h>
#import <BaiduMapAPI_Utils/BMKGeometry.h>
#import <CoreLocation/CoreLocation.h>
#import <math.h>

#import "moto_map_visual_style.h"

static UIColor *MotoMapColor(unsigned int rgb) {
    return [UIColor colorWithRed:MOTO_MAP_RED(rgb) / 255.0
                           green:MOTO_MAP_GREEN(rgb) / 255.0
                            blue:MOTO_MAP_BLUE(rgb) / 255.0 alpha:1];
}

@interface MotoRouteStrokeView : UIView
@property (nonatomic, weak) BMKMapView *mapView;
@property (nonatomic, copy) NSArray<NSValue *> *coordinates;
@property (nonatomic) CGFloat mapDimmingAlpha;
@end

@implementation MotoRouteStrokeView

- (void)drawRect:(CGRect)rect {
    BMKMapView *map = self.mapView;
    if (!map || self.coordinates.count < 2) { return; }
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) { return; }

    // Tint the complete Baidu-rendered base map; keep its own logo visible.
    CGContextSetFillColorWithColor(context, UIColor.blackColor.CGColor);
    CGContextSetAlpha(context, self.mapDimmingAlpha);
    CGContextFillRect(context, self.bounds);
    CGContextSetAlpha(context, 1);

    UIBezierPath *route = [UIBezierPath bezierPath];
    for (NSUInteger index = 0; index < self.coordinates.count; index++) {
        CLLocationCoordinate2D coordinate;
        [self.coordinates[index] getValue:&coordinate];
        CGPoint point = [map convertCoordinate:coordinate toPointToView:self];
        if (!isfinite(point.x) || !isfinite(point.y)) { return; }
        if (index == 0) { [route moveToPoint:point]; }
        else { [route addLineToPoint:point]; }
    }
    CGFloat scale = MIN(self.bounds.size.width / MOTO_MAP_DESIGN_WIDTH, 1.25);
    route.lineJoinStyle = kCGLineJoinRound;
    route.lineCapStyle = kCGLineCapRound;
    route.lineWidth = MOTO_MAP_ROUTE_SHADOW_WIDTH * scale;
    [MotoMapColor(MOTO_MAP_ROUTE_SHADOW) setStroke];
    [route stroke];
    route.lineWidth = MOTO_MAP_ROUTE_WIDTH * scale;
    [MotoMapColor(MOTO_MAP_ROUTE) setStroke];
    [route stroke];

    CLLocationCoordinate2D first, last;
    [self.coordinates.firstObject getValue:&first];
    [self.coordinates.lastObject getValue:&last];
    CGPoint start = [map convertCoordinate:first toPointToView:self];
    CGPoint end = [map convertCoordinate:last toPointToView:self];
    CGFloat markerRadius = MAX(4, 6 * scale);
    [MotoMapColor(MOTO_MAP_ICE) setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(start.x - markerRadius,
        start.y - markerRadius, markerRadius * 2, markerRadius * 2)] fill];
    [MotoMapColor(MOTO_MAP_AMBER) setFill];
    [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(end.x - markerRadius,
        end.y - markerRadius, markerRadius * 2, markerRadius * 2)] fill];
}

@end

@interface BaiduRoutePreviewView () <BMKMapViewDelegate>
@property (nonatomic, strong) BMKMapView *mapView;
@property (nonatomic, strong) MotoRouteStrokeView *strokeView;
@property (nonatomic, copy) NSArray<NSValue *> *coordinates;
@property (nonatomic, copy) NSString *customMapStyleID;
@property (nonatomic) CGSize fittedSize;
@property (nonatomic) BOOL needsFit;
@end

@implementation BaiduRoutePreviewView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) { return nil; }
    self.backgroundColor = MotoMapColor(MOTO_MAP_BLACK);
    _mapView = [[BMKMapView alloc] initWithFrame:self.bounds];
    _mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _mapView.gesturesEnabled = NO;
    _mapView.showMapScaleBar = NO;
    _mapView.buildingsEnabled = NO;
    // The preview is clipped to a circle. Move Baidu's logo into the wider
    // part of the lower disc so it remains visible.
    _mapView.logoPosition = BMKLogoPositionCenterBottom;
    _mapView.mapPadding = UIEdgeInsetsMake(0, 0, 36, 0);
    _mapView.delegate = self;
    [self addSubview:_mapView];

    _strokeView = [[MotoRouteStrokeView alloc] initWithFrame:self.bounds];
    _strokeView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _strokeView.backgroundColor = UIColor.clearColor;
    _strokeView.opaque = NO;
    _strokeView.userInteractionEnabled = NO;
    _strokeView.mapView = _mapView;
    _strokeView.mapDimmingAlpha = 0.36;
    [self addSubview:_strokeView];
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) { [self.mapView viewWillAppear]; }
    else { [self.mapView viewWillDisappear]; }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = MIN(self.bounds.size.width, self.bounds.size.height) / 2;
    self.clipsToBounds = YES;
    if (!CGSizeEqualToSize(self.fittedSize, self.bounds.size)) {
        self.fittedSize = self.bounds.size;
        self.needsFit = YES;
    }
    [self fitRouteIfNeeded];
}

- (void)showRoutePoints:(NSArray<NSDictionary<NSString *, NSNumber *> *> *)points {
    NSAssert(NSThread.isMainThread, @"Baidu map preview must run on the main thread");
    NSMutableArray<NSValue *> *valid = [NSMutableArray arrayWithCapacity:points.count];
    for (NSDictionary<NSString *, NSNumber *> *point in points) {
        double latitude = [point[@"latitude"] doubleValue];
        double longitude = [point[@"longitude"] doubleValue];
        CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(latitude, longitude);
        if (isfinite(latitude) && isfinite(longitude) &&
            CLLocationCoordinate2DIsValid(coordinate) &&
            (latitude != 0 || longitude != 0)) {
            [valid addObject:[NSValue valueWithBytes:&coordinate
                                           objCType:@encode(CLLocationCoordinate2D)]];
        }
    }
    // SwiftUI may update for unrelated model changes; avoid resetting the map.
    if ([valid isEqualToArray:self.coordinates]) { return; }
    self.coordinates = valid;
    self.strokeView.coordinates = valid;
    self.needsFit = YES;
    [self fitRouteIfNeeded];
}

- (void)useCustomMapStyleID:(NSString *)styleID {
    NSAssert(NSThread.isMainThread, @"Baidu map preview must run on the main thread");
    NSString *cleanID = [styleID stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    if ([cleanID isEqualToString:self.customMapStyleID]) { return; }
    self.customMapStyleID = cleanID;
    if (cleanID.length == 0) {
        [self.mapView setCustomMapStyleEnable:NO];
        self.strokeView.mapDimmingAlpha = 0.36;
        [self.strokeView setNeedsDisplay];
        return;
    }

    // Baidu styles are published in its official editor. If loading fails,
    // keep the normal Baidu roads with the dark screen treatment.
    BMKCustomMapStyleOption *option = [BMKCustomMapStyleOption new];
    option.customMapStyleID = cleanID;
    __weak typeof(self) weakSelf = self;
    BOOL loading = [self.mapView setCustomMapStyleWithOption:option
        preLoad:^(NSString * _Nullable path) {
            [weakSelf customStyleDidLoadForID:cleanID];
        } success:^(NSString *path) {
            [weakSelf customStyleDidLoadForID:cleanID];
        } failure:^(NSError *error, NSString * _Nullable path) {
            [weakSelf customStyleDidFailForID:cleanID];
        }];
    if (!loading) { [self customStyleDidFailForID:cleanID]; }
}

- (void)customStyleDidLoadForID:(NSString *)styleID {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self customStyleDidLoadForID:styleID]; });
        return;
    }
    if (![self.customMapStyleID isEqualToString:styleID]) { return; }
    [self.mapView setCustomMapStyleEnable:YES];
    self.strokeView.mapDimmingAlpha = 0;
    [self.strokeView setNeedsDisplay];
}

- (void)customStyleDidFailForID:(NSString *)styleID {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self customStyleDidFailForID:styleID]; });
        return;
    }
    if (![self.customMapStyleID isEqualToString:styleID]) { return; }
    [self.mapView setCustomMapStyleEnable:NO];
    self.strokeView.mapDimmingAlpha = 0.36;
    [self.strokeView setNeedsDisplay];
}

- (void)fitRouteIfNeeded {
    if (!self.needsFit || self.coordinates.count < 2 ||
        self.bounds.size.width < 1 || self.bounds.size.height < 1) { return; }
    double minX = INFINITY, minY = INFINITY;
    double maxX = -INFINITY, maxY = -INFINITY;
    for (NSValue *value in self.coordinates) {
        CLLocationCoordinate2D coordinate;
        [value getValue:&coordinate];
        BMKMapPoint point = BMKMapPointForCoordinate(coordinate);
        minX = MIN(minX, point.x);
        maxX = MAX(maxX, point.x);
        minY = MIN(minY, point.y);
        maxY = MAX(maxY, point.y);
    }
    if (!isfinite(minX) || !isfinite(minY) ||
        !isfinite(maxX) || !isfinite(maxY)) { return; }
    self.needsFit = NO;
    BMKMapRect routeRect = BMKMapRectMake(minX, minY,
        MAX(1, maxX - minX), MAX(1, maxY - minY));
    // An inscribed square occupies roughly 71% of a circle's bounding box.
    // Keep the whole route inside that safe area, including its stroke.
    CGFloat inset = MIN(self.bounds.size.width, self.bounds.size.height) * 0.17;
    UIEdgeInsets padding = UIEdgeInsetsMake(inset, inset, inset, inset);
    [self.mapView fitVisibleMapRect:routeRect edgePadding:padding withAnimated:NO];
    [self.strokeView setNeedsDisplay];
}

- (void)mapView:(BMKMapView *)mapView regionDidChangeAnimated:(BOOL)animated {
    [self.strokeView setNeedsDisplay];
}

- (void)mapViewDidFinishLoading:(BMKMapView *)mapView {
    [self.strokeView setNeedsDisplay];
}

- (void)dealloc {
    _mapView.delegate = nil;
    [_mapView viewWillDisappear];
}

@end
