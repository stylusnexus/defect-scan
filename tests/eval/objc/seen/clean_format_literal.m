#import <Foundation/Foundation.h>

void logIt(NSString *userInput) {
    NSLog(@"%@", userInput);   // safe: literal format, user data is an argument
}
