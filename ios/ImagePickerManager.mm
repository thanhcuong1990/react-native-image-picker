#import "ImagePickerManager.h"
#import "ImagePickerUtils.h"
#import <React/RCTConvert.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <MobileCoreServices/MobileCoreServices.h>

@interface ImagePickerManager ()

@property (nonatomic, strong) RCTResponseSenderBlock callback;
@property (nonatomic, copy) NSDictionary *options;
@property (nonatomic, assign) BOOL isCancelled;
@property (nonatomic, assign) BOOL callbackInvoked;

@end

@interface ImagePickerManager (UIImagePickerControllerDelegate) <UINavigationControllerDelegate, UIImagePickerControllerDelegate>
@end

@interface ImagePickerManager (UIAdaptivePresentationControllerDelegate) <UIAdaptivePresentationControllerDelegate>
@end

API_AVAILABLE(ios(14))
@interface ImagePickerManager (PHPickerViewControllerDelegate) <PHPickerViewControllerDelegate>
@end

@implementation ImagePickerManager

NSString *errCameraUnavailable = @"camera_unavailable";
NSString *errPermission = @"permission";
NSString *errOthers = @"others";
RNImagePickerTarget target;

BOOL photoSelected = NO;

RCT_EXPORT_MODULE(ImagePicker)

RCT_EXPORT_METHOD(launchCamera:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback)
{
    target = camera;
    photoSelected = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self launchImagePicker:options callback:callback];
    });
}

RCT_EXPORT_METHOD(launchImageLibrary:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback)
{
    target = library;
    photoSelected = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self launchImagePicker:options callback:callback];
    });
}

// We won't compile this code when we build for the old architecture.
#ifdef RCT_NEW_ARCH_ENABLED

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeImagePickerSpecJSI>(params);
}
#endif

- (void)launchImagePicker:(NSDictionary *)options callback:(RCTResponseSenderBlock)callback
{
    self.callback = callback;
    self.isCancelled = NO;
    self.callbackInvoked = NO;

    if (target == camera && [ImagePickerUtils isSimulator]) {
        [self safeInvokeCallback:@[@{@"errorCode": errCameraUnavailable}]];
        return;
    }

    self.options = options;

    if (@available(iOS 14, *)) {
        if (target == library) {
            PHPickerConfiguration *configuration = [ImagePickerUtils makeConfigurationFromOptions:options target:target];
            PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
            picker.delegate = self;
            picker.modalPresentationStyle = [RCTConvert UIModalPresentationStyle:options[@"presentationStyle"]];
            picker.presentationController.delegate = self;

            if([self.options[@"includeExtra"] boolValue]) {
                [self checkPhotosPermissions:^(BOOL granted) {
                    if (!granted) {
                        [self safeInvokeCallback:@[@{@"errorCode": errPermission}]];
                        return;
                    }
                    [self showPickerViewController:picker];
                }];
            } else {
                [self showPickerViewController:picker];
            }

            return;
        }
    }

    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    [ImagePickerUtils setupPickerFromOptions:picker options:self.options target:target];
    picker.delegate = self;
    picker.presentationController.delegate = self;
    
    if([self.options[@"includeExtra"] boolValue]) {
        [self checkPhotosPermissions:^(BOOL granted) {
            if (!granted) {
                [self safeInvokeCallback:@[@{@"errorCode": errPermission}]];
                return;
            }
            [self showPickerViewController:picker];
        }];
    } else {
      [self showPickerViewController:picker];
    }
}

- (void) showPickerViewController:(UIViewController *)picker
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *root = RCTPresentedViewController();
        [root presentViewController:picker animated:YES completion:nil];
    });
}

#pragma mark - Helpers

NSData* extractImageData(UIImage* image){
    CFMutableDataRef imageData = CFDataCreateMutable(NULL, 0);
    CGImageDestinationRef destination = CGImageDestinationCreateWithData(imageData, kUTTypeJPEG, 1, NULL);

    CFStringRef orientationKey[1];
    CFTypeRef   orientationValue[1];
    CGImagePropertyOrientation CGOrientation = CGImagePropertyOrientationForUIImageOrientation(image.imageOrientation);

    orientationKey[0] = kCGImagePropertyOrientation;
    orientationValue[0] = CFNumberCreate(NULL, kCFNumberIntType, &CGOrientation);

    CFDictionaryRef imageProps = CFDictionaryCreate( NULL, (const void **)orientationKey, (const void **)orientationValue, 1,
                    &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    CGImageDestinationAddImage(destination, image.CGImage, imageProps);

    CGImageDestinationFinalize(destination);

    CFRelease(destination);
    CFRelease(orientationValue[0]);
    CFRelease(imageProps);
    return (__bridge NSData *)imageData;
}



-(NSMutableDictionary *)mapImageToAsset:(UIImage *)image data:(NSData *)data phAsset:(PHAsset * _Nullable)phAsset {
    NSString *fileType = [ImagePickerUtils getFileType:data];
    if (target == camera) {
        if ([self.options[@"saveToPhotos"] boolValue]) {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
        }
        data = extractImageData(image);
    }

    UIImage* newImage = image;
    if (![fileType isEqualToString:@"gif"]) {
        newImage = [ImagePickerUtils resizeImage:image
                                     maxWidth:[self.options[@"maxWidth"] floatValue]
                                    maxHeight:[self.options[@"maxHeight"] floatValue]];
    }

    float quality = [self.options[@"quality"] floatValue];
    if (![image isEqual:newImage] || (quality >= 0 && quality < 1)) {
        if ([fileType isEqualToString:@"jpg"]) {
            data = UIImageJPEGRepresentation(newImage, quality);
        } else if ([fileType isEqualToString:@"png"]) {
            data = UIImagePNGRepresentation(newImage);
        }
    }

    NSMutableDictionary *asset = [[NSMutableDictionary alloc] init];
    asset[@"type"] = [@"image/" stringByAppendingString:fileType];

    NSString *fileName = [self getImageFileName:fileType];
    NSString *path = [[NSTemporaryDirectory() stringByStandardizingPath] stringByAppendingPathComponent:fileName];
    [data writeToFile:path atomically:YES];

    if ([self.options[@"includeBase64"] boolValue]) {
        asset[@"base64"] = [data base64EncodedStringWithOptions:0];
    }

    NSURL *fileURL = [NSURL fileURLWithPath:path];
    asset[@"uri"] = [fileURL absoluteString];

    NSNumber *fileSizeValue = nil;
    NSError *fileSizeError = nil;
    [fileURL getResourceValue:&fileSizeValue forKey:NSURLFileSizeKey error:&fileSizeError];
    if (fileSizeValue){
        asset[@"fileSize"] = fileSizeValue;
    }

    asset[@"fileName"] = fileName;
    asset[@"width"] = @(newImage.size.width);
    asset[@"height"] = @(newImage.size.height);

    if(phAsset){
        asset[@"timestamp"] = [self getDateTimeInUTC:phAsset.creationDate];
        asset[@"id"] = phAsset.localIdentifier;
    }

    return asset;
}

CGImagePropertyOrientation CGImagePropertyOrientationForUIImageOrientation(UIImageOrientation uiOrientation) {
    switch (uiOrientation) {
        case UIImageOrientationUp: return kCGImagePropertyOrientationUp;
        case UIImageOrientationDown: return kCGImagePropertyOrientationDown;
        case UIImageOrientationLeft: return kCGImagePropertyOrientationLeft;
        case UIImageOrientationRight: return kCGImagePropertyOrientationRight;
        case UIImageOrientationUpMirrored: return kCGImagePropertyOrientationUpMirrored;
        case UIImageOrientationDownMirrored: return kCGImagePropertyOrientationDownMirrored;
        case UIImageOrientationLeftMirrored: return kCGImagePropertyOrientationLeftMirrored;
        case UIImageOrientationRightMirrored: return kCGImagePropertyOrientationRightMirrored;
    }
}

-(NSMutableDictionary *)mapVideoToAsset:(NSURL *)url phAsset:(PHAsset * _Nullable)phAsset error:(NSError **)error {
    NSString *fileName = [url lastPathComponent];
    NSString *path = [[NSTemporaryDirectory() stringByStandardizingPath] stringByAppendingPathComponent:fileName];
    NSURL *videoDestinationURL = [NSURL fileURLWithPath:path];
    NSString *fileExtension = [fileName pathExtension];

    if ((target == camera) && [self.options[@"saveToPhotos"] boolValue]) {
        UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil);
    }

    if (![url.URLByResolvingSymlinksInPath.path isEqualToString:videoDestinationURL.URLByResolvingSymlinksInPath.path]) {
        NSFileManager *fileManager = [NSFileManager defaultManager];

        if ([fileManager fileExistsAtPath:videoDestinationURL.path]) {
            [fileManager removeItemAtURL:videoDestinationURL error:nil];
        }

        if (url) {
          if ([fileManager isWritableFileAtPath:[url path]]) {
            [fileManager moveItemAtURL:url toURL:videoDestinationURL error:error];
          } else {
            [fileManager copyItemAtURL:url toURL:videoDestinationURL error:error];
          }

          if (error && *error) {
              return nil;
          }
        }
    }

    NSMutableDictionary *response = [[NSMutableDictionary alloc] init];

    if([self.options[@"formatAsMp4"] boolValue] && ![fileExtension isEqualToString:@"mp4"]) {
        NSURL *parentURL = [videoDestinationURL URLByDeletingLastPathComponent];
        NSString *path = [[parentURL.path stringByAppendingString:@"/"] stringByAppendingString:[[NSUUID UUID] UUIDString]];
        path = [path stringByAppendingString:@".mp4"];
        NSURL *outputURL = [NSURL fileURLWithPath:path];

        [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:videoDestinationURL options:nil];
        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetPassthrough];

        exportSession.outputURL = outputURL;
        exportSession.outputFileType = AVFileTypeMPEG4;
        exportSession.shouldOptimizeForNetworkUse = YES;

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        [exportSession exportAsynchronouslyWithCompletionHandler:^(void) {
            if (exportSession.status == AVAssetExportSessionStatusCompleted) {
                CGSize dimentions = [ImagePickerUtils getVideoDimensionsFromUrl:outputURL];
                response[@"fileName"] = [outputURL lastPathComponent];
                response[@"duration"] = [NSNumber numberWithDouble:CMTimeGetSeconds([AVAsset assetWithURL:outputURL].duration)];
                response[@"uri"] = outputURL.absoluteString;
                response[@"type"] = [ImagePickerUtils getFileTypeFromUrl:outputURL];
                response[@"fileSize"] = [ImagePickerUtils getFileSizeFromUrl:outputURL];
                response[@"width"] = @(dimentions.width);
                response[@"height"] = @(dimentions.height);

                dispatch_semaphore_signal(sem);
            } else if (exportSession.status == AVAssetExportSessionStatusFailed || exportSession.status == AVAssetExportSessionStatusCancelled) {
                dispatch_semaphore_signal(sem);
            }
        }];


        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    } else {
        CGSize dimentions = [ImagePickerUtils getVideoDimensionsFromUrl:videoDestinationURL];
        response[@"fileName"] = fileName;
        response[@"duration"] = [NSNumber numberWithDouble:CMTimeGetSeconds([AVAsset assetWithURL:videoDestinationURL].duration)];
        response[@"uri"] = videoDestinationURL.absoluteString;
        response[@"type"] = [ImagePickerUtils getFileTypeFromUrl:videoDestinationURL];
        response[@"fileSize"] = [ImagePickerUtils getFileSizeFromUrl:videoDestinationURL];
        response[@"width"] = @(dimentions.width);
        response[@"height"] = @(dimentions.height);

        if(phAsset){
            response[@"timestamp"] = [self getDateTimeInUTC:phAsset.creationDate];
            response[@"id"] = phAsset.localIdentifier;
        }
    }

    return response;
}

- (NSString *) getDateTimeInUTC:(NSDate *)date {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZ"];
    return [formatter stringFromDate:date];
}

- (void)checkCameraPermissions:(void(^)(BOOL granted))callback
{
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusAuthorized) {
        callback(YES);
        return;
    }
    else if (status == AVAuthorizationStatusNotDetermined){
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            callback(granted);
            return;
        }];
    }
    else {
        callback(NO);
    }
}

- (void)checkPhotosPermissions:(void(^)(BOOL granted))callback
{
    if (@available(iOS 14, *)) {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
        if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
            callback(YES);
            return;
        } else if (status == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {
                if (status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited) {
                    callback(YES);
                    return;
                }
                else {
                    callback(NO);
                    return;
                }
            }];
        }
        else {
            callback(NO);
        }
    } else {
        // iOS 13 and below - use older API
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
        if (status == PHAuthorizationStatusAuthorized) {
            callback(YES);
            return;
        } else if (status == PHAuthorizationStatusNotDetermined) {
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                if (status == PHAuthorizationStatusAuthorized) {
                    callback(YES);
                    return;
                }
                else {
                    callback(NO);
                    return;
                }
            }];
        }
        else {
            callback(NO);
        }
    }
}

// Both camera and photo write permission is required to take picture/video and store it to public photos
- (void)checkCameraAndPhotoPermission:(void(^)(BOOL granted))callback
{
    [self checkCameraPermissions:^(BOOL cameraGranted) {
        if (!cameraGranted) {
            callback(NO);
            return;
        }

        [self checkPhotosPermissions:^(BOOL photoGranted) {
            if (!photoGranted) {
                callback(NO);
                return;
            }
            callback(YES);
        }];
    }];
}

- (void)checkPermission:(void(^)(BOOL granted)) callback
{
    void (^permissionBlock)(BOOL) = ^(BOOL permissionGranted) {
        if (!permissionGranted) {
            callback(NO);
            return;
        }
        callback(YES);
    };

    if (target == camera && [self.options[@"saveToPhotos"] boolValue]) {
        [self checkCameraAndPhotoPermission:permissionBlock];
    }
    else if (target == camera) {
        [self checkCameraPermissions:permissionBlock];
    }
    else {
        callback(YES);
    }
}

- (NSString *)getImageFileName:(NSString *)fileType
{
    NSString *fileName = [[NSUUID UUID] UUIDString];
    fileName = [fileName stringByAppendingString:@"."];
    return [fileName stringByAppendingString:fileType];
}

- (UIView *)createLoadingOverlayForView:(UIView *)parentView {
    UIView *overlayView = [[UIView alloc] initWithFrame:parentView.bounds];
    overlayView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];
    
    UIView *containerView = [[UIView alloc] init];
    containerView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.9];
    containerView.layer.cornerRadius = 12;
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    
    UIActivityIndicatorView *loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    loadingIndicator.color = [UIColor whiteColor];
    loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [loadingIndicator startAnimating];
    
    UILabel *downloadingLabel = [[UILabel alloc] init];
    downloadingLabel.text = @"Downloading";
    downloadingLabel.textColor = [UIColor whiteColor];
    downloadingLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    downloadingLabel.textAlignment = NSTextAlignmentCenter;
    downloadingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    [cancelButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    cancelButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    cancelButton.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.8];
    cancelButton.layer.cornerRadius = 8;
    cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [cancelButton addTarget:self action:@selector(cancelProcessing) forControlEvents:UIControlEventTouchUpInside];
    
    [containerView addSubview:loadingIndicator];
    [containerView addSubview:downloadingLabel];
    [containerView addSubview:cancelButton];
    [overlayView addSubview:containerView];
    
    [NSLayoutConstraint activateConstraints:@[
        [containerView.centerXAnchor constraintEqualToAnchor:overlayView.centerXAnchor],
        [containerView.centerYAnchor constraintEqualToAnchor:overlayView.centerYAnchor],
        [containerView.widthAnchor constraintEqualToConstant:200],
        [containerView.heightAnchor constraintEqualToConstant:150],
        
        [loadingIndicator.centerXAnchor constraintEqualToAnchor:containerView.centerXAnchor],
        [loadingIndicator.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:20],
        
        [downloadingLabel.centerXAnchor constraintEqualToAnchor:containerView.centerXAnchor],
        [downloadingLabel.topAnchor constraintEqualToAnchor:loadingIndicator.bottomAnchor constant:12],
        [downloadingLabel.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:16],
        [downloadingLabel.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-16],
        
        [cancelButton.centerXAnchor constraintEqualToAnchor:containerView.centerXAnchor],
        [cancelButton.topAnchor constraintEqualToAnchor:downloadingLabel.bottomAnchor constant:16],
        [cancelButton.widthAnchor constraintEqualToConstant:80],
        [cancelButton.heightAnchor constraintEqualToConstant:36]
    ]];
    
    return overlayView;
}

- (void)cancelProcessing {
    self.isCancelled = YES;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presentedViewController = RCTPresentedViewController();
        if (presentedViewController) {
            [presentedViewController dismissViewControllerAnimated:YES completion:^{
                [self safeInvokeCallback:@[@{@"didCancel": @YES}]];
            }];
        } else {
            [self safeInvokeCallback:@[@{@"didCancel": @YES}]];
        }
    });
}

- (void)safeInvokeCallback:(NSArray *)response {
    if (!self.callbackInvoked && self.callback) {
        self.callbackInvoked = YES;
        self.callback(response);
    }
}

+ (UIImage *)getUIImageFromInfo:(NSDictionary *)info
{
    UIImage *image = info[UIImagePickerControllerEditedImage];
    if (!image) {
        image = info[UIImagePickerControllerOriginalImage];
    }
    return image;
}

+ (NSURL *)getNSURLFromInfo:(NSDictionary *)info {
    return info[UIImagePickerControllerImageURL];
}

@end

@implementation ImagePickerManager (UIImagePickerControllerDelegate)

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info
{   
    __block UIView *overlayView;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        overlayView = [self createLoadingOverlayForView:picker.view];
        [picker.view addSubview:overlayView];
    });
    
    if (photoSelected == YES) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [picker dismissViewControllerAnimated:YES completion:nil];
        });
        return;
    }
    photoSelected = YES;
    self.isCancelled = NO;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [picker dismissViewControllerAnimated:YES completion:^{
            dispatch_queue_t processingQueue = dispatch_queue_create("com.imagepicker.processing", DISPATCH_QUEUE_CONCURRENT);
            dispatch_group_t processingGroup = dispatch_group_create();
            
            dispatch_group_enter(processingGroup);
            dispatch_async(processingQueue, ^{
                if (self.isCancelled) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self safeInvokeCallback:@[@{@"didCancel": @YES}]];
                    });
                    dispatch_group_leave(processingGroup);
                    return;
                }
                
                NSMutableArray<NSDictionary *> *assets = [[NSMutableArray alloc] initWithCapacity:1];
                PHAsset *asset = nil;

                if([self.options[@"includeExtra"] boolValue]) {
                    asset = [ImagePickerUtils fetchAssetFromImageInfo:info];
                }

                if ([info[UIImagePickerControllerMediaType] isEqualToString:(NSString *) kUTTypeImage]) {
                    if (self.isCancelled) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self safeInvokeCallback:@[@{@"didCancel": @YES}]];
                        });
                        dispatch_group_leave(processingGroup);
                        return;
                    }
                    
                    UIImage *image = [ImagePickerManager getUIImageFromInfo:info];
                    NSData *imageData = nil;
                    NSURL *imageURL = [ImagePickerManager getNSURLFromInfo:info];
                    if (imageURL) {
                        imageData = [NSData dataWithContentsOfURL:imageURL];
                    }
                    if (!imageData) {
                        imageData = UIImageJPEGRepresentation(image, 1.0);
                    }

                    [assets addObject:[self mapImageToAsset:image data:imageData phAsset:asset]];
                } else {
                    if (self.isCancelled) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self safeInvokeCallback:@[@{@"didCancel": @YES}]];
                        });
                        dispatch_group_leave(processingGroup);
                        return;
                    }
                    
                    NSError *error;
                    NSDictionary *videoAsset = [self mapVideoToAsset:info[UIImagePickerControllerMediaURL] phAsset:asset error:&error];

                    if (videoAsset == nil) {
                        NSString *errorMessage = error.localizedFailureReason;
                        if (errorMessage == nil) errorMessage = @"Video asset not found";
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self safeInvokeCallback:@[@{@"errorCode": errOthers, @"errorMessage": errorMessage}]];
                        });
                        dispatch_group_leave(processingGroup);
                        return;
                    }
                    [assets addObject:videoAsset];
                }

                if (self.isCancelled) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self safeInvokeCallback:@[@{@"didCancel": @YES}]];
                    });
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
                        response[@"assets"] = assets;
                        [self safeInvokeCallback:@[response]];
                    });
                }
                
                dispatch_group_leave(processingGroup);
            });
        }];
    });
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [picker dismissViewControllerAnimated:YES completion:^{
            [self safeInvokeCallback:@[@{@"didCancel": @YES}]];
        }];
    });
}

@end

@implementation ImagePickerManager (presentationControllerDidDismiss)

- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController
{
    [self safeInvokeCallback:@[@{@"didCancel": @YES}]];
}

@end

API_AVAILABLE(ios(14))
@implementation ImagePickerManager (PHPickerViewControllerDelegate)

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results API_AVAILABLE(ios(14))
{   
    if (results.count == 0) {
        [picker dismissViewControllerAnimated:YES completion:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self safeInvokeCallback:@[@{@"didCancel": @YES}]];
        });
        return;
    }
    
    __block UIView *overlayView;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        overlayView = [self createLoadingOverlayForView:picker.view];
        [picker.view addSubview:overlayView];
    });

    if (photoSelected == YES) {
        [picker dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    photoSelected = YES;
    self.isCancelled = NO;

    dispatch_group_t completionGroup = dispatch_group_create();
    dispatch_queue_t processingQueue = dispatch_queue_create("com.imagepicker.processing", DISPATCH_QUEUE_CONCURRENT);
    
    NSMutableArray<NSDictionary *> *assets = [[NSMutableArray alloc] initWithCapacity:results.count];
    for (int i = 0; i < results.count; i++) {
        [assets addObject:(NSDictionary *)[NSNull null]];
    }

    [results enumerateObjectsUsingBlock:^(PHPickerResult *result, NSUInteger index, BOOL *stop) {
        if (self.isCancelled) {
            *stop = YES;
            return;
        }
        
        dispatch_group_enter(completionGroup);
        dispatch_async(processingQueue, ^{
            if (self.isCancelled) {
                dispatch_group_leave(completionGroup);
                return;
            }
            
            PHAsset *asset = nil;
            NSItemProvider *provider = result.itemProvider;

            if([self.options[@"includeExtra"] boolValue] && result.assetIdentifier != nil) {
                PHFetchResult* fetchResult = [PHAsset fetchAssetsWithLocalIdentifiers:@[result.assetIdentifier] options:nil];
                asset = fetchResult.firstObject;
            }

            if ([provider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeImage]) {
                NSString *identifier = provider.registeredTypeIdentifiers.firstObject;
                if ([identifier containsString:@"live-photo-bundle"]) {
                    identifier = @"public.jpeg";
                }

                dispatch_group_t innerGroup = dispatch_group_create();
                dispatch_group_enter(innerGroup);
                
                [provider loadFileRepresentationForTypeIdentifier:identifier completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
                    if (self.isCancelled) {
                        dispatch_group_leave(innerGroup);
                        return;
                    }
                    
                    NSData *imageData = nil;
                    if (url) {
                        imageData = [[NSData alloc] initWithContentsOfURL:url];
                    }
                    
                    if (imageData && !self.isCancelled) {
                        UIImage *image = [[UIImage alloc] initWithData:imageData];
                        assets[index] = [self mapImageToAsset:image data:imageData phAsset:asset];
                    } else {
                        assets[index] = (NSDictionary *)[NSNull null];
                    }
                    dispatch_group_leave(innerGroup);
                }];
                
                dispatch_group_wait(innerGroup, DISPATCH_TIME_FOREVER);
                dispatch_group_leave(completionGroup);
                
            } else if ([provider hasItemConformingToTypeIdentifier:(NSString *)kUTTypeMovie]) {
                dispatch_group_t innerGroup = dispatch_group_create();
                dispatch_group_enter(innerGroup);
                
                [provider loadFileRepresentationForTypeIdentifier:(NSString *)kUTTypeMovie completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
                    if (self.isCancelled) {
                        dispatch_group_leave(innerGroup);
                        return;
                    }
                    
                    NSDictionary *mappedAsset = [self mapVideoToAsset:url phAsset:asset error:nil];
                    if (nil != mappedAsset && !self.isCancelled) {
                        assets[index] = mappedAsset;
                    } else {
                        assets[index] = (NSDictionary *)[NSNull null];
                    }
                    dispatch_group_leave(innerGroup);
                }];
                
                dispatch_group_wait(innerGroup, DISPATCH_TIME_FOREVER);
                dispatch_group_leave(completionGroup);
                
            } else {
                assets[index] = (NSDictionary *)[NSNull null];
                dispatch_group_leave(completionGroup);
            }
        });
    }];

    dispatch_group_notify(completionGroup, dispatch_get_main_queue(), ^{
        [picker dismissViewControllerAnimated:YES completion:nil];
        
        if (self.isCancelled) {
            [self safeInvokeCallback:@[@{@"didCancel": @YES}]];
            return;
        }
        
        BOOL hasNullAssets = NO;
        for (NSDictionary *asset in assets) {
            if ([asset isEqual:[NSNull null]]) {
                hasNullAssets = YES;
                break;
            }
        }
        
        if (hasNullAssets) {
            [self safeInvokeCallback:@[@{@"errorCode": errOthers}]];
            return;
        }

        NSMutableDictionary *response = [[NSMutableDictionary alloc] init];
        [response setObject:assets forKey:@"assets"];

        [self safeInvokeCallback:@[response]];
    });
}

@end
