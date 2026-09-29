#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^BaiduMapDataCompletion)(NSData * _Nullable data, NSError * _Nullable error);
typedef void (^BaiduMapAuthorizationCompletion)(NSError * _Nullable error);

/// Keeps Baidu SDK types out of the navigation core and converts SDK callbacks
/// into small JSON payloads consumed by the existing Swift route models.
@interface BaiduMapBridge : NSObject

+ (instancetype)shared;

- (void)authorizeWithAK:(NSString *)ak completion:(BaiduMapAuthorizationCompletion)completion;

- (void)searchPlaces:(NSString *)keyword
          nearLatitude:(double)latitude
         nearLongitude:(double)longitude
            completion:(BaiduMapDataCompletion)completion;

- (void)drivingRoutesFromLatitude:(double)originLatitude
                     longitude:(double)originLongitude
            destinationLatitude:(double)destinationLatitude
                     longitude:(double)destinationLongitude
                destinationUID:(nullable NSString *)destinationUID
                      multiple:(BOOL)multiple
                    completion:(BaiduMapDataCompletion)completion;

- (void)ridingRoutesFromLatitude:(double)originLatitude
                      longitude:(double)originLongitude
             destinationLatitude:(double)destinationLatitude
                      longitude:(double)destinationLongitude
                   electricBike:(BOOL)electricBike
                     completion:(BaiduMapDataCompletion)completion;

@end

NS_ASSUME_NONNULL_END
