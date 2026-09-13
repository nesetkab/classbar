#import <Cocoa/Cocoa.h>
#import "schedule.h"

@interface ClassBar : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (strong) Schedule *schedule;
- (void)menuNeedsUpdate:(NSMenu *)menu;
- (void)refreshNow;
@end
