#import <Foundation/Foundation.h>

@interface Cache : NSObject
- (void)add:(id)x;
@end

@implementation Cache {
    NSMutableArray *_items;
}
- (void)add:(id)x {
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        [_items addObject:x];   // cat#5: NSMutableArray mutated off a concurrent queue, unsynchronized
    });
}
@end
