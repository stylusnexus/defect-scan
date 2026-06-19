#import <Foundation/Foundation.h>

NSString *firstName(NSArray *names) {
    // cat#1: unchecked objectAtIndex: throws NSRangeException on an empty array.
    return [names objectAtIndex:0];
}
