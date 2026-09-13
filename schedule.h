#import <Cocoa/Cocoa.h>

extern const char * const kDayName[7];

@interface Schedule : NSObject
@property (strong) NSArray *byDay;
@property (copy)   NSString *canvasHome;
@property (assign) int termStart;
@property (assign) int termEnd;
@property (copy)   NSString *beforeLabel;
@property (copy)   NSString *canvasFeed;
@property (assign) int assignmentCap;
@property (copy)   NSString *loadError;
+ (instancetype)loadFromDisk;
@end

int ParseClock(NSString *s);
NSString *DUR(int m);
NSString *HHMMshort(int m);

NSString *TipText(NSString *heading, NSArray *lines);
NSString *TipJoin(NSArray *parts);
NSString *TipClassLine(NSDictionary *c);

NSArray *cb_series(Schedule *s, int ymd, int mins, int day, int count);

NSArray *DayTokens(void);
NSString *DaysToText(NSArray *days);
NSArray *TextToDays(NSString *text);
