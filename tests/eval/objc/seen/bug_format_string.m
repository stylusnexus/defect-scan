#import <Foundation/Foundation.h>

void logIt(NSString *userInput) {
    NSLog(userInput);   // cat#3: user-controlled format string (CWE-134)
}
