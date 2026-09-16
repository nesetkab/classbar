#import <Cocoa/Cocoa.h>
#import "schedule.h"

NSColor *RailForCourse(Schedule *s, NSString *course);

@interface ClassBar : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (strong) Schedule *schedule;
- (void)menuNeedsUpdate:(NSMenu *)menu;
- (void)refreshNow;
@end
