#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface DCUniConvert : NSObject

+ (BOOL)BOOL:(id)value;
+ (CGFloat)CGFloat:(id)value;
+ (CGFloat)flexCGFloat:(id)value;
+ (NSUInteger)NSUInteger:(id)value;
+ (NSInteger)NSInteger:(id)value;
+ (NSString *)NSString:(id)value;
+ (UIColor *)UIColor:(id)value;
+ (CGColorRef)CGColor:(id)value;
+ (NSString *)HexWithColor:(UIColor *)color;
+ (NSString *)dataToBase64String:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
