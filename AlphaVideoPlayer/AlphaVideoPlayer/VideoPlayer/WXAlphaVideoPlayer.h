//
//  WXAlphaVideoPlayer.h
//  AlphaVideoPlayer
//
//  Created by M2-2023 on 2025/6/26.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, WXAlphaMaskDirection) {
    WXAlphaMaskDirectionLeftToRight,
    WXAlphaMaskDirectionRightToLeft,
    WXAlphaMaskDirectionTopToBottom,
    WXAlphaMaskDirectionBottomToTop
};


@interface WXAlphaVideoPlayer : UIView

- (void)playWithURL:(NSURL *)videoURL
   placeholderImage:(UIImage *)image;

- (void)playWithURL:(NSURL *)videoURL
   placeholderImage:(UIImage * _Nullable)image
    enableAlphaMask:(BOOL)enableAlphaMask
      maskDirection:(WXAlphaMaskDirection)maskDirection;

/// 设置视频播放路径（支持本地路径或网络 URL）
- (void)setVideoURL:(NSURL *)videoURL;

/// 设置封面图（可选）
- (void)setCoverImage:(UIImage *)image;


/// 播放
- (void)play;

/// 暂停
- (void)pause;

/// 停止播放并释放资源
- (void)stop;

/// 当前是否在播放
@property (nonatomic, assign, readonly) BOOL isPlaying;

/// 是否自动播放，默认 YES
@property (nonatomic, assign) BOOL autoPlayEnabled;

/// 是否循环播放，默认 NO
@property (nonatomic, assign) BOOL loopEnabled;

/// 播放完成回调（主线程调用）
@property (nonatomic, copy, nullable) void (^playbackCompletedHandler)(void);

/// 视频准备好播放的回调（主线程）
@property (nonatomic, copy, nullable) void (^playerReadyHandler)(void);

/// 视频下载失败回调（主线程）
@property (nonatomic, copy, nullable) void (^downloadFailHandler)(void);

@end

NS_ASSUME_NONNULL_END
