#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
// Executes the same bounded material runtime as the physical display.
@interface MotoAmbientPreview : NSObject
- (UIImage *)imageWithIntensity:(uint8_t)intensity
                           speed:(uint8_t)speed
                          travel:(uint8_t)travel
                    reduceMotion:(BOOL)reduceMotion
                           nowMs:(uint32_t)nowMs;
@end
NS_ASSUME_NONNULL_END
