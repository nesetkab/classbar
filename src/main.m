#import <Cocoa/Cocoa.h>
#import "app.h"

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        static ClassBar *delegate;
        delegate = [[ClassBar alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
