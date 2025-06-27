//
//  WXVideoCacheManager.m
//  AlphaVideoPlayer
//
//  Created by M2-2023 on 2025/6/26.
//

#import "WXVideoCacheManager.h"
#import <CommonCrypto/CommonCrypto.h>

@interface WXVideoCacheManager ()

@property (nonatomic, strong) dispatch_queue_t ioQueue;
@property (nonatomic, strong) dispatch_queue_t barrierQueue;
@property (nonatomic, strong) NSMutableDictionary<NSURL *, NSMutableArray<void(^)(NSURL * _Nullable, NSError * _Nullable)> *> *downloadCallbacks;

@end

@implementation WXVideoCacheManager
+ (instancetype)sharedManager {
    static WXVideoCacheManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WXVideoCacheManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _ioQueue = dispatch_queue_create("com.videoplayer.cache.io", DISPATCH_QUEUE_SERIAL);
        _barrierQueue = dispatch_queue_create("com.videoplayer.cache.barrier", DISPATCH_QUEUE_CONCURRENT);
        _downloadCallbacks = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - Hash Filename

- (NSString *)md5FromString:(NSString *)input {
    if (!input) return nil;
    const char *str = [input UTF8String];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(str, (CC_LONG)strlen(str), result);
    NSMutableString *hash = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [hash appendFormat:@"%02x", result[i]];
    }
    return hash;
}

#pragma mark - Cache Directory

- (NSString *)cacheDirectoryPath {
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
                          stringByAppendingPathComponent:@"WXAnimateVideoCache"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:cacheDir]) {
        [fm createDirectoryAtPath:cacheDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return cacheDir;
}

#pragma mark - File Path

- (NSURL *)cachedFileURLForRemoteURL:(NSURL *)remoteURL {
    if (!remoteURL || ![remoteURL isKindOfClass:NSURL.class]) return nil;

    NSString *hashName = [self md5FromString:remoteURL.absoluteString];
    if (!hashName) return nil;

    NSString *fileName = [hashName stringByAppendingString:@".mp4"];
    NSString *fullPath = [[self cacheDirectoryPath] stringByAppendingPathComponent:fileName];
    return [NSURL fileURLWithPath:fullPath];
}

- (BOOL)isCacheFileExistForRemoteURL:(NSURL *)remoteURL {
    NSURL *fileURL = [self cachedFileURLForRemoteURL:remoteURL];
    return [[NSFileManager defaultManager] fileExistsAtPath:fileURL.path];
}

#pragma mark - Download and Merge

- (void)downloadAndCacheVideoWithURL:(NSURL *)remoteURL
                          completion:(void(^)(NSURL * _Nullable localURL, NSError * _Nullable error))completion {

    if (!remoteURL) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, [NSError errorWithDomain:@"WXAnimateVideoCache" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"无效的 URL"}]);
            });
        }
        return;
    }

    // 如果已缓存，直接返回
    if ([self isCacheFileExistForRemoteURL:remoteURL]) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion([self cachedFileURLForRemoteURL:remoteURL], nil);
            });
        }
        return;
    }

    __block BOOL shouldDownload = NO;

    dispatch_barrier_sync(self.barrierQueue, ^{
        NSMutableArray *callbacks = self.downloadCallbacks[remoteURL];
        if (callbacks) {
            if (completion) {
                [callbacks addObject:[completion copy]];
            }
        } else {
            NSMutableArray *arr = [NSMutableArray array];
            if (completion) {
                [arr addObject:[completion copy]];
            }
            self.downloadCallbacks[remoteURL] = arr;
            shouldDownload = YES;
        }
    });

    if (!shouldDownload) return;

    // 开始下载
    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession]
        downloadTaskWithURL:remoteURL
          completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {

        NSURL *cachedURL = nil;
        if (!error && location) {
            cachedURL = [self cachedFileURLForRemoteURL:remoteURL];
            dispatch_sync(self.ioQueue, ^{
                NSFileManager *fm = [NSFileManager defaultManager];
                if ([fm fileExistsAtPath:cachedURL.path]) {
                    [fm removeItemAtPath:cachedURL.path error:nil];
                }
                [fm moveItemAtURL:location toURL:cachedURL error:nil];
            });
        } else {
            NSLog(@"[WXVideoCacheManager] 下载失败: %@\n%@", remoteURL, error);
        }

        // 提取所有回调，清理字典
        __block NSArray *callbacks = nil;
        dispatch_barrier_sync(self.barrierQueue, ^{
            callbacks = [self.downloadCallbacks[remoteURL] copy];
            [self.downloadCallbacks removeObjectForKey:remoteURL];
        });

        // 主线程回调
        dispatch_async(dispatch_get_main_queue(), ^{
            for (void(^cb)(NSURL *, NSError *) in callbacks) {
                cb(cachedURL, error);
            }
        });
    }];

    [task resume];
}

#pragma mark - 清理缓存

- (void)clearExpiredCacheWithExpireTime:(NSTimeInterval)expireSeconds {
    dispatch_async(self.ioQueue, ^{
        NSString *cacheDir = [self cacheDirectoryPath];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:cacheDir error:nil];
        NSDate *now = [NSDate date];

        for (NSString *fileName in files) {
            NSString *filePath = [cacheDir stringByAppendingPathComponent:fileName];
            NSDictionary *attrs = [fm attributesOfItemAtPath:filePath error:nil];
            NSDate *modDate = attrs[NSFileModificationDate];
            if (modDate && [now timeIntervalSinceDate:modDate] > expireSeconds) {
                [fm removeItemAtPath:filePath error:nil];
            }
        }
    });
}

- (void)clearAllCache {
    dispatch_async(self.ioQueue, ^{
        NSString *cacheDir = [self cacheDirectoryPath];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:cacheDir error:nil];
        for (NSString *fileName in files) {
            NSString *filePath = [cacheDir stringByAppendingPathComponent:fileName];
            [fm removeItemAtPath:filePath error:nil];
        }
    });
}
@end
