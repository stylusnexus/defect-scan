#import <Foundation/Foundation.h>

void parse(NSData *d) {
    NSError *error = nil;
    [NSJSONSerialization JSONObjectWithData:d options:0 error:&error];
}
