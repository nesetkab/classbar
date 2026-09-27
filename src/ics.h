#import <Cocoa/Cocoa.h>

NSArray *cb_ics_items(NSString *text, NSString *canvasHome);
NSArray *cb_ics_window(NSArray *items, NSDate *now, int backDays,
                       int aheadDays, NSUInteger cap);
NSDictionary *cb_ics_classes(NSString *text);

int YMD(NSDate *date);
