#import <Cocoa/Cocoa.h>

NSDate *IcsDate(NSString *tzid, NSString *value);
NSDate *EndOfDay(NSDate *date);
NSString *FirstGroup(NSString *text, NSString *pattern);

NSArray *cb_ics_items(NSString *text, NSString *canvasHome);
NSArray *cb_ics_window(NSArray *items, NSDate *now, int backDays,
                       int aheadDays, NSUInteger cap);
NSDictionary *cb_ics_classes(NSString *text);

NSString *ClockText(NSDate *date);
int YMD(NSDate *date);
int WeekdayIndex(NSDate *date);
