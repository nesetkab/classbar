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
@property (assign) BOOL hideDone;
@property (copy)   NSString *loadError;
+ (instancetype)loadFromDisk;
+ (instancetype)loadFromDictionary:(NSDictionary *)root;
@end

int ParseClock(NSString *s);

NSString *TipText(NSString *heading, NSArray *lines);
NSString *TipJoin(NSArray *parts);

NSArray *cb_series(Schedule *s, int ymd, int mins, int day, int count);

NSString *DaysToText(NSArray *days);
NSArray *TextToDays(NSString *text);
