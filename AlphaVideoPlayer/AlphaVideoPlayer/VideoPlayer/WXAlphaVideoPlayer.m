//
//  WXAlphaVideoPlayer.m
//  AlphaVideoPlayer
//
//  Created by M2-2023 on 2025/6/26.
//

#import "WXAlphaVideoPlayer.h"
#import <AVFoundation/AVFoundation.h>
#import "WXVideoCacheManager.h"
#import <CoreImage/CoreImage.h>

static CIColorKernel *videoKernel = nil;

@interface WXAlphaVideoPlayer ()

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *playerItem;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) UIImageView *coverImageView;
@property (nonatomic, strong) NSURL *videoURL;
@property (nonatomic, assign, readwrite) BOOL isPlaying;

@property (nonatomic, assign) BOOL enableAlphaMask;
@property (nonatomic, assign) WXAlphaMaskDirection maskDirection;

@property (nonatomic, assign) BOOL isObserving;

@end

@implementation WXAlphaVideoPlayer

#pragma mark - Init & Layout

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _autoPlayEnabled = YES;
        _loopEnabled = NO;
        _enableAlphaMask = NO;
        _maskDirection = WXAlphaMaskDirectionLeftToRight;

        _coverImageView = [[UIImageView alloc] initWithFrame:self.bounds];
        _coverImageView.clipsToBounds = YES;
        _coverImageView.contentMode = UIViewContentModeScaleAspectFill;
        [self addSubview:_coverImageView];

        self.contentMode = UIViewContentModeScaleAspectFill;

        // 监听内存警告，主动释放缓存等
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleMemoryWarning) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.coverImageView.frame = self.bounds;
    if (self.playerLayer) {
        self.playerLayer.frame = self.bounds;
        if (!self.playerLayer.superlayer) {
            [self.layer insertSublayer:self.playerLayer above:self.coverImageView.layer];
        }
    }
}

#pragma mark - Public APIs

- (void)playWithURL:(NSURL *)videoURL
   placeholderImage:(UIImage *)image {
    [self setCoverImage:image];
    [self setVideoURL:videoURL];
}

- (void)playWithURL:(NSURL *)videoURL
   placeholderImage:(UIImage *)image
    enableAlphaMask:(BOOL)enableAlphaMask
      maskDirection:(WXAlphaMaskDirection)maskDirection {
    self.enableAlphaMask = enableAlphaMask;
    self.maskDirection = maskDirection;
    [self playWithURL:videoURL placeholderImage:image];
}

- (void)setCoverImage:(UIImage *)image {
    self.coverImageView.image = image;
}

- (void)setVideoURL:(NSURL *)videoURL {
    if ([_videoURL isEqual:videoURL]) {
        return; // 相同URL，避免重复加载
    }
    _videoURL = videoURL;

    [self stop]; // 先清理旧资源

    if (videoURL.isFileURL) {
        [self setupPlayerWithURL:videoURL];
        return;
    }

    WXVideoCacheManager *cacheManager = [WXVideoCacheManager sharedManager];
    NSURL *localURL = [cacheManager cachedFileURLForRemoteURL:videoURL];

    if ([cacheManager isCacheFileExistForRemoteURL:videoURL] &&
        [self.class isPlayableVideoAtURL:localURL]) {
        [self setupPlayerWithURL:localURL];
        return;
    } else {
        if ([[NSFileManager defaultManager] fileExistsAtPath:localURL.path]) {
            [[NSFileManager defaultManager] removeItemAtURL:localURL error:nil];
        }
    }

    __weak typeof(self) weakSelf = self;
    [cacheManager downloadAndCacheVideoWithURL:videoURL completion:^(NSURL * _Nullable localURL, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (localURL && [self.class isPlayableVideoAtURL:localURL]) {
                [weakSelf setupPlayerWithURL:localURL];
            } else {
                if (weakSelf.downloadFailHandler) {
                    weakSelf.downloadFailHandler();
                }
            }
        });
    }];
}

+ (BOOL)isPlayableVideoAtURL:(NSURL *)url {
    if (!url) return NO;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    return asset.isPlayable;
}

- (void)play {
    if (self.player && !self.isPlaying) {
        [self.player play];
        self.isPlaying = YES;
        self.coverImageView.hidden = YES;
    }
}

- (void)pause {
    if (self.player && self.isPlaying) {
        [self.player pause];
        self.isPlaying = NO;
    }
}

- (void)stop {
    if (self.playerItem && self.isObserving) {
        @try {
            [self.playerItem removeObserver:self forKeyPath:@"status"];
        } @catch (NSException *exception) {
            // 防止移除不存在的监听导致崩溃
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVPlayerItemDidPlayToEndTimeNotification
                                                      object:self.playerItem];
        self.isObserving = NO;
    }

    [self.player pause];
    self.playerItem = nil;
    self.player = nil;

    [self.playerLayer removeFromSuperlayer];
    self.playerLayer = nil;

    self.isPlaying = NO;
    self.coverImageView.hidden = NO;
}

- (void)setContentMode:(UIViewContentMode)contentMode {
    [super setContentMode:contentMode];
    self.coverImageView.contentMode = contentMode;
    self.playerLayer.videoGravity = [self.class videoGravityFromContentMode:contentMode];
    [self setNeedsLayout];
}

#pragma mark - Private Helpers

- (void)setupPlayerWithURL:(NSURL *)url {
    // 避免重复创建相同url播放器项
    if ([self.playerItem.asset isKindOfClass:[AVURLAsset class]]) {
        AVURLAsset *asset = (AVURLAsset *)self.playerItem.asset;
        if ([asset.URL isEqual:url]) {
            return;
        }
    }

    [self stop];

    self.playerItem = [AVPlayerItem playerItemWithURL:url];
    [self.playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:nil];

    self.isObserving = YES;

    [self setPlayer];
    [self setPlayerLayer];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerDidFinishPlaying:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:self.playerItem];

    if (self.enableAlphaMask) {
        [self setAudioTacks];
        [self setAlphaMaskCompositionToPlayerItem:self.playerItem];
    }

    [self.player replaceCurrentItemWithPlayerItem:self.playerItem];

    if (self.autoPlayEnabled) {
        [self play];
    }
}

- (void)setPlayer {
    if (!_player) {
        _player = [AVPlayer playerWithPlayerItem:nil];
    }
}

- (void)setPlayerLayer {
    if (!_playerLayer) {
        _playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
        _playerLayer.videoGravity = [self.class videoGravityFromContentMode:self.contentMode];
        [self.layer insertSublayer:_playerLayer above:self.coverImageView.layer];
        _playerLayer.backgroundColor = UIColor.clearColor.CGColor;
    } else {
        _playerLayer.player = self.player;
    }
}

- (void)setAudioTacks {
    NSArray *audioTracks = [self.playerItem.asset tracksWithMediaType:AVMediaTypeAudio];
    NSMutableArray *allAudioParams = [NSMutableArray array];
    for (AVAssetTrack *track in audioTracks) {
        AVMutableAudioMixInputParameters *audioInputParams = [AVMutableAudioMixInputParameters audioMixInputParameters];
        [audioInputParams setVolume:[AVAudioSession sharedInstance].outputVolume atTime:kCMTimeZero];
        [audioInputParams setTrackID:[track trackID]];
        [allAudioParams addObject:audioInputParams];
    }

    AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix];
    [audioMix setInputParameters:allAudioParams];
    [self.playerItem setAudioMix:audioMix];
}

- (void)setAlphaMaskCompositionToPlayerItem:(AVPlayerItem *)playItem {
    AVAsset *asset = playItem.asset;

    if (@available(iOS 15.0, *)) {
        [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> * _Nullable assetTracks, NSError * _Nullable error) {
            if (error || assetTracks.count == 0) {
                NSLog(@"视频轨道加载失败: %@", error);
                return;
            }
            [self setupAlphaMaskWithAssetTracks:assetTracks playItem:playItem];
        }];
    } else {
        NSArray<AVAssetTrack *> *assetTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        if (assetTracks.count == 0) {
            NSLog(@"视频轨道加载失败");
            return;
        }
        [self setupAlphaMaskWithAssetTracks:assetTracks playItem:playItem];
    }
}

- (void)setupAlphaMaskWithAssetTracks:(NSArray<AVAssetTrack *> *)assetTracks
                             playItem:(AVPlayerItem *)playItem {
    AVAssetTrack *videoTrack = assetTracks.firstObject;
    CGSize fullSize = videoTrack.naturalSize;
    CGSize videoSize = CGSizeZero;
    
    switch (self.maskDirection) {
        case WXAlphaMaskDirectionLeftToRight:
        case WXAlphaMaskDirectionRightToLeft:
            videoSize = CGSizeMake(fullSize.width / 2.0, fullSize.height);
            break;
        case WXAlphaMaskDirectionTopToBottom:
        case WXAlphaMaskDirectionBottomToTop:
            videoSize = CGSizeMake(fullSize.width, fullSize.height / 2.0);
            break;
    }
    
#if DEBUG
    NSAssert(videoSize.width && videoSize.height, @"videoSize can't be zero");
#else
    if (!videoSize.width || !videoSize.height) return;
#endif
    
    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoCompositionWithAsset:playItem.asset applyingCIFiltersWithHandler:^(AVAsynchronousCIImageFilteringRequest * _Nonnull request) {
        CGRect sourceRect = CGRectMake(0, 0, videoSize.width, videoSize.height);
        CGRect alphaRect = CGRectZero;
        CGFloat dx = 0, dy = 0;
        
        switch (self.maskDirection) {
            case WXAlphaMaskDirectionLeftToRight:
            case WXAlphaMaskDirectionRightToLeft:
                alphaRect = CGRectOffset(sourceRect, videoSize.width, 0);
                dx = -sourceRect.size.width;
                dy = 0;
                break;
            case WXAlphaMaskDirectionTopToBottom:
            case WXAlphaMaskDirectionBottomToTop:
                alphaRect = CGRectOffset(sourceRect, 0, videoSize.height);
                dx = 0; dy = -sourceRect.size.height;
                break;
        }
        
        if (!videoKernel) {
            NSURL *kernelURL = [[NSBundle mainBundle] URLForResource:@"default" withExtension:@"metallib"];
            NSError *error;
            NSData *kernelData = [NSData dataWithContentsOfURL:kernelURL];
            videoKernel = [CIColorKernel kernelWithFunctionName:@"maskVideoMetal" fromMetalLibraryData:kernelData error:&error];
#if DEBUG
            NSAssert(!error, @"%@",error);
#endif
        }
        
        CIImage *inputImage = nil;
        CIImage *maskImage = nil;
        
        switch (self.maskDirection) {
            case WXAlphaMaskDirectionLeftToRight:
                inputImage = [[request.sourceImage imageByCroppingToRect:alphaRect] imageByApplyingTransform:CGAffineTransformMakeTranslation(dx, dy)];
                maskImage = [request.sourceImage imageByCroppingToRect:sourceRect];
                break;
            case WXAlphaMaskDirectionRightToLeft:
                inputImage = [request.sourceImage imageByCroppingToRect:sourceRect];
                maskImage = [[request.sourceImage imageByCroppingToRect:alphaRect] imageByApplyingTransform:CGAffineTransformMakeTranslation(dx, dy)];
                break;
            case WXAlphaMaskDirectionTopToBottom:
                inputImage = [request.sourceImage imageByCroppingToRect:sourceRect];
                maskImage = [[request.sourceImage imageByCroppingToRect:alphaRect] imageByApplyingTransform:CGAffineTransformMakeTranslation(dx, dy)];
                break;
            case WXAlphaMaskDirectionBottomToTop:
                inputImage = [[request.sourceImage imageByCroppingToRect:alphaRect] imageByApplyingTransform:CGAffineTransformMakeTranslation(dx, dy)];
                maskImage = [request.sourceImage imageByCroppingToRect:sourceRect];
                break;
        }
        
        if (inputImage && maskImage && videoKernel) {
            CIImage *outputImage = [videoKernel applyWithExtent:inputImage.extent arguments:@[inputImage, maskImage]];
            if (outputImage) {
                [request finishWithImage:outputImage context:nil];
            } else {
                NSError *error = [NSError errorWithDomain:@"com.st.mask" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"视频遮罩合成失败"}];
                [request finishWithError:error];
            }
        } else {
            NSError *error = [NSError errorWithDomain:@"com.st.mask" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"视频遮罩合成失败"}];
            [request finishWithError:error];
        }
    }];
    
    videoComposition.renderSize = videoSize;
    playItem.videoComposition = videoComposition;
    playItem.seekingWaitsForVideoCompositionRendering = YES;
    
    self.playerLayer.pixelBufferAttributes = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)
    };
}

#pragma mark - KVO & Notification

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if (object == self.playerItem) {
        if ([keyPath isEqualToString:@"status"]) {
            if (self.playerItem.status == AVPlayerItemStatusReadyToPlay) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.playerReadyHandler) {
                        self.playerReadyHandler();
                    }
                });
            } else if (self.playerItem.status == AVPlayerItemStatusFailed) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.downloadFailHandler) {
                        self.downloadFailHandler();
                    }
                });
            }
        }
    }
}

- (void)playerDidFinishPlaying:(NSNotification *)notification {
    if (notification.object != self.playerItem) return;

    if (self.loopEnabled) {
        __weak typeof(self) weakSelf = self;
        [self.player seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
            if (finished) {
                [weakSelf.player play];
            }
        }];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.playbackCompletedHandler) {
                self.playbackCompletedHandler();
            }
        });
    }
}

#pragma mark - Memory Warning

- (void)handleMemoryWarning {
    NSLog(@"⚠️ 收到内存警告，释放播放器相关资源");
    [self stop];
    // 这里可通知缓存管理器清理内存缓存或其他资源
}

#pragma mark - Utils

+ (AVLayerVideoGravity)videoGravityFromContentMode:(UIViewContentMode)contentMode {
    switch (contentMode) {
        case UIViewContentModeScaleAspectFit:
            return AVLayerVideoGravityResizeAspect;
        case UIViewContentModeScaleAspectFill:
            return AVLayerVideoGravityResizeAspectFill;
        case UIViewContentModeScaleToFill:
            return AVLayerVideoGravityResize;
        default:
            return AVLayerVideoGravityResizeAspect;
    }
}

#pragma mark - Dealloc

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stop];
}


@end
