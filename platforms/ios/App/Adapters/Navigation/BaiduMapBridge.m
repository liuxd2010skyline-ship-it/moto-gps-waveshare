#import "BaiduMapBridge.h"

#import <BaiduMapAPI_Base/BMKMapManager.h>
#import <BaiduMapAPI_Search/BMKDrivingRouteSearch.h>
#import <BaiduMapAPI_Search/BMKSuggestionSearch.h>
#import <BaiduMapAPI_Utils/BMKGeometry.h>

static NSError *BaiduError(NSString *message, NSInteger code) {
    return [NSError errorWithDomain:@"MotoGPS.BaiduMap" code:code
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSString *BaiduAuthorizationDescription(NSInteger code) {
    switch (code) {
        case E_PERMISSIONCHECK_CONNECT_ERROR: return @"连接百度鉴权服务器失败，请检查手机网络";
        case E_PERMISSIONCHECK_DATA_ERROR: return @"百度鉴权服务器返回异常数据，请稍后重试";
        case E_PERMISSIONCHECK_KEY_ERROR: return @"AK 不存在，请核对百度控制台中的 AK";
        case E_PERMISSIONCHECK_MCODE_ERROR: return @"安全码与安装后的应用标识不一致";
        case E_PERMISSIONCHECK_UID_KEY_ERROR: return @"找不到该 AK 对应的应用";
        case E_PERMISSIONCHECK_KEY_FORBIDEN: return @"应用已在百度控制台被禁用";
        case E_PERMISSIONCHECK_KEY_DENY_BY_SERVER: return @"应用已被百度平台删除";
        case E_PERMISSIONCHECK_USER_DENY_BY_SERVER: return @"百度开发者账户已被平台删除";
        default: return @"请检查百度控制台中的 AK、应用类型和启用服务";
    }
}

static NSDictionary *BaiduPoint(CLLocationCoordinate2D point) {
    return @{@"longitude": @(point.longitude), @"latitude": @(point.latitude)};
}

@class BaiduMapOperation;

@interface BaiduMapBridge () <BMKGeneralDelegate>
@property (nonatomic, strong) BMKMapManager *manager;
@property (nonatomic, copy) NSString *activeAK;
@property (nonatomic, strong) NSMutableSet<BaiduMapOperation *> *operations;
@property (nonatomic) NSInteger authorizationError;
- (void)finishOperation:(BaiduMapOperation *)operation;
@end

@interface BaiduMapOperation : NSObject <BMKSuggestionSearchDelegate, BMKDrivingRouteSearchDelegate>
@property (nonatomic, weak) BaiduMapBridge *owner;
@property (nonatomic, strong) BMKSuggestionSearch *suggestion;
@property (nonatomic, strong) BMKDrivingRouteSearch *driving;
@property (nonatomic, copy) BaiduMapDataCompletion completion;
- (void)finishWithObject:(nullable id)object error:(nullable NSError *)error;
@end

@implementation BaiduMapOperation

- (void)finishWithObject:(id)object error:(NSError *)error {
    if (!_completion) { return; }
    BaiduMapDataCompletion completion = _completion;
    _completion = nil;
    _suggestion.delegate = nil;
    _driving.delegate = nil;
    _suggestion = nil;
    _driving = nil;
    NSData *data = nil;
    if (!error && object) {
        data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    }
    [self.owner finishOperation:self];
    completion(data, error);
}

- (void)onGetSuggestionResult:(BMKSuggestionSearch *)searcher
                       result:(BMKSuggestionSearchResult *)result
                    errorCode:(BMKSearchErrorCode)errorCode {
    if (errorCode != BMK_SEARCH_NO_ERROR && errorCode != BMK_SEARCH_RESULT_NOT_FOUND) {
        NSString *message = [NSString stringWithFormat:@"百度地点检索错误 %ld，请检查网络和已启用的服务",
                             (long)errorCode];
        [self finishWithObject:nil error:BaiduError(message, errorCode)];
        return;
    }
    NSMutableArray *places = [NSMutableArray array];
    for (BMKSuggestionInfo *item in result.suggestionList ?: @[]) {
        CLLocationCoordinate2D coordinate = item.location;
        // Some suggestions are keywords without a usable POI position.
        if (!CLLocationCoordinate2DIsValid(coordinate) ||
            (coordinate.latitude == 0 && coordinate.longitude == 0) ||
            item.key.length == 0) { continue; }
        [places addObject:@{
            @"id": item.uid.length ? item.uid : [NSString stringWithFormat:@"%.7f,%.7f", coordinate.longitude, coordinate.latitude],
            @"name": item.key,
            @"address": item.address ?: @"",
            @"city": item.city ?: @"",
            @"district": item.district ?: @"",
            @"location": BaiduPoint(coordinate)
        }];
    }
    [self finishWithObject:places error:nil];
}

- (void)onGetDrivingRouteResult:(BMKDrivingRouteSearch *)searcher
                         result:(BMKDrivingRouteSearchResult *)result
                      errorCode:(BMKSearchErrorCode)errorCode {
    if (errorCode != BMK_SEARCH_NO_ERROR) {
        NSString *message = [NSString stringWithFormat:@"百度路线规划错误 %ld，请检查网络、服务和终点",
                             (long)errorCode];
        [self finishWithObject:nil error:BaiduError(message, errorCode)];
        return;
    }
    NSMutableArray *routes = [NSMutableArray array];
    for (BMKDrivingRouteLine *line in result.routes ?: @[]) {
        NSMutableArray *points = [NSMutableArray array];
        NSMutableArray *steps = [NSMutableArray array];
        NSMutableArray *traffic = [NSMutableArray array];
        double routeOffset = 0;
        for (BMKDrivingStep *step in line.steps ?: @[]) {
            if (![step isKindOfClass:BMKDrivingStep.class]) { continue; }
            double stepStart = routeOffset;
            [steps addObject:@{
                @"offset": @(routeOffset),
                @"road": step.roadName ?: @"",
                @"instruction": step.instruction ?: @""
            }];
            for (int i = 0; step.points && i < step.pointsCount; i++) {
                CLLocationCoordinate2D coordinate = BMKCoordinateForMapPoint(step.points[i]);
                if (!CLLocationCoordinate2DIsValid(coordinate) ||
                    (coordinate.latitude == 0 && coordinate.longitude == 0)) { continue; }
                NSDictionary *point = BaiduPoint(coordinate);
                if (![point isEqual:points.lastObject]) { [points addObject:point]; }
            }
            for (BMKTrafficCondition *condition in step.trafficCondition ?: @[]) {
                double length = MAX(0, condition.distance);
                if (length > 0) {
                    [traffic addObject:@{@"start": @(routeOffset),
                                         @"end": @(routeOffset + length),
                                         @"status": @(condition.status)}];
                    routeOffset += length;
                }
            }
            // Conditions may be absent or may not cover the entire step.
            // Keep maneuver/traffic offsets on the route-distance baseline.
            routeOffset = MAX(routeOffset, stepStart + MAX(0, step.distance));
        }
        if (points.count < 2 || line.distance <= 0) { continue; }
        BMKTime *duration = line.duration;
        NSInteger seconds = MAX(1, duration.dates * 86400 + duration.hours * 3600 +
                                  duration.minutes * 60 + duration.seconds);
        [routes addObject:@{@"distance": @(line.distance),
                            @"duration": @(seconds),
                            @"points": points,
                            @"steps": steps,
                            @"traffic": traffic}];
    }
    [self finishWithObject:routes error:nil];
}

@end

@implementation BaiduMapBridge

+ (instancetype)shared {
    static BaiduMapBridge *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [BaiduMapBridge new]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) { _operations = [NSMutableSet set]; }
    return self;
}

- (BOOL)startWithAK:(NSString *)ak {
    NSAssert(NSThread.isMainThread, @"Baidu SDK must be used on the main thread");
    if (ak.length == 0) { return NO; }
    if ([_activeAK isEqualToString:ak] && _manager) { return YES; }
    if (_operations.count) { return NO; }
    [_manager stop];
    _manager = nil;
    _activeAK = nil;
    _authorizationError = 0;
    [BMKMapManager setAgreePrivacy:YES];
    if (![BMKMapManager setCoordinateTypeUsedInBaiduMapSDK:BMK_COORDTYPE_COMMON]) { return NO; }
    BMKMapManager *manager = [BMKMapManager sharedInstance];
    if (![manager start:ak generalDelegate:self]) { return NO; }
    _manager = manager;
    _activeAK = [ak copy];
    return YES;
}

- (void)onGetPermissionState:(int)error {
    _authorizationError = error;
}

- (void)finishOperation:(BaiduMapOperation *)operation {
    [_operations removeObject:operation];
}

- (void)armTimeout:(BaiduMapOperation *)operation {
    __weak BaiduMapOperation *weakOperation = operation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [weakOperation finishWithObject:nil error:BaiduError(@"百度地图请求超时，请检查网络", -2)];
    });
}

- (NSError *)readinessError {
    if (!_manager) { return BaiduError(@"请先同意隐私条款并填写百度 iOS AK", -1); }
    if (_authorizationError != 0) {
        NSString *message = [NSString stringWithFormat:@"百度鉴权错误 %ld：%@",
                             (long)_authorizationError,
                             BaiduAuthorizationDescription(_authorizationError)];
        return BaiduError(message, _authorizationError);
    }
    return nil;
}

- (void)searchPlaces:(NSString *)keyword nearLatitude:(double)latitude
         nearLongitude:(double)longitude completion:(BaiduMapDataCompletion)completion {
    NSAssert(NSThread.isMainThread, @"Baidu SDK must be used on the main thread");
    NSError *error = [self readinessError];
    if (error) { completion(nil, error); return; }
    BaiduMapOperation *operation = [BaiduMapOperation new];
    operation.owner = self;
    operation.completion = completion;
    operation.suggestion = [BMKSuggestionSearch new];
    operation.suggestion.delegate = operation;
    BMKSuggestionSearchOption *option = [BMKSuggestionSearchOption new];
    option.keyword = keyword;
    option.cityname = @"全国";
    option.cityLimit = NO;
    if (CLLocationCoordinate2DIsValid(CLLocationCoordinate2DMake(latitude, longitude))) {
        option.location = BMKCoordTrans(CLLocationCoordinate2DMake(latitude, longitude),
                                        BMK_COORDTYPE_GPS, BMK_COORDTYPE_COMMON);
    }
    [_operations addObject:operation];
    if (![operation.suggestion suggestionSearch:option]) {
        [operation finishWithObject:nil error:BaiduError(@"无法启动百度地点检索", -3)];
    } else { [self armTimeout:operation]; }
}

- (void)drivingRoutesFromLatitude:(double)originLatitude longitude:(double)originLongitude
            destinationLatitude:(double)destinationLatitude longitude:(double)destinationLongitude
                destinationUID:(NSString *)destinationUID multiple:(BOOL)multiple
                    completion:(BaiduMapDataCompletion)completion {
    NSAssert(NSThread.isMainThread, @"Baidu SDK must be used on the main thread");
    NSError *error = [self readinessError];
    if (error) { completion(nil, error); return; }
    BaiduMapOperation *operation = [BaiduMapOperation new];
    operation.owner = self;
    operation.completion = completion;
    operation.driving = [BMKDrivingRouteSearch new];
    operation.driving.delegate = operation;
    BMKDrivingRouteSearchOption *option = [BMKDrivingRouteSearchOption new];
    BMKPlanNode *origin = [BMKPlanNode new];
    origin.pt = BMKCoordTrans(CLLocationCoordinate2DMake(originLatitude, originLongitude),
                              BMK_COORDTYPE_GPS, BMK_COORDTYPE_COMMON);
    BMKPlanNode *destination = [BMKPlanNode new];
    destination.pt = BMKCoordTrans(CLLocationCoordinate2DMake(destinationLatitude, destinationLongitude),
                                   BMK_COORDTYPE_GPS, BMK_COORDTYPE_COMMON);
    destination.uid = destinationUID ?: @"";
    option.origin = origin;
    option.destination = destination;
    option.tactics = BMK_DRIVING_ROUTE_SEARCH_TACTICS_NO_HIGHWAY;
    option.alternatives = multiple ? BMK_DRIVING_ROUTE_SEARCH_ALTERNATIVES_MULTIPLE
                                   : BMK_DRIVING_ROUTE_SEARCH_ALTERNATIVES_SINGLE;
    option.stepsInfo = 1;
    [_operations addObject:operation];
    if (![operation.driving drivingRouteSearch:option]) {
        [operation finishWithObject:nil error:BaiduError(@"无法启动百度驾车路线规划", -4)];
    } else { [self armTimeout:operation]; }
}

@end
