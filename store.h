#import <Cocoa/Cocoa.h>

extern const int kDefaultAssignmentCap;
extern const int kMinAssignmentCap;
extern const int kMaxAssignmentCap;
extern const int kCacheAssignmentCap;

NSString *SchedulePath(void);
NSString *CachePath(void);
int ClampCap(int n);

NSISO8601DateFormatter *ISOFormatter(void);
BOOL WriteCache(NSArray *items);
NSDictionary *LoadCache(void);
NSArray *LoadUpcoming(void);
NSString *CacheAgeLabel(void);
NSDate *ParseISO(NSString *s);
NSString *DueLabel(NSCalendar *cal, NSDate *due);
NSString *Clip(NSString *s, NSUInteger n);
