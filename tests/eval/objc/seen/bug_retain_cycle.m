#import <Foundation/Foundation.h>

@interface Worker : NSObject
@property (copy) void (^handler)(void);
- (void)work;
@end

@implementation Worker
- (void)setup {
    self.handler = ^{ [self work]; };   // cat#4: block retains strong self -> cycle
}
@end
