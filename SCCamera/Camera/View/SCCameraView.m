//
//  SCCameraView.m
//  SCCamera
//
//  Created by SeacenLiu on 2019/4/8.
//  Copyright © 2019 SeacenLiu. All rights reserved.
//

#import "SCCameraView.h"
#import "SCVideoPreviewView.h"
#import "UIView+SCCategory.h"

typedef NS_ENUM(NSInteger, SCCameraType) {
    SCCameraTypePhoto,
    SCCameraTypeMovie
};

@interface SCCameraView ()
/// 聚焦动画 view
@property (nonatomic, strong) UIView *focusView;

@property (weak, nonatomic) IBOutlet UIButton *photoBtn;
@property (weak, nonatomic) IBOutlet UIButton *typeSelBtn;
@property (nonatomic, assign) SCCameraType currentType;
@end

// TODO: - 聚焦，曝光，人脸检测动画
@implementation SCCameraView

+ (instancetype)cameraView:(CGRect)frame {
    SCCameraView *view = (SCCameraView*)[[UINib nibWithNibName:@"SCCameraView" bundle:nil] instantiateWithOwner:self options:nil][0];
    view.frame = frame;
    [view addGestureRecognizers];
    [view addSubview:view.focusView];
    return view;
}

#pragma mark - 手势添加
- (void)addGestureRecognizers {
    // 单击 -> 聚焦
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusingTapClcik:)];
    [self.previewView addGestureRecognizer:tap];
}

#pragma mark - 相机操作
- (void)focusingTapClcik:(UITapGestureRecognizer *)tap {
    if ([_delegate respondsToSelector:@selector(focusAndExposeAction:point:handle:)]) {
        CGPoint point = [tap locationInView:self.previewView];
        [_delegate focusAndExposeAction:self point:point handle:^(NSError * _Nonnull error) {
            // TODO: - handle error
        }];
    }
}

- (IBAction)flashLightClick:(UIButton*)sender {
    if ([self.delegate respondsToSelector:@selector(flashLightAction:isOn:handle:)]) {
        [sender setSelected:!sender.isSelected];
        [_delegate flashLightAction:self isOn:sender.isSelected handle:^(NSError * _Nonnull error) {
            // TODO: - handle error
        }];
    }
}

- (IBAction)torchLightClick:(UIButton*)sender {
    if ([self.delegate respondsToSelector:@selector(torchLightAction:isOn:handle:)]) {
        [sender setSelected:!sender.isSelected];
        [_delegate torchLightAction:self isOn:sender.isSelected handle:^(NSError * _Nonnull error) {
            // TODO: - handle error
        }];
    }
}

- (IBAction)switchCameraClick:(UIButton*)sender {
    if ([_delegate respondsToSelector:@selector(switchCameraAction:isFront:handle:)]) {
        [sender setSelected:!sender.isSelected];
        [_delegate switchCameraAction:self isFront:sender.isSelected handle:^(NSError * _Nonnull error) {
            // TODO: - handle error
        }];
    }
}

- (IBAction)cancelClick:(id)sender {
    if ([_delegate respondsToSelector:@selector(cancelAction:)]) {
        [_delegate cancelAction:self];
    }
}

- (IBAction)cameraTypeClick:(UIButton*)sender {
    // 如果是 photoBtn 被选中（正在录像）则不做事
    if (self.photoBtn.isSelected) {
        return;
    }
    switch (self.currentType) {
        case SCCameraTypePhoto:
            [self.photoBtn setTitle:@"开始" forState:UIControlStateNormal];
            [self.photoBtn setTitle:@"停止" forState:UIControlStateSelected];
            [self.typeSelBtn setTitle:@"录像" forState:UIControlStateNormal];
            self.currentType = SCCameraTypeMovie;
            break;
        case SCCameraTypeMovie:
            [self.photoBtn setSelected:NO];
            [self.photoBtn setTitle:@"拍照" forState:UIControlStateNormal];
            [self.photoBtn setTitle:@"拍照" forState:UIControlStateSelected];
            [self.typeSelBtn setTitle:@"拍照" forState:UIControlStateNormal];
            self.currentType = SCCameraTypePhoto;
            break;
    }
}

- (IBAction)photoClick:(UIButton*)sender {
    switch (self.currentType) {
        case SCCameraTypePhoto:
            if ([_delegate respondsToSelector:@selector(takePhotoAction:)]) {
                [_delegate takePhotoAction:self];
            }
            break;
        case SCCameraTypeMovie:
            [sender setSelected:!sender.isSelected];
            if (sender.isSelected) {
                // 开始录制
                if ([_delegate respondsToSelector:@selector(startRecordVideoAction:)]) {
                    [_delegate startRecordVideoAction:self];
                }
            } else {
                // 停止录制
                if ([_delegate respondsToSelector:@selector(stopRecordVideoAction:)]) {
                    [_delegate stopRecordVideoAction:self];
                }
            }
            break;
    }
    
}

#pragma mark - Animation
- (void)runFocusAnimation:(CGPoint)center {
    [self runFocusAnimation:self.focusView point:center];
}

/// 聚焦、曝光动画
- (void)runFocusAnimation:(UIView *)view point:(CGPoint)point {
    view.center = point;
    view.hidden = NO;
    [UIView animateWithDuration:0.15f delay:0.0f options:UIViewAnimationOptionCurveEaseInOut animations:^{
        view.layer.transform = CATransform3DMakeScale(0.5, 0.5, 1.0);
    } completion:^(BOOL complete) {
        double delayInSeconds = 0.5f;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            view.hidden = YES;
            view.transform = CGAffineTransformIdentity;
        });
    }];
}

#pragma mark - lazy
-(UIView *)focusView{
    if (_focusView == nil) {
        _focusView = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 150, 150.0f)];
        _focusView.backgroundColor = [UIColor clearColor];
        _focusView.layer.borderColor = [UIColor yellowColor].CGColor;
        _focusView.layer.borderWidth = 5.0f;
        _focusView.hidden = YES;
    }
    return _focusView;
}

@end
