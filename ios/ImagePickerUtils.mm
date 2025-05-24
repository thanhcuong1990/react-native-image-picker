#import "ImagePickerUtils.h"
#import <CoreServices/CoreServices.h>
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>

@implementation ImagePickerUtils

+ (void) setupPickerFromOptions:(UIImagePickerController *)picker options:(NSDictionary *)options target:(RNImagePickerTarget)target
{
    if ([options[@"mediaType"] isEqualToString:@"video"] || [options[@"mediaType"] isEqualToString:@"mixed"]) {

        if ([[options objectForKey:@"videoQuality"] isEqualToString:@"high"]) {
            picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
        }
        else if ([[options objectForKey:@"videoQuality"] isEqualToString:@"low"]) {
            picker.videoQuality = UIImagePickerControllerQualityTypeLow;
        }
        else {
            picker.videoQuality = UIImagePickerControllerQualityTypeMedium;
        }
    }
    
    if (target == camera) {
        picker.sourceType = UIImagePickerControllerSourceTypeCamera;

        if ([options[@"durationLimit"] doubleValue] > 0) {
            picker.videoMaximumDuration = [options[@"durationLimit"] doubleValue];
        }

        if ([options[@"cameraType"] isEqualToString:@"front"]) {
            picker.cameraDevice = UIImagePickerControllerCameraDeviceFront;
        } else {
            picker.cameraDevice = UIImagePickerControllerCameraDeviceRear;
        }
    } else {
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    }

    if ([options[@"mediaType"] isEqualToString:@"video"]) {
        picker.mediaTypes = @[(NSString *)kUTTypeMovie];
    } else if ([options[@"mediaType"] isEqualToString:@"photo"]) {
        picker.mediaTypes = @[(NSString *)kUTTypeImage];
    } else if ([options[@"mediaType"] isEqualToString:@"mixed"]) {
        picker.mediaTypes = @[(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie];
    }

    picker.modalPresentationStyle = [RCTConvert UIModalPresentationStyle:options[@"presentationStyle"]];
}

+ (PHPickerConfiguration *)makeConfigurationFromOptions:(NSDictionary *)options target:(RNImagePickerTarget)target API_AVAILABLE(ios(14))
{
    PHPickerConfiguration *configuration;
    
    if(options[@"includeExtra"]) {
        PHPhotoLibrary *photoLibrary = [PHPhotoLibrary sharedPhotoLibrary];
        configuration = [[PHPickerConfiguration alloc] initWithPhotoLibrary:photoLibrary];
    } else {
        configuration = [[PHPickerConfiguration alloc] init];
    }

    if ([[options objectForKey:@"assetRepresentationMode"] isEqualToString:@"current"]) {
        configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    }
    else if ([[options objectForKey:@"assetRepresentationMode"] isEqualToString:@"compatible"]) {
        configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCompatible;
    }
    else {
       configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeAutomatic;
    }
    
    configuration.selectionLimit = [options[@"selectionLimit"] integerValue];

    if ([options[@"mediaType"] isEqualToString:@"video"]) {
        configuration.filter = [PHPickerFilter videosFilter];
    } else if ([options[@"mediaType"] isEqualToString:@"photo"]) {
        configuration.filter = [PHPickerFilter imagesFilter];
    } else if ((target == library) && ([options[@"mediaType"] isEqualToString:@"mixed"])) {
        configuration.filter = [PHPickerFilter anyFilterMatchingSubfilters: @[PHPickerFilter.imagesFilter, PHPickerFilter.videosFilter]];
    }
    return configuration;
}


+ (BOOL) isSimulator
{
    #if TARGET_OS_SIMULATOR
        return YES;
    #endif
    return NO;
}

+ (NSString*) getFileType:(NSData *)imageData
{
    const uint8_t firstByteJpg = 0xFF;
    const uint8_t firstBytePng = 0x89;
    const uint8_t firstByteGif = 0x47;
    
    uint8_t firstByte;
    [imageData getBytes:&firstByte length:1];
    switch (firstByte) {
      case firstByteJpg:
        return @"jpg";
      case firstBytePng:
        return @"png";
      case firstByteGif:
        return @"gif";
      default:
        return @"jpg";
    }
}

+ (NSString *) getFileTypeFromUrl:(NSURL *)url {
    CFStringRef fileExtension = (__bridge CFStringRef)[url pathExtension];
    CFStringRef UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension, NULL);
    CFStringRef MIMEType = UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType);
    CFRelease(UTI);
    return (__bridge_transfer NSString *)MIMEType;
}

+ (NSNumber *) getFileSizeFromUrl:(NSURL *)url {
    NSError *attributesError;
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[url path] error:&attributesError];
    NSNumber *fileSizeNumber = [fileAttributes objectForKey:NSFileSize];
    long fileSize = [fileSizeNumber longLongValue];

    if (attributesError) {
        return nil;
    }

    return [NSNumber numberWithLong:fileSize];
}

+ (CGSize)getVideoDimensionsFromUrl:(NSURL *)url {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    
    if ([tracks count] > 0) {
        AVAssetTrack *track = [tracks objectAtIndex:0];
        return track.naturalSize;
    }
    
    return CGSizeMake(0, 0);
}

+ (UIImage*)resizeImage:(UIImage*)image maxWidth:(float)maxWidth maxHeight:(float)maxHeight
{
    if ((maxWidth == 0) || (maxHeight == 0)) {
        return image;
    }
    
    if (image.size.width <= maxWidth && image.size.height <= maxHeight) {
        return image;
    }

    CGSize newSize = CGSizeMake(image.size.width, image.size.height);
    if (maxWidth < newSize.width) {
        newSize = CGSizeMake(maxWidth, (maxWidth / newSize.width) * newSize.height);
    }
    if (maxHeight < newSize.height) {
        newSize = CGSizeMake((maxHeight / newSize.height) * newSize.width, maxHeight);
    }
    
    newSize.width = (int)newSize.width;
    newSize.height = (int)newSize.height;

    UIGraphicsBeginImageContext(newSize);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    if (newImage == nil) {
        NSLog(@"could not scale image");
    }
    UIGraphicsEndImageContext();

    return newImage;
}

+ (void)ensureAssetDownloaded:(PHAsset *)asset {
    if (!asset) {
        return;
    }

    // Use our synchronous method to force download
    [self getImageDataHandlingICloud:nil phAsset:asset];
}

+ (PHAsset *)fetchAssetFromImageInfo:(NSDictionary<NSString *,id> *)info
{
    NSURL *assetURL = info[UIImagePickerControllerImageURL];
    if (!assetURL) {
        return nil;
    }
    
    NSString *localID = [self getLocalIdentifierFromImageURL:assetURL];
    if (localID) {
        PHFetchResult* fetchResult = [PHAsset fetchAssetsWithLocalIdentifiers:@[localID] options:nil];
        PHAsset *asset = fetchResult.firstObject;
        
        if (asset) {
            // Ensure the asset is downloaded if it's an iCloud asset
            [self ensureAssetDownloaded:asset];
        }
        
        return asset;
    }
    return nil;
}

+ (NSString *)getLocalIdentifierFromImageURL:(NSURL *)url
{
    if (!url) {
        return nil;
    }
    
    PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
    fetchOptions.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", PHAssetMediaTypeImage];
    
    __block NSString *localIdentifier = nil;
    __block PHAsset *foundAsset = nil;
    
    NSString *fileName = url.lastPathComponent;
    PHFetchResult *result = [PHAsset fetchAssetsWithOptions:fetchOptions];
    
    [result enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
        PHAssetResource *resource = [[PHAssetResource assetResourcesForAsset:asset] firstObject];
        if ([resource.originalFilename isEqualToString:fileName]) {
            localIdentifier = asset.localIdentifier;
            foundAsset = asset;
            *stop = YES;
        }
    }];
    
    // If we found an asset, ensure it's downloaded
    if (foundAsset) {
        [self ensureAssetDownloaded:foundAsset];
    }

    return localIdentifier;
}

+ (UIImageOrientation)UIImageOrientationFromCGImagePropertyOrientation:(CGImagePropertyOrientation)cgOrientation {
    switch (cgOrientation) {
        case kCGImagePropertyOrientationUp:
            return UIImageOrientationUp;
        case kCGImagePropertyOrientationDown:
            return UIImageOrientationDown;
        case kCGImagePropertyOrientationLeft:
            return UIImageOrientationLeft;
        case kCGImagePropertyOrientationRight:
            return UIImageOrientationRight;
        case kCGImagePropertyOrientationUpMirrored:
            return UIImageOrientationUpMirrored;
        case kCGImagePropertyOrientationDownMirrored:
            return UIImageOrientationDownMirrored;
        case kCGImagePropertyOrientationLeftMirrored:
            return UIImageOrientationLeftMirrored;
        case kCGImagePropertyOrientationRightMirrored:
            return UIImageOrientationRightMirrored;
        default:
            return UIImageOrientationUp;
    }
}

+ (NSData *)getImageDataHandlingICloud:(NSURL *)url phAsset:(PHAsset *)asset
{
    if (!asset && !url) {
        return nil;
    }
    
    // If we have a URL but no asset, try to get data directly
    if (!asset && url) {
        return [NSData dataWithContentsOfURL:url];
    }
    
    // Create a standard options structure to identify iCloud assets
    PHImageRequestOptions *checkOptions = [PHImageRequestOptions new];
    checkOptions.synchronous = YES;
    checkOptions.networkAccessAllowed = NO; // Don't download yet
    
    __block BOOL isCloudAsset = NO;
    
    [[PHImageManager defaultManager] requestImageDataAndOrientationForAsset:asset
                                                  options:checkOptions
                                            resultHandler:^(NSData * _Nullable data, NSString * _Nullable dataUTI, CGImagePropertyOrientation orientation, NSDictionary * _Nullable info) {
                                                if (info[PHImageResultIsInCloudKey] && [info[PHImageResultIsInCloudKey] boolValue]) {
                                                    isCloudAsset = YES;
                                                }
                                            }];
    
    // Set up request options
    __block NSData *imageData = nil;
    PHImageRequestOptions *requestOptions = [PHImageRequestOptions new];
    requestOptions.networkAccessAllowed = YES;
    requestOptions.synchronous = YES;
    requestOptions.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    requestOptions.progressHandler = ^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {};
    
    // Get full-resolution image data
    [[PHImageManager defaultManager] requestImageDataAndOrientationForAsset:asset 
                                                 options:requestOptions 
                                           resultHandler:^(NSData * _Nullable data, NSString * _Nullable dataUTI, CGImagePropertyOrientation orientation, NSDictionary * _Nullable info) {
                                                imageData = data;
                                           }];
    
    return imageData;
}

@end
