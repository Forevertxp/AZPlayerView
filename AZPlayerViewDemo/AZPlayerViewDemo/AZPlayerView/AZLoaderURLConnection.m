//  PlayerView.h
//  LiveViewDemo
//
//  Created by arronzhu on 16/7/18.
//  Copyright © 2016年 arronzhu. All rights reserved.
//

#import "AZLoaderURLConnection.h"
#import "AZVideoRequestTask.h"

@interface AZLoaderURLConnection ()<AZVideoRequestTaskDelegate>

@property (nonatomic, strong) NSMutableArray *pendingRequests;
@property (nonatomic, strong) NSString       *cachePath;
@property (nonatomic, copy  ) NSString       *videoPath;
@end

@implementation AZLoaderURLConnection

- (instancetype)initWithCacheUrl:(NSURL *)url {
    self = [super init];
    if (self) {
        _pendingRequests = [NSMutableArray array];
        if (url) {
            _cachePath = [url absoluteString];
        } else {
            _cachePath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).lastObject;
        }
        _videoPath = [_cachePath stringByAppendingPathComponent:@"temp.mp4"];
    }
    return self;
}

- (void)fillInContentInformation:(AVAssetResourceLoadingContentInformationRequest *)contentInformationRequest
{
    NSString *mimeType = self.task.mimeType;
    CFStringRef contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)(mimeType), NULL);
    contentInformationRequest.byteRangeAccessSupported = YES;
    contentInformationRequest.contentType = CFBridgingRelease(contentType);
    contentInformationRequest.contentLength = self.task.videoLength;
}

#pragma mark - AVURLAsset resource loader methods

- (void)processPendingRequests
{
    NSMutableArray *requestsCompleted = [NSMutableArray array];  //请求完成的数组
    //每次下载一块数据都是一次请求，把这些请求放到数组，遍历数组
    for (AVAssetResourceLoadingRequest *loadingRequest in self.pendingRequests)
    {
        [self fillInContentInformation:loadingRequest.contentInformationRequest]; //对每次请求加上长度，文件类型等信息
        
        BOOL didRespondCompletely = [self respondWithDataForRequest:loadingRequest.dataRequest]; //判断此次请求的数据是否处理完全
        
        if (didRespondCompletely) {
            
            [requestsCompleted addObject:loadingRequest];  //如果完整，把此次请求放进 请求完成的数组
            [loadingRequest finishLoading];
            
        }
    }
    
    [self.pendingRequests removeObjectsInArray:requestsCompleted];   //在所有请求的数组中移除已经完成的
    
}


- (BOOL)respondWithDataForRequest:(AVAssetResourceLoadingDataRequest *)dataRequest
{
    long long startOffset = dataRequest.requestedOffset;
    
    if (dataRequest.currentOffset != 0) {
        startOffset = dataRequest.currentOffset;
    }
    
    if ((self.task.offset +self.task.downLoadingOffset) < startOffset)
    {
        //NSLog(@"NO DATA FOR REQUEST");
        return NO;
    }
    
    if (startOffset < self.task.offset) {
        return NO;
    }
    
    NSData *filedata = [NSData dataWithContentsOfURL:[NSURL fileURLWithPath:_videoPath] options:NSDataReadingMappedIfSafe error:nil];
    
    // This is the total data we have from startOffset to whatever has been downloaded so far
    NSUInteger unreadBytes = self.task.downLoadingOffset - ((NSInteger)startOffset - self.task.offset);
    
    // Respond with whatever is available if we can't satisfy the request fully yet
    NSUInteger numberOfBytesToRespondWith = MIN((NSUInteger)dataRequest.requestedLength, unreadBytes);
    
    
    [dataRequest respondWithData:[filedata subdataWithRange:NSMakeRange((NSUInteger)startOffset- self.task.offset, (NSUInteger)numberOfBytesToRespondWith)]];
    
    
    
    long long endOffset = startOffset + dataRequest.requestedLength;
    BOOL didRespondFully = (self.task.offset + self.task.downLoadingOffset) >= endOffset;
    
    return didRespondFully;
    
    
}


/**
 *  必须返回Yes，如果返回NO，则resourceLoader将会加载出现故障的数据
 *  这里会出现很多个loadingRequest请求， 需要为每一次请求作出处理
 *  @param resourceLoader 资源管理器
 *  @param loadingRequest 每一小块数据的请求
 *
 */
- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest
{
    //获取系统中不能处理的URL
    NSURL *resourceURL = [loadingRequest.request URL];
    //判断这个URL是否是我们所设定的URL
    if ([resourceURL.scheme isEqualToString:kCustomVideoScheme]){
        [self.pendingRequests addObject:loadingRequest];
        [self dealWithLoadingRequest:loadingRequest];
        return YES;
    } else {
        return NO;
    }
}


- (void)dealWithLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
{
    NSURL *interceptedURL = [loadingRequest.request URL];
    NSRange range = NSMakeRange((NSUInteger)loadingRequest.dataRequest.currentOffset, NSUIntegerMax);
    
    if (self.task.downLoadingOffset > 0) {
        [self processPendingRequests];
    }
    
    if (!self.task) {
        self.task = [[AZVideoRequestTask alloc] initWithCachePath:_cachePath];
        self.task.delegate = self;
        [self.task setUrl:interceptedURL offset:0];
    } else {
        // 如果新的rang的起始位置比当前缓存的位置还大300k，则重新按照range请求数据
        if (self.task.offset + self.task.downLoadingOffset + 1024 * 300 < range.location ||
            // 如果往回拖也重新请求
            range.location < self.task.offset) {
            [self.task setUrl:interceptedURL offset:range.location];
        }
    }
}


- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
{
    [self.pendingRequests removeObject:loadingRequest];
    
}

- (NSURL *)getSchemeVideoURL:(NSURL *)url
{
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:url resolvingAgainstBaseURL:NO];
    components.scheme = kCustomVideoScheme;
    return [components URL];
}

#pragma mark - TBVideoRequestTaskDelegate

- (void)task:(AZVideoRequestTask *)task didReciveVideoLength:(NSUInteger)videoLength mimeType:(NSString *)mimeType {
    
}

- (void)didReciveVideoDataWithTask:(AZVideoRequestTask *)task {
    [self processPendingRequests];
}

- (void)didFinishLoadingWithTask:(AZVideoRequestTask *)task {
    if ([self.delegate respondsToSelector:@selector(didFinishLoadingWithTask:)]) {
        [self.delegate didFinishLoadingWithTask:task];
    }
}

- (void)didFailLoadingWithTask:(AZVideoRequestTask *)task withError:(NSError *)error {
    [self.task clearData];
    if ([self.delegate respondsToSelector:@selector(didFailLoadingWithTask:withError:)]) {
        [self.delegate didFailLoadingWithTask:task withError:error];
    }
}

@end
