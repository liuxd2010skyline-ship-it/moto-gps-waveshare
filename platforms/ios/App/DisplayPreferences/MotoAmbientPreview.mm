#import "MotoAmbientPreview.h"
#include "../../../../shared/nav_ui/include/moto_nav_design_runtime.hpp"
#include <vector>

@implementation MotoAmbientPreview {
    moto::design::Ambient _ambient;
    moto::design::MaterialScratch _scratch;
    std::vector<std::uint16_t> _nativePixels;
    std::vector<std::uint8_t> _pixels;
}
- (instancetype)init {
    self=[super init];
    if(self) {
        moto::design::initialize(_ambient,0x6D6F746F);
        _pixels.resize(466*350*4);
        _nativePixels.resize(466*350);
    }
    return self;
}
- (UIImage *)imageWithIntensity:(uint8_t)intensity speed:(uint8_t)speed
                          travel:(uint8_t)travel reduceMotion:(BOOL)reduceMotion nowMs:(uint32_t)nowMs {
    moto::design::configure(_ambient,{intensity,speed,travel,static_cast<std::uint8_t>(reduceMotion)});
    moto::design::tick(_ambient,nowMs,true);
    moto::design::render_material(_ambient,_nativePixels.data(),_scratch);
    for(int y=0;y<350;++y) for(int x=0;x<466;++x) {
        const auto color=_nativePixels[y*466+x];
        const auto offset=(y*466+x)*4;
        _pixels[offset]=((color>>11)&31)*255/31;
        _pixels[offset+1]=((color>>5)&63)*255/63;
        _pixels[offset+2]=(color&31)*255/31;
        _pixels[offset+3]=255;
    }
    // Copy into the immutable provider: a later frame cannot modify a UIImage
    // already retained by SwiftUI or a screenshot.
    CFDataRef data=CFDataCreate(kCFAllocatorDefault,_pixels.data(),_pixels.size());
    if(!data) return [[UIImage alloc] init];
    CGDataProviderRef provider=CGDataProviderCreateWithCFData(data);
    if(!provider) {CFRelease(data);return [[UIImage alloc] init];}
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    if(!space) {CGDataProviderRelease(provider);CFRelease(data);return [[UIImage alloc] init];}
    CGImageRef image=CGImageCreate(466,350,8,32,466*4,space,
        static_cast<CGBitmapInfo>(kCGBitmapByteOrder32Big|kCGImageAlphaPremultipliedLast),
        provider,nullptr,false,kCGRenderingIntentDefault);
    UIImage* result=image?[UIImage imageWithCGImage:image]:[[UIImage alloc] init];
    if(image) CGImageRelease(image);
    CGColorSpaceRelease(space);
    CGDataProviderRelease(provider);CFRelease(data);
    return result;
}
@end
