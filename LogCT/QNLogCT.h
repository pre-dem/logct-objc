//
//  QNLogCT.h
//  Logan-iOS
//
//  Created by 白龙 on 2020/4/3.
//  Copyright © 2020 jiangteng. All rights reserved.
//

#ifndef QNLogCT_h
#define QNLogCT_h

#import <Foundation/Foundation.h>

#define SDK_VERSION "0.0.1"

typedef NS_ENUM(NSInteger, LogCtCategory) {
    kLogCtCommonLog = 1,
    kLogCtNetworkLog = 2,
    kLogCtCrashLog = 3,
    kLogCtErrorLog = 4,
};

/**
 Log Collector初始化
 
 @param host 服务器域名
 @param appKey 加密key
 @param max_file_size  日志文件最大大小，超过该大小后日志将不再被写入，单位：byte。
 */
extern NSError * _Nullable QNLogCtInit(NSString* _Nonnull server, NSString* _Nonnull appKey, uint64_t maxFileSize);

/**
 *    设备信息集合，此类初始化后sdk上传使用时 不会对此进行改变；如果参数没有变化以及没有使用依赖，可以重复使用。
 */
@interface QNLogCtDeviceInfo : NSObject

/**
 *    user ID
 */
@property (copy, nonatomic, readonly) NSString * _Nullable userID;

/**
 *    device ID
 */
@property (copy, nonatomic, readonly) NSString * _Nullable deviceID;

/**
 *    userID 来源，比如wechat, weibo
 */
@property (copy, nonatomic, readonly) NSString * _Nullable provider;

/**
 *    app 下载渠道
 */
@property (copy, nonatomic, readonly) NSString * _Nullable channel;

/**
 *    额外的信息，如果有多个自定义字段，需要处理成一个字符串，之后自行解析
 */
@property (copy, nonatomic, readonly) NSString * _Nullable extra;

/**
 *    可选参数的初始化方法
 *
 *    @param userID     user ID
 *    @param deviceID     device ID
 *
 *    @return 可选参数类实例
 */
- (instancetype _Nonnull )initWithUserID:(NSString *_Nullable)userID
                                deviceID:(NSString *_Nullable)deviceID;

/**
 *    可选参数的初始化方法
 *
 *    @param userID user ID
 *    @param deviceID 设备 ID
 *    @param extra     自定义信息
 *    @param provider     用户账号来源
 *    @param channel       下载渠道
 *
 *    @return 可选参数类实例
 */
- (instancetype _Nonnull )initWithUserID:(NSString *_Nullable)userID
                                deviceID:(NSString *_Nullable)deviceID
                                   extra:(NSString *_Nullable)extra
                                provider:(NSString *_Nullable)provider
                                 channel:(NSString *_Nullable)channel;
@end

/**
Log Collector 设定设备信息

@param info  设备信息
*/
extern void QNLogCtSetDeviceInfo(QNLogCtDeviceInfo* _Nonnull info);

/**
Log Collector 启动后台实时发送

@param info  设备信息
*/
extern void QNLogCtStartSender();

/**
 实时发送一条日志
 
 @param type 日志类型
 @param log  日志字符串
 
 @brief
 用例：
 QNLogCtSend(1, @"this is a test");
 */
extern void QNLogCtSend(NSUInteger type, NSString *_Nonnull log);

/**
 存储一条日志，将来通过Upload上传
 
 @param type 日志类型
 @param log  日志字符串
 
 @brief
 用例：
 QNLogCtSave(1, @"this is a test");
 */
extern void QNLogCtSave(NSUInteger type, NSString *_Nonnull log);



typedef void (^QNLogCtUploadResultBlock)(NSError *_Nullable error);

/**
 上传指定日期的日志
 
 @param date 日志日期，
 @param resultBlock 服务器返回结果
 */
extern void QNLogCtUpload(NSDate * _Nonnull date, QNLogCtUploadResultBlock _Nullable resultBlock);

/**
是否要输出log 到ASL

@param flag false 表示关闭，默认为关闭
*/
extern void QNLogCtDumpOutput(BOOL b);

/**
 设置本地保存最大文件天数

 @param max_reserved_date 超过该文件天数的文件会被删除，默认7天
 */
extern void QNLogCtSetMaxReservedDays(int max_reserved_days);

/**
 返回本地所有文件名及大小(单位byte)
 
 @return @{@"2018-11-21":@"110"}
 */
extern NSDictionary *_Nullable QNLogCtAllFilesInfo(void);

/**
 清除本地所有日志
 */
extern void QNLogCtClearAllLogs(void);

/**
 启动策略检查服务，判断是否需要上传日志
 */

extern void QNLogCtStartUploadChecker();


typedef NS_ENUM(NSInteger, LogCtErrorCode) {
  kLogCtErrorCodeUnknown = -1,
  kLogCtErrorCodeInvalidServiceDomain = 100,
  kLogCtErrorCodeInvalidAppKey = 101,
  kLogCtErrorCodeInternalError = 103,
  kLogCtErrorCodeNotInitedError = 104,
  kLogCtErrorCodeInvalidTransactionIDError = 105,
  kLogCtErrorCodeCompressionError = 106,
  kLogCtErrorCodeNoLogError = 107,
};

@interface LogCtError : NSObject

+ (NSError *_Nonnull)GenerateNSError:(LogCtErrorCode)code
                         description:(NSString *_Nonnull)format, ...;
@end

#endif /* QNLogCT_h */
