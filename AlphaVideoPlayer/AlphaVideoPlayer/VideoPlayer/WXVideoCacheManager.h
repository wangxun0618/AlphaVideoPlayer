//
//  WXVideoCacheManager.h
//  AlphaVideoPlayer
//
//  Created by M2-2023 on 2025/6/26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WXVideoCacheManager : NSObject
/// 单例
+ (instancetype)sharedManager;

/// 根据远程 URL 生成本地缓存文件路径（哈希命名）
- (NSURL *)cachedFileURLForRemoteURL:(NSURL *)remoteURL;

/// 判断缓存文件是否存在
- (BOOL)isCacheFileExistForRemoteURL:(NSURL *)remoteURL;

/// 异步下载并缓存视频，完成后回调本地文件路径或错误（主线程）
- (void)downloadAndCacheVideoWithURL:(NSURL *)remoteURL
                          completion:(void(^)(NSURL * _Nullable localURL, NSError * _Nullable error))completion;

/// 清理缓存目录中过期的缓存文件，expireSeconds 是过期时间（单位：秒）
- (void)clearExpiredCacheWithExpireTime:(NSTimeInterval)expireSeconds;

/// 手动清理所有缓存文件
- (void)clearAllCache;

@end

NS_ASSUME_NONNULL_END
