#import <Cocoa/Cocoa.h>

extern const int kDefaultAssignmentCap;
extern const int kMinAssignmentCap;
extern const int kMaxAssignmentCap;
extern const int kCacheAssignmentCap;

NSString *SchedulePath(void);
NSString *CachePath(void);
int ClampCap(int n);
void SplitAssignmentCap(NSUInteger todo, NSUInteger done, NSUInteger cap,
                        NSUInteger *todoShown, NSUInteger *doneShown);
NSString *HHMMshort(int m);

NSISO8601DateFormatter *ISOFormatter(void);
BOOL WriteCache(NSArray *items);
NSArray *LoadUpcoming(void);
NSString *CacheAgeLabel(void);
NSDate *ParseISO(NSString *s);
NSString *DueLabel(NSCalendar *cal, NSDate *due);
NSString *Clip(NSString *s, NSUInteger n);

NSString *DonePath(void);
NSString *DoneKey(NSDictionary *item);
NSDictionary *PruneDone(NSDictionary *map, NSDate *now);
NSDictionary *LoadDone(void);
void SetDone(NSDictionary *item, BOOL done);
NSArray *DoneEntries(void);
void RestoreDone(NSArray *keys);
