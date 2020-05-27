//
//  QNLogCT.m
//  Logan-iOS_Example
//
//  Created by 白龙 on 2020/4/3.
//  Copyright © 2020 jiangteng. All rights reserved.
//

#import "QNLogCT.h"
#import <sys/time.h>
#include <sys/mount.h>
#import <sys/sysctl.h>
#include "clogan_core.h"

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

static BOOL __ASLDump = NO;
static NSString* __server;
static NSData *__AES_KEY;
static NSData *__AES_IV;
static uint64_t __max_file;
static uint32_t __max_reversed_date;

static NSString* __appId;
static NSString* __deviceType;
static QNLogCtDeviceInfo* __info;

#define AppKeyLength 24

/**
 返回文件路径
 
 @param filePath filePath nil时表示文件不存在
 */
typedef void (^LoganFilePathBlock)(NSString *_Nullable filePath);

@interface LoganWrapper : NSObject {
    NSTimeInterval _lastCheckFreeSpace;
}
@property (nonatomic, copy) NSString *lastLogDate;

#if OS_OBJECT_USE_OBJC
@property (nonatomic, strong) dispatch_queue_t loganQueue;
@property (nonatomic, strong) dispatch_queue_t uploadQueue;
@property (nonatomic, strong) NSMutableArray<NSDictionary*>* buffer;
#else
@property (nonatomic, assign) dispatch_queue_t loganQueue;
@property (nonatomic, assign) dispatch_queue_t uploadQueue;
@property (nonatomic, assign) NSMutableArray<NSDictionary*>* buffer;
#endif

+ (instancetype)instance;

- (void)writeLog:(NSString *)log logType:(NSUInteger)type;
- (void)clearLogs;
+ (NSDictionary *)allFilesInfo;
+ (NSString*) dateFormat:(NSDate*)date;
- (void)flush;
- (void)filePathForDate:(NSString *)date
                  block:(LoganFilePathBlock)filePathBlock;
@end

static NSString* deviceModel(void) {
  size_t size;
  sysctlbyname("hw.machine", NULL, &size, NULL, 0);
  char *answer = (char *)malloc(size);
  if (answer == NULL)
    return @"";
  sysctlbyname("hw.machine", answer, &size, NULL, 0);
  NSString *platform =
      [NSString stringWithCString:answer encoding:NSUTF8StringEncoding];
  free(answer);
  return platform;
}

static NSString* buildDeviceInfo(){
    QNLogCtDeviceInfo* info = __info;
    NSMutableDictionary *dict = [NSMutableDictionary new];

    if(info.userID && info.userID.length >0){
        [dict setValue:info.userID forKey:@"user"];
    }
    NSString *bundleVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    if (bundleVersion.length > 0) {
       [dict setValue:bundleVersion forKey:@"bundleVersion"];
    }

    if(info.deviceID && info.deviceID.length >0){
        [dict setValue:info.deviceID forKey:@"deviceId"];
    }
    [dict setValue:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] forKey:@"appVersion"];
    [dict setValue:@"iOS" forKey:@"platform"];

    
    if (info.channel) {
        [dict setValue:info.channel forKey:@"channel"];
    }
    if (info.provider) {
        [dict setValue:info.provider forKey:@"provider"];
    }
    if (info.extra) {
        [dict setValue:info.extra forKey:@"extra"];
    }
    
    [dict setValue:@SDK_VERSION forKey:@"sdkVersion"];
    
    NSString* osVersion;
    #if TARGET_OS_IPHONE
    osVersion = [[UIDevice currentDevice] systemVersion];
    #else
    osVersion = [[NSProcessInfo processInfo] operatingSystemVersionString];
    #endif
    [dict setValue: osVersion forKey:@"osVersion"];
    
    [dict setValue:@"Apple" forKey:@"manufacturer"];
    [dict setValue:__deviceType forKey:@"deviceType"];
    [dict setValue:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleExecutable"] forKey:@"appName"];
    [dict setValue:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"] forKey:@"packageId"];
    NSString* str = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:dict options:kNilOptions error:nil] encoding:NSUTF8StringEncoding];
    NSData* d = [str dataUsingEncoding:NSUTF8StringEncoding];
    d = [d base64EncodedDataWithOptions:0];
    return [[NSString alloc] initWithData:d encoding:NSASCIIStringEncoding];
}

NSError* QNLogCtInit(NSString* _Nonnull server, NSString* _Nonnull appKey, uint64_t maxFileSize){
    if (!server.length) {
        return [LogCtError
            GenerateNSError:kLogCtErrorCodeInvalidServiceDomain
                description:@"必须指定 server domain ！！！！！！"];
    }
    if (appKey.length != AppKeyLength) {
        return [LogCtError
            GenerateNSError:kLogCtErrorCodeInvalidAppKey
                description:@"app key 的长度必须大于等于 %d！！！！！！",
                            AppKeyLength];
    }
    
    if (![server hasPrefix:@"http://"] &&
        ![server hasPrefix:@"https://"]) {
        server = [NSString stringWithFormat:@"http://%@", server];
    }
    NSURL *url = [NSURL URLWithString:server];
    if (!url) {
      return [LogCtError
          GenerateNSError:kLogCtErrorCodeInvalidServiceDomain
              description:@"service domain 的结构不正确: %@ ！！！！！！",
                          server];
    }
    __server = [server copy];
    NSString* aes = [appKey substringFromIndex:8];
    __AES_KEY = [aes dataUsingEncoding:NSASCIIStringEncoding];
     NSString* iv = [appKey substringToIndex:16];
    __AES_IV = [iv dataUsingEncoding:NSASCIIStringEncoding];
    __max_file = maxFileSize;
    if (__max_reversed_date == 0) {
        __max_reversed_date = 7;
    }
   
    __appId = [appKey substringToIndex:8];
    __deviceType = deviceModel();
    return nil;
}

void QNLogCtSetMaxReservedDays(int max_reversed_date) {
    if (max_reversed_date > 0) {
        __max_reversed_date = max_reversed_date;
    }
    
}
void QNLogCtSave(NSUInteger type, NSString *_Nonnull log) {
    [[LoganWrapper instance] writeLog:log logType:type];
}

void QNLogCtDumpOutput(BOOL b) {
    __ASLDump = b;
}

void QNLogCtClearAllLogs(void) {
    [[LoganWrapper instance] clearLogs];
}

NSDictionary *_Nullable QNLogCtAllFilesInfo(void) {
    return [LoganWrapper allFilesInfo];
}

void QNLogCtUploadFilePath(NSString *_Nonnull date, LoganFilePathBlock _Nonnull filePathBlock) {
    [[LoganWrapper instance] filePathForDate:date block:filePathBlock];
}

void QNLogCtFlush(void) {
    [[LoganWrapper instance] flush];
}

NSString *_Nonnull QNLogCtTodaysDate(void) {
    return [LoganWrapper dateFormat:[NSDate new]];
}

@interface LogCtItem : NSObject

@property NSString *log;
@property int category;
@property long long local_time;
@property NSString *thread_name;
@property long long thread_id;
@property int is_main;

-(instancetype)initWithCategory:(int)category
                            log:(NSString*)log
                      localTime:(long long)time
                     threadName:(NSString*)threadName
                       threadId:(long long)threadId
                         isMain:(int)isMain;

-(NSDictionary*)toDict;
@end

@implementation LogCtItem

-(instancetype)initWithCategory:(int)category
       log:(NSString*)log
 localTime:(long long)time
threadName:(NSString*)threadName
  threadId:(long long)threadId
    isMain:(int)isMain{
    if (self = [super init]) {
           _log = log;
           _category = category;
           _local_time = time;
        _thread_name = threadName;
        _thread_id = threadId;
        _is_main = isMain;
       }
       return self;
}

-(NSDictionary*)toDict {
    return [self dictionaryWithValuesForKeys:@[@"log",@"category", @"local_time", @"thread_name", @"thread_id", @"is_main"]];
}

@end

@implementation LoganWrapper
+ (instancetype)instance {
    static LoganWrapper *_instance = nil;
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        _instance = [[LoganWrapper alloc] init];
    });
    return _instance;
}

- (nonnull instancetype)init {
    if (self = [super init]) {
        _buffer = [NSMutableArray new];
        _loganQueue = dispatch_queue_create("logct.logan", DISPATCH_QUEUE_SERIAL);
        _uploadQueue = dispatch_queue_create("logct.upload", DISPATCH_QUEUE_SERIAL);
        dispatch_async(self.loganQueue, ^{
            [self initAndOpenCLib];
            [self addNotification];
            [self cleanTempFile];
            [LoganWrapper deleteOutdatedFiles];
        });
    }
    return self;
}

- (void)initAndOpenCLib {
    NSAssert(__AES_KEY, @"aes_key is nil!!!,Please use llogInit() to set the key.");
    NSAssert(__AES_IV, @"aes_iv is nil!!!,Please use llogInit() to set the iv.");
    const char *path = [LoganWrapper loganLogDirectory].UTF8String;
    
    const char *aeskey = (const char *)[__AES_KEY bytes];
    const char *aesiv = (const char *)[__AES_IV bytes];
    clogan_init(path, path, (int)__max_file, aeskey, aesiv);
    NSString *today = QNLogCtTodaysDate();
    clogan_open((char *)today.UTF8String);
    __AES_KEY = nil;
    __AES_IV = nil;
}

- (void)writeLog:(NSString *)log logType:(NSUInteger)type {
    if (log.length == 0) {
        return;
    }
    
    NSTimeInterval localTime = [[NSDate date] timeIntervalSince1970] * 1000;
    NSString *threadName = [[NSThread currentThread] name];
    NSInteger threadNum = 1;
    BOOL threadIsMain = [[NSThread currentThread] isMainThread];
    if (!threadIsMain) {
        threadNum = [self getThreadNum];
    }
    char *threadNameC = threadName ? (char *)threadName.UTF8String : "";
    if (__ASLDump) {
        [self printfLog:log type:type];
    }
    
    if (![self hasFreeSpace]) {
        return;
    }
    
    dispatch_async(self.loganQueue, ^{
        NSString *today = QNLogCtTodaysDate();
        if (self.lastLogDate && ![self.lastLogDate isEqualToString:today]) {
                // 日期变化，立即写入日志文件
            clogan_flush();
            clogan_open((char *)today.UTF8String);
        }
        self.lastLogDate = today;
        clogan_write((int)type, (char *)log.UTF8String, (long long)localTime, threadNameC, (long long)threadNum, (int)threadIsMain);
    });
}

- (void)sendLog:(NSString *)log logType:(NSUInteger)type {
    if (log.length == 0) {
        return;
    }
    
    NSTimeInterval localTime = [[NSDate date] timeIntervalSince1970] * 1000;
    NSString *threadName = [[NSThread currentThread] name];
    NSInteger threadNum = 1;
    BOOL threadIsMain = [[NSThread currentThread] isMainThread];
    if (!threadIsMain) {
        threadNum = [self getThreadNum];
    }

    if (__ASLDump) {
        [self printfLog:log type:type];
    }
    
    LogCtItem *it = [[LogCtItem alloc] initWithCategory:(int)type log:log localTime:(long long)localTime threadName:threadName threadId:(long long)threadNum isMain:(int)threadIsMain];
    [_buffer addObject:[it toDict]];
    if ([_buffer count] >= 2) {
        dispatch_async(self.uploadQueue, ^{
            [self uploadLogRealtime];
        });
    }
}

- (void)uploadLogRealtime {
    NSString *urlStr = [NSString stringWithFormat:@"%@/logct/v1/native/%@/auto", __server, __appId];
    NSURL *url = [NSURL URLWithString:urlStr];
    NSMutableURLRequest *req = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60];
    [req setHTTPMethod:@"POST"];
    [req addValue:@"binary/octet-stream" forHTTPHeaderField:@"Content-Type"];
    NSString* infoStr = buildDeviceInfo();
    [req addValue:infoStr forHTTPHeaderField:@"X-REQINFO"];
    NSData * d = [NSJSONSerialization dataWithJSONObject:_buffer options:kNilOptions error:nil];
    
    NSURLSessionUploadTask * task = [[NSURLSession sharedSession] uploadTaskWithRequest:req fromData:d  completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error) {
        [_buffer removeAllObjects];
        NSLog(@"upload auto %@", error);
    }];
    [task resume];
}

- (void)flush {
    dispatch_async(self.loganQueue, ^{
        [self flushInQueue];
    });
}

- (void)flushInQueue {
    clogan_flush();
}

- (void)clearLogs {
    dispatch_async(self.loganQueue, ^{
        NSArray *array = [LoganWrapper localFilesArray];
        NSError *error = nil;
        BOOL ret;
        for (NSString *name in array) {
            NSString *path = [[LoganWrapper loganLogDirectory] stringByAppendingPathComponent:name];
            ret = [[NSFileManager defaultManager] removeItemAtPath:path error:&error];
        }
    });
}

- (BOOL)hasFreeSpace {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now > (_lastCheckFreeSpace + 60)) {
        _lastCheckFreeSpace = now;
            // 每隔至少1分钟，检查一下剩余空间
        long long freeDiskSpace = [self freeDiskSpaceInBytes];
        if (freeDiskSpace <= 5 * 1024 * 1024) {
                // 剩余空间不足5m时，不再写入
            return NO;
        }
    }
    return YES;
}

- (long long)freeDiskSpaceInBytes {
    struct statfs buf;
    long long freespace = -1;
    if (statfs("/var", &buf) >= 0) {
        freespace = (long long)(buf.f_bsize * buf.f_bfree);
    }
    return freespace;
}

- (NSInteger)getThreadNum {
    NSString *description = [[NSThread currentThread] description];
    NSRange beginRange = [description rangeOfString:@"{"];
    NSRange endRange = [description rangeOfString:@"}"];
    
    if (beginRange.location == NSNotFound || endRange.location == NSNotFound) return -1;
    
    NSInteger length = endRange.location - beginRange.location - 1;
    if (length < 1) {
        return -1;
    }
    
    NSRange keyRange = NSMakeRange(beginRange.location + 1, length);
    
    if (keyRange.location == NSNotFound) {
        return -1;
    }
    
    if (description.length > (keyRange.location + keyRange.length)) {
        NSString *keyPairs = [description substringWithRange:keyRange];
        NSArray *keyValuePairs = [keyPairs componentsSeparatedByString:@","];
        for (NSString *keyValuePair in keyValuePairs) {
            NSArray *components = [keyValuePair componentsSeparatedByString:@"="];
            if (components.count) {
                NSString *key = components[0];
                key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (([key isEqualToString:@"num"] || [key isEqualToString:@"number"]) && components.count > 1) {
                    return [components[1] integerValue];
                }
            }
        }
    }
    return -1;
}

- (void)printfLog:(NSString *)log type:(NSUInteger)type {
    static time_t dtime = -1;
    if (dtime == -1) {
        time_t tm;
        time(&tm);
        struct tm *t_tm;
        t_tm = localtime(&tm);
        dtime = t_tm->tm_gmtoff;
    }
    struct timeval time;
    gettimeofday(&time, NULL);
    int secOfDay = (time.tv_sec + dtime) % (3600 * 24);
    int hour = secOfDay / 3600;
    int minute = secOfDay % 3600 / 60;
    int second = secOfDay % 60;
    int millis = time.tv_usec / 1000;
    NSString *str = [[NSString alloc] initWithFormat:@"%02d:%02d:%02d.%03d [%lu] %@\n", hour, minute, second, millis, (unsigned long)type, log];
    const char *buf = [str cStringUsingEncoding:NSUTF8StringEncoding];
    printf("%s", buf);
}
#pragma mark - notification
- (void)addNotification {
    // App Extension
    if ( [[[NSBundle mainBundle] bundlePath] hasSuffix:@".appex"] ) {
        return ;
    }
#if TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground) name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillTerminate) name:UIApplicationWillTerminateNotification object:nil];
#else
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillEnterForeground) name:NSApplicationWillBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidEnterBackground) name:NSApplicationDidResignActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillTerminate) name:NSApplicationWillTerminateNotification object:nil];
#endif

}

- (void)appWillResignActive {
    [self flush];
}

- (void)appDidEnterBackground {
    [self flush];
}

- (void)appWillEnterForeground {
    [self flush];
}

- (void)appWillTerminate {
    [self flush];
}

- (void)filePathForDate:(NSString *)date block:(LoganFilePathBlock)filePathBlock {
    NSString *uploadFilePath = nil;
    NSString *filePath = nil;
    if (date.length) {
        NSArray *allFiles = [LoganWrapper localFilesArray];
        if ([allFiles containsObject:date]) {
            filePath = [LoganWrapper logFilePath:date];
            if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
                uploadFilePath = filePath;
            }
        }
    }
    
    if (uploadFilePath.length) {
        if ([date isEqualToString:QNLogCtTodaysDate()]) {
            dispatch_async(self.loganQueue, ^{
                [self todayFilePath:filePathBlock];
            });
            return;
        }
    }
    dispatch_async(_uploadQueue, ^{
        filePathBlock(uploadFilePath);
    });
}

- (void)todayFilePath:(LoganFilePathBlock)filePathBlock {
    [self flushInQueue];
    NSString *currentDate = QNLogCtTodaysDate();
    NSString *uploadFilePath = [LoganWrapper uploadFilePath: currentDate];
    NSString *filePath = [LoganWrapper logFilePath: currentDate];
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:uploadFilePath error:&error];
    if (![[NSFileManager defaultManager] copyItemAtPath:filePath toPath:uploadFilePath error:&error]) {
        uploadFilePath = nil;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        filePathBlock(uploadFilePath);
    });
}

- (void)cleanTempFile {
    NSArray *allFiles = [LoganWrapper localFilesArray];
    for (NSString *f in allFiles) {
        if ([f hasSuffix:@".temp"]) {
            NSString *filePath = [LoganWrapper logFilePath:f];
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:NULL];
        }
    }
}


- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (NSDictionary *)allFilesInfo {
    NSArray *allFiles = [LoganWrapper localFilesArray];
    NSString *dateFormatString = @"yyyy-MM-dd";
    NSMutableDictionary *infoDic = [NSMutableDictionary new];
    for (NSString *file in allFiles) {
        if ([file pathExtension].length > 0) {
            continue;
        }
        NSString *dateString = [file substringToIndex:dateFormatString.length];
        unsigned long long gzFileSize = [LoganWrapper fileSizeAtPath:[self logFilePath:dateString]];
        NSString *size = [NSString stringWithFormat:@"%llu", gzFileSize];
        [infoDic setObject:size forKey:dateString];
    }
    return infoDic;
}

+ (void)deleteOutdatedFiles {
    NSArray *allFiles = [LoganWrapper localFilesArray];
    __block NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    NSString *dateFormatString = @"yyyy-MM-dd";
    [formatter setDateFormat:dateFormatString];
    [allFiles enumerateObjectsUsingBlock:^(NSString *_Nonnull dateStr, NSUInteger idx, BOOL *_Nonnull stop) {
            // 检查后缀名
        if ([dateStr pathExtension].length > 0) {
            [self deleteLoganFile:dateStr];
            return;
        }
        
            // 检查文件名长度
        if (dateStr.length != (dateFormatString.length)) {
            [self deleteLoganFile:dateStr];
            return;
        }
            // 文件名转化为日期
        dateStr = [dateStr substringToIndex:dateFormatString.length];
        NSDate *date = [formatter dateFromString:dateStr];
        NSString *todayStr = QNLogCtTodaysDate();
        NSDate *todayDate = [formatter dateFromString:todayStr];
        if (!date || [self getDaysFrom:date To:todayDate] >= __max_reversed_date) {
                // 删除过期文件
            [self deleteLoganFile:dateStr];
        }
    }];
}

+ (void)deleteLoganFile:(NSString *)name {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:[[self loganLogDirectory] stringByAppendingPathComponent:name] error:nil];
}

+ (NSInteger)getDaysFrom:(NSDate *)serverDate To:(NSDate *)endDate {
    NSCalendar *gregorian = [[NSCalendar alloc]
                             initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    
    NSDate *fromDate;
    NSDate *toDate;
    [gregorian rangeOfUnit:NSCalendarUnitDay startDate:&fromDate interval:NULL forDate:serverDate];
    [gregorian rangeOfUnit:NSCalendarUnitDay startDate:&toDate interval:NULL forDate:endDate];
    NSDateComponents *dayComponents = [gregorian components:NSCalendarUnitDay fromDate:fromDate toDate:toDate options:0];
    return dayComponents.day;
}

+ (NSString *)uploadFilePath:(NSString *)date {
    return [[LoganWrapper loganLogDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.temp", date]];
}
+ (NSString *)logFilePath:(NSString *)date {
    return [[LoganWrapper loganLogDirectory] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@", date]];
}

+ (unsigned long long)fileSizeAtPath:(NSString *)filePath {
    if (filePath.length == 0) {
        return 0;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isExist = [fileManager fileExistsAtPath:filePath];
    if (isExist) {
        return [[fileManager attributesOfItemAtPath:filePath error:nil] fileSize];
    } else {
        return 0;
    }
}

+ (NSArray *)localFilesArray {
    return [[[[NSFileManager defaultManager] contentsOfDirectoryAtPath:[LoganWrapper loganLogDirectory] error:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF CONTAINS[cd] '-'"]] sortedArrayUsingSelector:@selector(compare:)]; //[c]不区分大小写 , [d]不区分发音符号即没有重音符号 , [cd]既不区分大小写，也不区分发音符号。
}

+ (NSString*) dateFormat:(NSDate*) date {
    NSString *key = @"LOGCT_DATE";
    NSMutableDictionary *dictionary = [[NSThread currentThread] threadDictionary];
    NSDateFormatter *dateFormatter = [dictionary objectForKey:key];
    if (!dateFormatter) {
        dateFormatter = [[NSDateFormatter alloc] init];
        [dictionary setObject:dateFormatter forKey:key];
        [dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
        [dateFormatter setDateFormat:@"yyyy-MM-dd"];
        [dictionary setObject:dateFormatter forKey:key];
    }
    return [dateFormatter stringFromDate:date];
}

+ (NSString *)loganLogDirectory {
    static NSString *dir = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dir = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"LoganLoggerv3"];
    });
    return dir;
}
@end


void QNLogCtUpload(NSDate * _Nonnull d, QNLogCtUploadResultBlock _Nullable resultBlock) {
    NSString* date = QNLogCtTodaysDate();
    QNLogCtUploadFilePath(date, ^(NSString *_Nullable filePath) {
        if (filePath == nil) {
            if(resultBlock){
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSError * error = [LogCtError GenerateNSError:kLogCtErrorCodeNoLogError description:@"can't find file of %@",date];
                    resultBlock(error);
                });
            }
            return;
        }
        
        NSString *urlStr = [NSString stringWithFormat:@"%@/logct/v1/native/%@/tasks", __server, __appId];
        NSURL *url = [NSURL URLWithString:urlStr];
        NSMutableURLRequest *req = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60];
        [req setHTTPMethod:@"POST"];
        [req addValue:@"binary/octet-stream" forHTTPHeaderField:@"Content-Type"];
        NSString* infoStr = buildDeviceInfo();
        [req addValue:date forHTTPHeaderField:@"fileDate"];
        [req addValue:infoStr forHTTPHeaderField:@"X-REQINFO"];
        
        NSURL *fileUrl = [NSURL fileURLWithPath:filePath];
        NSURLSessionUploadTask *task = [[NSURLSession sharedSession] uploadTaskWithRequest:req fromFile:fileUrl completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error) {
            if(resultBlock){
                dispatch_async(dispatch_get_main_queue(), ^{
                    resultBlock(error);
                });
            }
        }];
        [task resume];
    });
}

@implementation QNLogCtDeviceInfo

- (instancetype _Nonnull )initWithUserID:(NSString *_Nullable)userID
                                deviceID:(NSString *_Nullable)deviceID{
    return [self initWithUserID:userID deviceID:deviceID extra:nil provider:nil channel:nil];
}

- (instancetype _Nonnull )initWithUserID:(NSString *_Nullable)userID
                                deviceID:(NSString *_Nullable)deviceID
                                   extra:(NSString *_Nullable)extra
                                provider:(NSString *_Nullable)provider
                                 channel:(NSString *_Nullable)channel{
    if (self = [super init]) {
        _extra = extra;
        _provider = provider;
        _channel = channel;
        _userID = userID;
        _deviceID = deviceID;
    }

    return self;
}

void QNLogCtSetDeviceInfo(QNLogCtDeviceInfo* _Nonnull info){
    __info = info;
}

@end

void QNLogCtSend(NSUInteger type, NSString *_Nonnull log) {
    [[LoganWrapper instance] sendLog:log logType:type];
}

void QNLogCtStartSender() {
    
}

@implementation LogCtError

static NSString *const LogCtErrorDomain = @"logct.error";

+ (NSError *)GenerateNSError:(LogCtErrorCode)code
                 description:(NSString *)format, ... {
  va_list args;
  va_start(args, format);
  NSString *description =
      [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  NSMutableDictionary *userInfo = [NSMutableDictionary new];
  [userInfo setValue:description forKey:NSLocalizedDescriptionKey];
  return [NSError errorWithDomain:LogCtErrorDomain code:code userInfo:userInfo];
}

@end
