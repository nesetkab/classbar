#import <Cocoa/Cocoa.h>
#import "store.h"

NSString *SchedulePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Application Support/classbar/schedule.json"];
}

NSString *CachePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Caches/classbar/assignments.json"];
}

const int kDefaultAssignmentCap = 25;
const int kMinAssignmentCap = 1;
const int kMaxAssignmentCap = 100;
const int kCacheAssignmentCap = 200;

int ClampCap(int n) {
    if (n < kMinAssignmentCap) return kMinAssignmentCap;
    if (n > kMaxAssignmentCap) return kMaxAssignmentCap;
    return n;
}

NSString *HHMMshort(int m) {
    int h24 = m / 60, mm = m % 60;
    int h = h24 % 12; if (h == 0) h = 12;
    return [NSString stringWithFormat:@"%d:%02d%s", h, mm, h24 >= 12 ? "p" : "a"];
}

NSISO8601DateFormatter *ISOFormatter(void) {
    static NSISO8601DateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [[NSISO8601DateFormatter alloc] init]; });
    return f;
}

BOOL WriteCache(NSArray *items) {
    NSDictionary *root = @{ @"generated": [ISOFormatter() stringFromDate:[NSDate date]],
                            @"items": items ?: @[] };
    NSData *d = [NSJSONSerialization dataWithJSONObject:root
                                                options:NSJSONWritingPrettyPrinted
                                                  error:NULL];
    if (!d) return NO;
    [[NSFileManager defaultManager]
        createDirectoryAtPath:[CachePath() stringByDeletingLastPathComponent]
      withIntermediateDirectories:YES attributes:nil error:NULL];
    return [d writeToFile:CachePath() atomically:YES];
}

static NSDictionary *LoadCache(void) {
    NSData *d = [NSData dataWithContentsOfFile:CachePath()];
    if (!d) return nil;
    id root = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    return [root isKindOfClass:[NSDictionary class]] ? root : nil;
}

NSArray *LoadUpcoming(void) {
    id items = LoadCache()[@"items"];
    return [items isKindOfClass:[NSArray class]] ? items : nil;
}

NSString *CacheAgeLabel(void) {
    NSDictionary *c = LoadCache();
    if (!c) return @"no data";
    NSDate *gen = nil;
    id g = c[@"generated"];
    if ([g isKindOfClass:[NSString class]]) gen = [ISOFormatter() dateFromString:g];
    if (!gen) return @"";
    NSTimeInterval age = -[gen timeIntervalSinceNow];
    if (age < 5400) return @"";
    if (age < 86400) return [NSString stringWithFormat:@"%dh ago", (int)(age / 3600)];
    return [NSString stringWithFormat:@"%dd ago", (int)(age / 86400)];
}

NSDate *ParseISO(NSString *s) {
    static NSISO8601DateFormatter *plain, *fractional;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        plain = [[NSISO8601DateFormatter alloc] init];
        fractional = [[NSISO8601DateFormatter alloc] init];
        fractional.formatOptions = NSISO8601DateFormatWithInternetDateTime
                                 | NSISO8601DateFormatWithFractionalSeconds;
    });
    if (![s isKindOfClass:[NSString class]]) return nil;
    NSDate *d = [plain dateFromString:s];
    return d ?: [fractional dateFromString:s];
}

NSString *DueLabel(NSCalendar *cal, NSDate *due) {
    if (!due) return @"";
    NSDate *a, *b;
    [cal rangeOfUnit:NSCalendarUnitDay startDate:&a interval:NULL forDate:[NSDate date]];
    [cal rangeOfUnit:NSCalendarUnitDay startDate:&b interval:NULL forDate:due];
    NSInteger days = [[cal components:NSCalendarUnitDay fromDate:a toDate:b options:0] day];

    NSDateComponents *tc = [cal components:(NSCalendarUnitHour|NSCalendarUnitMinute)
                                  fromDate:due];
    NSString *clock = HHMMshort((int)tc.hour * 60 + (int)tc.minute);

    if (days < 0)  return @"late";
    if (days == 0) return [NSString stringWithFormat:@"today %@", clock];
    if (days == 1) return [NSString stringWithFormat:@"tmr %@", clock];
    if (days < 7)  return [NSString stringWithFormat:@"%ldd", (long)days];

    static const char *mon[] = {"Jan","Feb","Mar","Apr","May","Jun",
                                "Jul","Aug","Sep","Oct","Nov","Dec"};
    NSDateComponents *c = [cal components:(NSCalendarUnitMonth|NSCalendarUnitDay) fromDate:due];
    return [NSString stringWithFormat:@"%s %ld", mon[c.month - 1], (long)c.day];
}

NSString *Clip(NSString *s, NSUInteger n) {
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length <= n) return s;
    return [[s substringToIndex:n - 1] stringByAppendingString:@"…"];
}

NSString *DonePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Application Support/classbar/done.json"];
}

NSString *DoneKey(NSDictionary *item) {
    NSString *url = item[@"url"];
    if ([url isKindOfClass:[NSString class]] && url.length) return url;
    NSString *name = [item[@"name"] isKindOfClass:[NSString class]] ? item[@"name"] : @"";
    NSString *due = [item[@"due"] isKindOfClass:[NSString class]] ? item[@"due"] : @"";
    return [NSString stringWithFormat:@"%@|%@", name, due];
}

NSDictionary *PruneDone(NSDictionary *map, NSDate *now) {
    NSMutableDictionary *kept = [NSMutableDictionary dictionary];
    for (NSString *key in map) {
        id stamp = map[key];
        if (![stamp isKindOfClass:[NSString class]]) continue;
        NSDate *due = ParseISO(stamp);
        if (due && [due compare:now] == NSOrderedAscending) continue;
        kept[key] = stamp;
    }
    return kept;
}

static NSMutableDictionary *ReadDone(void) {
    NSData *d = [NSData dataWithContentsOfFile:DonePath()];
    id root = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    if (![root isKindOfClass:[NSDictionary class]]) return [NSMutableDictionary dictionary];
    return [root mutableCopy];
}

static void WriteDone(NSDictionary *map) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:map
                                                options:NSJSONWritingPrettyPrinted
                                                  error:NULL];
    if (!d) return;
    [[NSFileManager defaultManager]
        createDirectoryAtPath:[DonePath() stringByDeletingLastPathComponent]
      withIntermediateDirectories:YES attributes:nil error:NULL];
    [d writeToFile:DonePath() atomically:YES];
}

NSDictionary *LoadDone(void) {
    NSDictionary *map = ReadDone();
    NSDictionary *kept = PruneDone(map, [NSDate date]);
    if (kept.count != map.count) WriteDone(kept);
    return kept;
}

void SetDone(NSDictionary *item, BOOL done) {
    NSMutableDictionary *map = ReadDone();
    NSString *key = DoneKey(item);
    if (done) {
        id due = item[@"due"];
        map[key] = [due isKindOfClass:[NSString class]] ? due : @"";
    } else {
        [map removeObjectForKey:key];
    }
    WriteDone(map);
}
