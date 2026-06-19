#import <Foundation/Foundation.h>

@interface Cache : NSObject
- (void)add:(id)x;
@end

@implementation Cache {
    NSMutableArray *_items;
}
- (void)add:(id)x {
    @synchronized (self) {
        [_items addObject:x];   // safe: mutation guarded by a lock
    }
}
@end
