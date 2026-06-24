#import "RokidGlassModule.h"
#import "DCUniConvert.h"

#if __has_include("RokidCXRLUniPlugin-Swift.h")
#import "RokidCXRLUniPlugin-Swift.h"
#define ROKID_GLASS_SWIFT_HEADER_AVAILABLE 1
#elif __has_include(<RokidCXRLUniPlugin/RokidCXRLUniPlugin-Swift.h>)
#import <RokidCXRLUniPlugin/RokidCXRLUniPlugin-Swift.h>
#define ROKID_GLASS_SWIFT_HEADER_AVAILABLE 1
#elif __has_include("RokidGlass-Swift.h")
#import "RokidGlass-Swift.h"
#define ROKID_GLASS_SWIFT_HEADER_AVAILABLE 1
#elif __has_include("Rokid_Glass-Swift.h")
#import "Rokid_Glass-Swift.h"
#define ROKID_GLASS_SWIFT_HEADER_AVAILABLE 1
#elif __has_include(<RokidGlass/RokidGlass-Swift.h>)
#import <RokidGlass/RokidGlass-Swift.h>
#define ROKID_GLASS_SWIFT_HEADER_AVAILABLE 1
#endif

#ifndef ROKID_GLASS_SWIFT_HEADER_AVAILABLE
@interface RokidGlassBridge : NSObject
+ (RokidGlassBridge *)sharedInstance;
- (void)setEventCallback:(UniModuleKeepAliveCallback)callback;
- (void)initSDK:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)checkPermissions:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)requestAuthorization:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)connectCustomView:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)connectCustomApp:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)openCustomView:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)updateCustomView:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)closeCustomView:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)queryApp:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)openApp:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)stopApp:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)changeAudioSceneId:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)startAudioRecord:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)stopAudioRecord:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)startPhoneAudioRecord:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)stopPhoneAudioRecord:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)isBluetoothConnected:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)requestSystemInfo:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)requestGlassDeviceInfo:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)getState:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)handleOpenURL:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
- (void)releaseSession:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback;
@end
#endif

@interface RokidCXRLModule : RokidGlassModule
@end

@implementation RokidCXRLModule
@end

@interface RokidGlassModule ()
@property (nonatomic, strong) RokidGlassBridge *bridge;
@end

@implementation RokidGlassModule

UNI_EXPORT_METHOD(@selector(setEventCallback:))
UNI_EXPORT_METHOD(@selector(initSDK:callback:))
UNI_EXPORT_METHOD(@selector(checkPermissions:callback:))
UNI_EXPORT_METHOD(@selector(requestAuthorization:callback:))
UNI_EXPORT_METHOD(@selector(connectCustomView:callback:))
UNI_EXPORT_METHOD(@selector(connectCustomApp:callback:))
UNI_EXPORT_METHOD(@selector(openCustomView:callback:))
UNI_EXPORT_METHOD(@selector(updateCustomView:callback:))
UNI_EXPORT_METHOD(@selector(closeCustomView:callback:))
UNI_EXPORT_METHOD(@selector(queryApp:callback:))
UNI_EXPORT_METHOD(@selector(openApp:callback:))
UNI_EXPORT_METHOD(@selector(stopApp:callback:))
UNI_EXPORT_METHOD(@selector(changeAudioSceneId:callback:))
UNI_EXPORT_METHOD(@selector(startAudioRecord:callback:))
UNI_EXPORT_METHOD(@selector(stopAudioRecord:callback:))
UNI_EXPORT_METHOD(@selector(startPhoneAudioRecord:callback:))
UNI_EXPORT_METHOD(@selector(stopPhoneAudioRecord:callback:))
UNI_EXPORT_METHOD(@selector(startAudio:callback:))
UNI_EXPORT_METHOD(@selector(stopAudio:callback:))
UNI_EXPORT_METHOD(@selector(isBluetoothConnected:callback:))
UNI_EXPORT_METHOD(@selector(requestSystemInfo:callback:))
UNI_EXPORT_METHOD(@selector(requestGlassDeviceInfo:callback:))
UNI_EXPORT_METHOD(@selector(getState:callback:))
UNI_EXPORT_METHOD(@selector(handleOpenURL:callback:))
UNI_EXPORT_METHOD(@selector(release:callback:))
UNI_EXPORT_METHOD(@selector(prepareTeleprompter:callback:))
UNI_EXPORT_METHOD(@selector(updateTeleprompter:callback:))
UNI_EXPORT_METHOD(@selector(closeTeleprompter:callback:))

- (RokidGlassBridge *)bridge {
    if (!_bridge) {
        _bridge = [RokidGlassBridge sharedInstance];
    }
    return _bridge;
}

- (void)setEventCallback:(UniModuleKeepAliveCallback)callback {
    [self.bridge setEventCallback:callback];
}

- (void)initSDK:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge initSDK:options callback:callback];
}

- (void)checkPermissions:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge checkPermissions:options callback:callback];
}

- (void)requestAuthorization:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge requestAuthorization:options callback:callback];
}

- (void)connectCustomView:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge connectCustomView:options callback:callback];
}

- (void)connectCustomApp:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge connectCustomApp:options callback:callback];
}

- (void)openCustomView:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge openCustomView:options callback:callback];
}

- (void)updateCustomView:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge updateCustomView:options callback:callback];
}

- (void)closeCustomView:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge closeCustomView:options callback:callback];
}

- (void)queryApp:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge queryApp:options callback:callback];
}

- (void)openApp:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge openApp:options callback:callback];
}

- (void)stopApp:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge stopApp:options callback:callback];
}

- (void)changeAudioSceneId:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge changeAudioSceneId:options callback:callback];
}

- (void)startAudioRecord:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge startAudioRecord:options callback:callback];
}

- (void)stopAudioRecord:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge stopAudioRecord:options callback:callback];
}

- (void)startPhoneAudioRecord:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge startPhoneAudioRecord:options callback:callback];
}

- (void)stopPhoneAudioRecord:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge stopPhoneAudioRecord:options callback:callback];
}

- (void)startAudio:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge startAudioRecord:options callback:callback];
}

- (void)stopAudio:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge stopAudioRecord:options callback:callback];
}

- (void)isBluetoothConnected:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge isBluetoothConnected:options callback:callback];
}

- (void)requestSystemInfo:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge requestSystemInfo:options callback:callback];
}

- (void)requestGlassDeviceInfo:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge requestGlassDeviceInfo:options callback:callback];
}

- (void)getState:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge getState:options callback:callback];
}

- (void)handleOpenURL:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge handleOpenURL:options callback:callback];
}

- (void)release:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    [self.bridge releaseSession:options callback:callback];
}

- (void)prepareTeleprompter:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    NSMutableDictionary *params = [[self rk_safeDictionary:options] mutableCopy];
    params[@"sessionType"] = @"customView";
    params[@"mode"] = @"customView";
    params[@"title"] = [self rk_stringValue:params[@"title"] defaultValue:@"AI提词器"];
    params[@"text"] = [self rk_stringValue:params[@"text"] defaultValue:@"眼镜提词器已准备"];

    NSString *providedViewJson = [self rk_stringValue:params[@"viewJson"] defaultValue:@""];
    if (providedViewJson.length == 0) {
        providedViewJson = [self rk_stringValue:params[@"view"] defaultValue:[self rk_teleprompterViewJsonWithTitle:params[@"title"] text:params[@"text"]]];
        params[@"viewJson"] = providedViewJson;
        params[@"view"] = providedViewJson;
        params[@"json"] = providedViewJson;
    }

    [self.bridge initSDK:params callback:^(id initResult, BOOL keepAlive) {
        if (![self rk_resultOK:initResult]) {
            [self rk_invoke:callback result:initResult keepAlive:NO];
            return;
        }

        [self.bridge requestAuthorization:params callback:^(id authResult, BOOL keepAlive) {
            if (![self rk_resultOK:authResult]) {
                [self rk_invoke:callback result:authResult keepAlive:NO];
                return;
            }

            [self.bridge connectCustomView:params callback:^(id connectResult, BOOL keepAlive) {
                if (![self rk_resultOK:connectResult]) {
                    [self rk_invoke:callback result:connectResult keepAlive:NO];
                    return;
                }

                [self.bridge openCustomView:params callback:^(id openResult, BOOL keepAlive) {
                    [self rk_invoke:callback result:[self rk_resultByAddingTeleprompterEvent:@"teleprompterReady" toResult:openResult] keepAlive:NO];
                }];
            }];
        }];
    }];
}

- (void)updateTeleprompter:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    NSMutableDictionary *params = [[self rk_safeDictionary:options] mutableCopy];
    NSString *text = [self rk_stringValue:params[@"text"] defaultValue:@""];
    NSString *updateJson = [self rk_stringValue:params[@"updateJson"] defaultValue:@""];
    if (updateJson.length == 0) {
        updateJson = [self rk_teleprompterUpdateJsonWithText:text];
        params[@"updateJson"] = updateJson;
        params[@"updates"] = updateJson;
        params[@"json"] = updateJson;
        params[@"view"] = updateJson;
    }

    [self.bridge updateCustomView:params callback:^(id result, BOOL keepAlive) {
        [self rk_invoke:callback result:[self rk_resultByAddingTeleprompterEvent:@"teleprompterUpdated" toResult:result] keepAlive:NO];
    }];
}

- (void)closeTeleprompter:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    NSMutableDictionary *params = [[self rk_safeDictionary:options] mutableCopy];
    NSString *viewJson = [self rk_stringValue:params[@"viewJson"] defaultValue:@""];
    if (viewJson.length == 0) {
        viewJson = [self rk_teleprompterViewJsonWithTitle:@"AI提词器" text:@""];
        params[@"viewJson"] = viewJson;
        params[@"view"] = viewJson;
        params[@"json"] = viewJson;
    }
    [self.bridge closeCustomView:params callback:^(id result, BOOL keepAlive) {
        [self rk_invoke:callback result:[self rk_resultByAddingTeleprompterEvent:@"teleprompterClosed" toResult:result] keepAlive:NO];
    }];
}

- (NSDictionary *)rk_safeDictionary:(NSDictionary *)options {
    return [options isKindOfClass:NSDictionary.class] ? options : @{};
}

- (NSString *)rk_stringValue:(id)value defaultValue:(NSString *)defaultValue {
    if ([value isKindOfClass:NSString.class]) {
        return value;
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        return [value stringValue];
    }
    return defaultValue ?: @"";
}

- (BOOL)rk_resultOK:(id)result {
    if (![result isKindOfClass:NSDictionary.class]) {
        return YES;
    }
    NSDictionary *dict = (NSDictionary *)result;
    id code = dict[@"code"];
    if (code && [code respondsToSelector:@selector(integerValue)] && [code integerValue] != 0) {
        return NO;
    }
    id success = dict[@"success"];
    if (success && [success respondsToSelector:@selector(boolValue)] && ![success boolValue]) {
        return NO;
    }
    NSDictionary *data = [dict[@"data"] isKindOfClass:NSDictionary.class] ? dict[@"data"] : nil;
    id dataSuccess = data[@"success"];
    if (dataSuccess && [dataSuccess respondsToSelector:@selector(boolValue)] && ![dataSuccess boolValue]) {
        return NO;
    }
    return YES;
}

- (id)rk_resultByAddingTeleprompterEvent:(NSString *)event toResult:(id)result {
    if (![result isKindOfClass:NSDictionary.class]) {
        return @{
            @"code": @0,
            @"data": @{
                @"event": event ?: @"teleprompter",
                @"teleprompter": @YES
            }
        };
    }

    NSMutableDictionary *dict = [(NSDictionary *)result mutableCopy];
    NSMutableDictionary *data = nil;
    if ([dict[@"data"] isKindOfClass:NSDictionary.class]) {
        data = [dict[@"data"] mutableCopy];
    } else {
        data = [NSMutableDictionary dictionary];
    }
    data[@"event"] = event ?: @"teleprompter";
    data[@"teleprompter"] = @YES;
    dict[@"data"] = data;
    if (!dict[@"code"]) {
        dict[@"code"] = @0;
    }
    return dict;
}

- (void)rk_invoke:(UniModuleKeepAliveCallback)callback result:(id)result keepAlive:(BOOL)keepAlive {
    if (callback) {
        callback(result, keepAlive);
    }
}

- (NSString *)rk_teleprompterViewJsonWithTitle:(NSString *)title text:(NSString *)text {
    NSDictionary *view = @{
        @"type": @"LinearLayout",
        @"props": @{
            @"id": @"root",
            @"layout_width": @"match_parent",
            @"layout_height": @"match_parent",
            @"orientation": @"vertical",
            @"gravity": @"center_vertical",
            @"paddingTop": @"140dp",
            @"paddingBottom": @"100dp",
            @"backgroundColor": @"#FF000000"
        },
        @"children": @[
            @{
                @"type": @"TextView",
                @"props": @{
                    @"id": @"tv_title",
                    @"layout_width": @"wrap_content",
                    @"layout_height": @"wrap_content",
                    @"text": title ?: @"AI提词器",
                    @"textColor": @"#FF00FF00",
                    @"textSize": @"16sp",
                    @"textStyle": @"bold",
                    @"marginBottom": @"20dp",
                    @"paddingStart": @"16dp",
                    @"paddingEnd": @"16dp"
                }
            },
            @{
                @"type": @"TextView",
                @"props": @{
                    @"id": @"textView",
                    @"layout_width": @"wrap_content",
                    @"layout_height": @"wrap_content",
                    @"text": text ?: @"",
                    @"textColor": @"#FF00FF00",
                    @"textSize": @"16sp",
                    @"gravity": @"center",
                    @"paddingStart": @"16dp",
                    @"paddingEnd": @"16dp"
                }
            }
        ]
    };
    return [self rk_jsonString:view fallback:@"{}"];
}

- (NSString *)rk_teleprompterUpdateJsonWithText:(NSString *)text {
    NSArray *updates = @[
        @{
            @"action": @"update",
            @"id": @"textView",
            @"props": @{
                @"text": text ?: @""
            }
        }
    ];
    return [self rk_jsonString:updates fallback:@"[]"];
}

- (NSString *)rk_jsonString:(id)object fallback:(NSString *)fallback {
    if (![NSJSONSerialization isValidJSONObject:object]) {
        return fallback;
    }
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (error || !data) {
        return fallback;
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: fallback;
}

@end
