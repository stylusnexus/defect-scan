#import <Foundation/Foundation.h>

@interface Worker : NSObject
@property (copy) void (^handler)(void);
- (void)work;
@end

@implementation Worker
- (void)setup {
    __weak typeof(self) weakSelf = self;
    self.handler = ^{ [weakSelf work]; };   // NEAR-MISS: __weak breaks the cycle
}
@end
