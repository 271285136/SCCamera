//
//  SCCameraController.m
//  Detector
//
//  Created by SeacenLiu on 2019/3/8.
//  Copyright © 2019 SeacenLiu. All rights reserved.
//

#import "SCCameraController.h"
#import "SCVideoPreviewView.h"
#import "SCCameraResultController.h"
#import "SCCameraView.h"
#import "AVCaptureDevice+SCCategory.h"
#import "UIView+CCHUD.h"
#import <Photos/Photos.h>
#import "SCFocusView.h"
#import "SCFaceModel.h"
#import "SCPermissionsView.h"

#import "SCCameraManager.h"
#import "SCPhotographManager.h"
#import "SCMovieFileOutManager.h"

#import <Photos/Photos.h>

@interface SCCameraController () <SCCameraViewDelegate, AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate,SCPermissionsViewDelegate,SCMovieFileOutManagerDelegate>
@property (nonatomic) dispatch_queue_t sessionQueue;
@property (nonatomic) dispatch_queue_t metaQueue;
@property (nonatomic) dispatch_queue_t captureQueue;
// 会话
@property (nonatomic, strong) AVCaptureSession *session;
// 输入
@property (nonatomic, strong) AVCaptureDeviceInput *backCameraInput;
@property (nonatomic, strong) AVCaptureDeviceInput *frontCameraInput;
@property (nonatomic, strong) AVCaptureDeviceInput *currentCameraInput;
// Connection
@property (nonatomic, strong) AVCaptureConnection *videoConnection;
@property (nonatomic, strong) AVCaptureConnection *audioConnection;
// 输出
/// 与 AVCaptureMovieFileOutput 水火不相容
//@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, strong) AVCaptureMetadataOutput *metaOutput;
@property (nonatomic, strong) AVCaptureStillImageOutput *stillImageOutput; // iOS10 AVCapturePhotoOutput
@property (nonatomic, strong) AVCaptureMovieFileOutput *movieFileOutput;

@property (nonatomic, strong) SCCameraView *cameraView;
@property (nonatomic, strong) SCPermissionsView *permissionsView;

@property (nonatomic, strong) SCCameraManager *cameraManager;
@property (nonatomic, strong) SCPhotographManager *photographManager;
@property (nonatomic, strong) SCMovieFileOutManager *movieFileManager;

/// 有相机和麦克风的权限(必须调用getter方法)
@property (nonatomic, assign, readonly) BOOL hasAllPermissions;

// 用于人脸检测显示
/// 需要使用 NSCache
@property (nonatomic, strong) NSCache<NSNumber*, SCFaceModel*> *faceModels;
@property (nonatomic, strong) NSMutableDictionary<NSNumber*, SCFocusView*> *faceFocusViews;
@end

@implementation SCCameraController

#pragma mark - view life cycle
- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupUI];
    if (!self.hasAllPermissions) { // 没有权限
        [self setupPermissionsView];
    } else { // 有权限
        dispatch_async(self.sessionQueue, ^{
            [self configureSession:nil];
        });
    }
}

- (void)permissionsViewDidHasAllPermissions:(SCPermissionsView *)pv {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.25 animations:^{
            pv.alpha = 0;
        } completion:^(BOOL finished) {
            [self.permissionsView removeFromSuperview];
            self.permissionsView = nil;
        }];
    });
    dispatch_async(self.sessionQueue, ^{
        [self configureSession:nil];
        [self.session startRunning];
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    dispatch_async(self.sessionQueue, ^{
        if (self.hasAllPermissions && !self.session.isRunning) {
            [self.session startRunning];
        }
    });
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    dispatch_async(self.sessionQueue, ^{
        if (self.session.isRunning) {
            [self.session stopRunning];
        }
    });
}

- (void)setupPermissionsView {
    [self.cameraView addSubview:self.permissionsView];
    [self.cameraView bringSubviewToFront:self.cameraView.cancelBtn];
    [self.permissionsView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.permissionsView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTop multiplier:1.0 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.permissionsView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeLeft multiplier:1.0 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.permissionsView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.permissionsView attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeRight multiplier:1.0 constant:0]];
}

- (void)setupUI {
    [self.view addSubview:self.cameraView];
    [self.cameraView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.cameraView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTop multiplier:1.0 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.cameraView attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeLeft multiplier:1.0 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.cameraView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.cameraView attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeRight multiplier:1.0 constant:0]];
}

#pragma mark - 会话配置
/** 配置会话 */
- (void)configureSession:(NSError**)error {
    [self.session beginConfiguration];
    self.session.sessionPreset = AVCaptureSessionPresetPhoto;
    [self setupSessionInput:error];
    [self setupSessionOutput:error];
    [self.session commitConfiguration];
}

/** 配置输入 */
- (void)setupSessionInput:(NSError**)error {
    // 视频输入(默认是后置摄像头)
    if ([_session canAddInput:self.backCameraInput]) {
        [_session addInput:self.backCameraInput];
    }
    self.currentCameraInput = _backCameraInput;
    
    // AVCaptureVideoPreviewLayer.session 在添加视频输入后就应该设置
    dispatch_async(dispatch_get_main_queue(), ^{
        self.cameraView.previewView.captureSession = self.session;
    });
    
    // 音频输入
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput *audioIn = [[AVCaptureDeviceInput alloc] initWithDevice:audioDevice error:error];
    if ([_session canAddInput:audioIn]){
        [_session addInput:audioIn];
    }
}

/** 配置输出 */
- (void)setupSessionOutput:(NSError**)error {
    // 添加元素输出（识别）
    _metaOutput = [AVCaptureMetadataOutput new];
    if ([_session canAddOutput:_metaOutput]) {
        [_session addOutput:_metaOutput];
        // 需要先 addOutput 后面在 setMetadataObjectTypes
        [_metaOutput setMetadataObjectsDelegate:self queue:self.metaQueue];
        [_metaOutput setMetadataObjectTypes:@[AVMetadataObjectTypeFace]];
    }
    
    // 静态图片输出
    _stillImageOutput = [AVCaptureStillImageOutput new];
    // 设置编解码
    _stillImageOutput.outputSettings = @{AVVideoCodecKey: AVVideoCodecJPEG};
    if ([_session canAddOutput:_stillImageOutput]) {
        [_session addOutput:_stillImageOutput];
    }
    
    // 视频文件输出
    _movieFileOutput = [AVCaptureMovieFileOutput new];
    if ([_session canAddOutput:_movieFileOutput]) {
        [_session addOutput:_movieFileOutput];
    }
}

#pragma mark - 相机操作
/// 缩放
- (void)zoomAction:(SCCameraView *)cameraView factor:(CGFloat)factor handle:(void(^)(NSError *error))handle {
    dispatch_async(self.sessionQueue, ^{
        [self.cameraManager zoom:self.currentCameraInput.device factor:factor handle:handle];
    });
}

/// 聚焦&曝光操作
- (void)focusAndExposeAction:(SCCameraView *)cameraView point:(CGPoint)point handle:(void (^)(NSError * _Nonnull))handle {
    // instestPoint 只能在主线程获取
    CGPoint instestPoint = [cameraView.previewView captureDevicePointForPoint:point];
    dispatch_async(self.sessionQueue, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [cameraView runFocusAnimation:point];
        });
        [self.cameraManager focusWithMode:AVCaptureFocusModeAutoFocus
                           exposeWithMode:AVCaptureExposureModeAutoExpose
                                   device:self.currentCameraInput.device
                            atDevicePoint:instestPoint
                 monitorSubjectAreaChange:YES
                                   handle:handle];
    });
}

/// 转换镜头
- (void)switchCameraAction:(SCCameraView *)cameraView isFront:(BOOL)isFront handle:(void(^)(NSError *error))handle {
    dispatch_async(self.sessionQueue, ^{
        AVCaptureDeviceInput *old = isFront ? self.backCameraInput : self.frontCameraInput;
        AVCaptureDeviceInput *new = isFront ? self.frontCameraInput : self.backCameraInput;
        [self.cameraManager switchCamera:self.session old:old new:new handle:handle];
    });
}

/// 闪光灯
- (void)flashLightAction:(SCCameraView *)cameraView isOn:(BOOL)isOn handle:(void(^)(NSError *error))handle {
    dispatch_async(self.sessionQueue, ^{
        AVCaptureFlashMode mode = isOn?AVCaptureFlashModeOn:AVCaptureFlashModeOff;
        [self.cameraManager changeFlash:self.currentCameraInput.device mode:mode handle:handle];
    });
}

/// 补光
- (void)torchLightAction:(SCCameraView *)cameraView isOn:(BOOL)isOn handle:(void(^)(NSError *error))handle {
    dispatch_async(self.sessionQueue, ^{
        AVCaptureTorchMode mode = isOn?AVCaptureTorchModeOn:AVCaptureTorchModeOff;
        [self.cameraManager changeTorch:self.currentCameraInput.device mode:mode handle:handle];
    });
}

/// 取消
- (void)cancelAction:(SCCameraView *)cameraView {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - AVCaptureMetadataOutputObjectsDelegate
- (void)captureOutput:(AVCaptureOutput *)output didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
    for (AVMetadataObject *metadataObject in metadataObjects) {
        if ([metadataObject isKindOfClass:[AVMetadataFaceObject class]]) {
            AVMetadataFaceObject *faceObject = (AVMetadataFaceObject*)metadataObject;
            NSInteger faceId = faceObject.faceID;
            NSNumber *faceIdNum = [NSNumber numberWithInteger:faceId];
            SCFaceModel *model = [self.faceModels objectForKey:faceIdNum];
            if (model == nil) {
                model = [SCFaceModel faceModelWithFaceId:faceId];
                [self.faceModels setObject:model forKey:faceIdNum];
            } else if (model.count > 50) {
                return;
            }
            model.count += 1;
            NSInteger curCnt = model.count;
            dispatch_async(dispatch_get_main_queue(), ^{
                AVMetadataObject *face = [self.cameraView.previewView.videoPreviewLayer transformedMetadataObjectForMetadataObject:faceObject];
                SCFocusView *focusView = self.faceFocusViews[faceIdNum];
                if (focusView == nil) {
                    focusView = [SCFocusView new];
                    self.faceFocusViews[faceIdNum] = focusView;
                    [self.cameraView.previewView addSubview:focusView];
                }
                if (model.count > 50) {
                    [focusView removeFromSuperview];
                    [self.faceFocusViews removeObjectForKey:faceIdNum];
                    return;
                }
                focusView.frame = face.bounds;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (curCnt == model.count) {
                        [focusView removeFromSuperview];
                        [self.faceFocusViews removeObjectForKey:faceIdNum];
                    }
                });
            });
        }
    }
}

#pragma mark - 拍照
/// 拍照
- (void)takePhotoAction:(SCCameraView *)cameraView {
    [self.photographManager takePhoto:self.cameraView.previewView.videoPreviewLayer stillImageOutput:self.stillImageOutput handle:^(UIImage * _Nonnull originImage, UIImage * _Nonnull scaleImage, UIImage * _Nonnull cropImage) {
        NSLog(@"take photo success.");
        // 测试用保存图片
        [self saveImageToCameraRoll:cropImage];
        
        SCCameraResultController *rc = [SCCameraResultController new];
        rc.img = cropImage;
        [self presentViewController:rc animated:YES completion:nil];
    }];
}

/// 保存图片
- (void)saveImageToCameraRoll:(UIImage*)image {
    [self.photographManager saveImageToCameraRoll:image authHandle:^(BOOL success, PHAuthorizationStatus status) {
        
    } completion:^(BOOL success, NSError * _Nullable error) {
        
    }];
}

#pragma mark - 录制视频
/// 开始录像视频
- (void)startRecordVideoAction:(SCCameraView *)cameraView {
    [self.movieFileManager start:self.cameraView.previewView.videoOrientation];
}

/// 停止录像视频
- (void)stopRecordVideoAction:(SCCameraView *)cameraView {
    [self.movieFileManager stop];
}

/// movieFileOut 错误处理
- (void)movieFileOutManagerHandleError:(SCMovieFileOutManager *)manager error:(NSError *)error {
    [self.view showError:error];
}

// movieFileOut 录制完成处理
- (void)movieFileOutManagerDidFinishRecord:(SCMovieFileOutManager *)manager outputFileURL:(NSURL *)outputFileURL {
    // 保存视频
    [self.view showLoadHUD:@"保存中..."];
    [self.movieFileManager saveMovieToCameraRoll:outputFileURL authHandle:^(BOOL success, PHAuthorizationStatus status) {
        // TODO: - 权限处理问题
    } completion:^(BOOL success, NSError * _Nullable error) {
        [self.view hideHUD];
        success?:[self.view showError:error];
    }];
}

#pragma mark - 方向变化处理
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

- (void) viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    UIDeviceOrientation deviceOrientation = [UIDevice currentDevice].orientation;
    if (UIDeviceOrientationIsPortrait(deviceOrientation) || UIDeviceOrientationIsLandscape(deviceOrientation)) {
        self.cameraView.previewView.videoPreviewLayer.connection.videoOrientation = (AVCaptureVideoOrientation)deviceOrientation;
    }
}

#pragma mark - getter/setter
- (BOOL)hasAllPermissions {
    return [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusAuthorized
    && [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio] == AVAuthorizationStatusAuthorized;
}

#pragma mark - lazy
// Views
- (SCCameraView *)cameraView {
    if (_cameraView == nil) {
        _cameraView = [SCCameraView cameraView:self.view.frame];
        _cameraView.delegate = self;
    }
    return _cameraView;
}

- (SCPermissionsView *)permissionsView {
    if (_permissionsView == nil) {
        _permissionsView = [[SCPermissionsView alloc] initWithFrame:self.view.bounds];
        _permissionsView.delegate = self;
    }
    return _permissionsView;
}

// Managers
- (SCCameraManager *)cameraManager {
    if (_cameraManager == nil) {
        _cameraManager = [SCCameraManager new];
    }
    return _cameraManager;
}

- (SCPhotographManager *)photographManager {
    if (_photographManager == nil) {
        _photographManager = [SCPhotographManager new];
    }
    return _photographManager;
}

- (SCMovieFileOutManager *)movieFileManager {
    if (_movieFileManager == nil) {
        _movieFileManager = [SCMovieFileOutManager new];
        _movieFileManager.movieFileOutput = self.movieFileOutput;
        _movieFileManager.delegate = self;
    }
    return _movieFileManager;
}

// AVFoundation
- (AVCaptureSession *)session {
    if (_session == nil) {
        _session = [AVCaptureSession new];
    }
    return _session;
}

- (AVCaptureDeviceInput *)backCameraInput {
    if (_backCameraInput == nil) {
        NSError *error;
        _backCameraInput = [[AVCaptureDeviceInput alloc] initWithDevice:[self backCamera] error:&error];
        if (error) {
            NSLog(@"获取后置摄像头失败~");
        }
    }
    return _backCameraInput;
}

- (AVCaptureDeviceInput *)frontCameraInput {
    if (_frontCameraInput == nil) {
        NSError *error;
        _frontCameraInput = [[AVCaptureDeviceInput alloc] initWithDevice:[self frontCamera] error:&error];
        if (error) {
            NSLog(@"获取前置摄像头失败~");
        }
    }
    return _frontCameraInput;
}

- (AVCaptureDevice *)frontCamera {
    return [AVCaptureDevice cameraWithPosition:AVCaptureDevicePositionFront];
}

- (AVCaptureDevice *)backCamera {
    return [AVCaptureDevice cameraWithPosition:AVCaptureDevicePositionBack];
}

// 用于人脸识别
- (NSCache<NSNumber *,SCFaceModel *> *)faceModels {
    if (_faceModels == nil) {
        _faceModels = [[NSCache alloc] init];
        [_faceModels setCountLimit:20];
    }
    return _faceModels;
}

- (NSMutableDictionary<NSNumber *,SCFocusView *> *)faceFocusViews {
    if (_faceFocusViews == nil) {
        _faceFocusViews = [NSMutableDictionary dictionaryWithCapacity:2];
    }
    return _faceFocusViews;
}

// 队列懒加载
- (dispatch_queue_t)sessionQueue {
    if (_sessionQueue == NULL) {
        _sessionQueue = dispatch_queue_create("com.seacen.sessionQueue", DISPATCH_QUEUE_SERIAL);
    }
    return _sessionQueue;
}

- (dispatch_queue_t)metaQueue {
    if (_metaQueue == NULL) {
        _metaQueue = dispatch_queue_create("com.seacen.metaQueue", DISPATCH_QUEUE_SERIAL);
    }
    return _metaQueue;
}

- (dispatch_queue_t)captureQueue {
    if (_captureQueue == NULL) {
        _captureQueue = dispatch_queue_create("com.seacen.captureQueue", DISPATCH_QUEUE_SERIAL);
    }
    return _captureQueue;
}

@end

