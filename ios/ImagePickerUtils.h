#import "ImagePickerManager.h"
#import <Photos/Photos.h>

@class PHPickerConfiguration;

@interface ImagePickerUtils : NSObject

+ (BOOL)isSimulator;

+ (void)setupPickerFromOptions:(UIImagePickerController *)picker options:(NSDictionary *)options target:(RNImagePickerTarget)target;

+ (PHPickerConfiguration *)makeConfigurationFromOptions:(NSDictionary *)options target:(RNImagePickerTarget)target API_AVAILABLE(ios(14));

+ (NSString*)getFileType:(NSData*)imageData;

+ (UIImage*)resizeImage:(UIImage*)image maxWidth:(float)maxWidth maxHeight:(float)maxHeight;

+ (CGSize)getVideoDimensionsFromUrl:(NSURL *)url;

+ (NSString *)getFileTypeFromUrl:(NSURL *)url;

+ (NSNumber *)getFileSizeFromUrl:(NSURL *)url;

+ (PHAsset *)fetchAssetFromImageInfo:(NSDictionary<NSString *,id> *)info;

+ (NSString *)getLocalIdentifierFromImageURL:(NSURL *)url;

+ (NSData *)getImageDataHandlingICloud:(NSURL *)url phAsset:(PHAsset *)asset;

+ (void)getImageDataHandlingICloudAsync:(NSURL *)url 
                                phAsset:(PHAsset *)asset 
                             completion:(void (^)(NSData *imageData, NSError *error))completion;

+ (UIImageOrientation)UIImageOrientationFromCGImagePropertyOrientation:(CGImagePropertyOrientation)cgOrientation;
    
@end
