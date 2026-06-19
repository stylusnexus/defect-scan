#import <Foundation/Foundation.h>

NSString *firstName(NSArray *names) {
    return [names objectAtIndex:0];   // cat#1: NSRangeException on an empty array
}
