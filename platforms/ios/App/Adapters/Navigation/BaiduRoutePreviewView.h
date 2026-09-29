#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Baidu renders real streets; the selected route is drawn with the same
/// palette and stroke proportions as the Waveshare navigation screen.
@interface BaiduRoutePreviewView : UIView

- (void)showRoutePoints:(NSArray<NSDictionary<NSString *, NSNumber *> *> *)points;

/// Optional Baidu personalization style ID. An empty value keeps the built-in
/// darkened road presentation; changing it does not require rebuilding the app.
- (void)useCustomMapStyleID:(nullable NSString *)styleID;

@end

NS_ASSUME_NONNULL_END
