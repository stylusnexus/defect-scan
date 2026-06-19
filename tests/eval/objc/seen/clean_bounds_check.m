#import <Foundation/Foundation.h>

NSString *firstNameOrNil(NSArray *names) {
    if (names.count == 0) { return nil; }
    return [names objectAtIndex:0];   // safe: bounds-checked above
}
