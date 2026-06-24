#import <Foundation/Foundation.h>
#import "DCUniDefine.h"

NS_ASSUME_NONNULL_BEGIN

@interface DCUniSDKInstance : NSObject
@end

@interface DCUniModule : NSObject

@property (nonatomic, strong) dispatch_queue_t uniExecuteQueue;
@property (nonatomic, strong) NSThread *uniExecuteThread;
@property (nonatomic, weak) DCUniSDKInstance *uniInstance;

@end

NS_ASSUME_NONNULL_END
