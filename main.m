#import <Cocoa/Cocoa.h>
#import <objc/message.h>

static NSString *SchedulePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Application Support/classbar/schedule.json"];
}

static NSString *CachePath(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
            @"Library/Caches/classbar/upcoming.json"];
}

static int ParseClock(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return -1;
    NSArray *parts = [s componentsSeparatedByString:@":"];
    if (parts.count != 2) return -1;
    int h = [parts[0] intValue], m = [parts[1] intValue];
    if (h < 0 || h > 23 || m < 0 || m > 59) return -1;
    return h * 60 + m;
}

@interface Schedule : NSObject
@property (strong) NSArray *byDay;
@property (copy)   NSString *canvasHome;
@property (assign) int termStart;
@property (assign) int termEnd;
@property (copy)   NSString *beforeLabel;
@property (copy)   NSString *refreshAgent;
@property (copy)   NSString *loadError;
@end

@implementation Schedule

+ (instancetype)loadFromDisk {
    Schedule *s = [[Schedule alloc] init];
    s.canvasHome = @"https://canvas.instructure.com/";
    s.termStart = 0;
    s.termEnd = 99999999;
    s.beforeLabel = @"Term hasn't started";

    NSData *d = [NSData dataWithContentsOfFile:SchedulePath()];
    if (!d) {
        s.loadError = @"No schedule.json";
        s.byDay = @[@[], @[], @[], @[], @[], @[], @[]];
        return s;
    }
    NSError *err = nil;
    id root = [NSJSONSerialization JSONObjectWithData:d options:0 error:&err];
    if (![root isKindOfClass:[NSDictionary class]]) {
        s.loadError = err ? @"schedule.json is not valid JSON" : @"schedule.json is malformed";
        s.byDay = @[@[], @[], @[], @[], @[], @[], @[]];
        return s;
    }

    if ([root[@"canvasHome"] isKindOfClass:[NSString class]]) s.canvasHome = root[@"canvasHome"];
    if ([root[@"refreshAgent"] isKindOfClass:[NSString class]]) s.refreshAgent = root[@"refreshAgent"];
    NSDictionary *term = root[@"term"];
    if ([term isKindOfClass:[NSDictionary class]]) {
        if ([term[@"start"] isKindOfClass:[NSNumber class]]) s.termStart = [term[@"start"] intValue];
        if ([term[@"end"] isKindOfClass:[NSNumber class]]) s.termEnd = [term[@"end"] intValue];
        if ([term[@"beforeLabel"] isKindOfClass:[NSString class]]) s.beforeLabel = term[@"beforeLabel"];
    }

    NSMutableArray *buckets = [NSMutableArray arrayWithCapacity:7];
    for (int i = 0; i < 7; i++) [buckets addObject:[NSMutableArray array]];

    for (NSDictionary *c in root[@"classes"]) {
        if (![c isKindOfClass:[NSDictionary class]]) continue;
        int st = ParseClock(c[@"start"]), en = ParseClock(c[@"end"]);
        if (st < 0 || en < 0 || en <= st) continue;
        if (![c[@"name"] isKindOfClass:[NSString class]]) continue;
        NSDictionary *entry = @{
            @"name": c[@"name"],
            @"code": [c[@"code"] isKindOfClass:[NSString class]] ? c[@"code"] : @"",
            @"room": [c[@"room"] isKindOfClass:[NSString class]] ? c[@"room"] : @"",
            @"start": @(st),
            @"end": @(en),
            @"canvas": [c[@"canvas"] isKindOfClass:[NSString class]] ? c[@"canvas"] : @"",
            @"zoom": [c[@"zoom"] isKindOfClass:[NSString class]] ? c[@"zoom"] : @""
        };
        for (NSNumber *dn in c[@"days"]) {
            if (![dn isKindOfClass:[NSNumber class]]) continue;
            int day = dn.intValue;
            if (day < 0 || day > 6) continue;
            [buckets[day] addObject:entry];
        }
    }

    NSSortDescriptor *byStart = [NSSortDescriptor sortDescriptorWithKey:@"start" ascending:YES];
    for (int i = 0; i < 7; i++) [buckets[i] sortUsingDescriptors:@[byStart]];
    s.byDay = buckets;
    return s;
}

@end

static NSString *HHMM(int m) {
    int h24 = m / 60, mm = m % 60;
    int h = h24 % 12; if (h == 0) h = 12;
    return [NSString stringWithFormat:@"%d:%02d %s", h, mm, h24 >= 12 ? "PM" : "AM"];
}

static NSString *DUR(int m) {
    if (m < 60) return [NSString stringWithFormat:@"%dm", m];
    int h = m / 60, r = m % 60;
    return r ? [NSString stringWithFormat:@"%dh %dm", h, r]
             : [NSString stringWithFormat:@"%dh", h];
}

static const char * const kDayName[7] = {
    "Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"
};

static void cb_resolve(Schedule *s, int ymd, int mins, int day,
                       NSString * __strong *outTitle,
                       NSString * __strong *outWhen,
                       NSString * __strong *outRoom,
                       NSString * __strong *outLink) {
    *outTitle = nil; *outWhen = @""; *outRoom = nil; *outLink = s.canvasHome;

    if (s.loadError) {
        *outTitle = s.loadError;
        *outWhen = @"Add one to Application Support/classbar";
        return;
    }
    if (ymd < s.termStart) { *outTitle = @"Term hasn't started"; *outWhen = s.beforeLabel; return; }
    if (ymd > s.termEnd)   { *outTitle = @"Term is over"; return; }

    NSArray *list = s.byDay[day];
    NSDictionary *hit = nil;
    BOOL inClass = NO;

    for (NSDictionary *c in list) {
        int st = [c[@"start"] intValue], en = [c[@"end"] intValue];
        if (mins >= st && mins < en) { hit = c; inClass = YES; break; }
    }
    if (!hit)
        for (NSDictionary *c in list)
            if ([c[@"start"] intValue] > mins) { hit = c; break; }

    if (hit) {
        int st = [hit[@"start"] intValue], en = [hit[@"end"] intValue];
        *outTitle = hit[@"name"];
        *outRoom  = [hit[@"room"] length] ? hit[@"room"] : nil;
        *outWhen  = inClass
            ? [NSString stringWithFormat:@"ends %@ · %@ left", HHMM(en), DUR(en - mins)]
            : [NSString stringWithFormat:@"%@ · in %@", HHMM(st), DUR(st - mins)];
        if ([hit[@"canvas"] length]) *outLink = hit[@"canvas"];
        return;
    }

    for (int k = 1; k <= 7; k++) {
        int d = (day + k) % 7;
        NSArray *nx = s.byDay[d];
        if (nx.count) {
            NSDictionary *f = nx[0];
            *outTitle = f[@"name"];
            *outRoom  = [f[@"room"] length] ? f[@"room"] : nil;
            *outWhen  = [NSString stringWithFormat:@"%s · %@",
                         kDayName[d], HHMM([f[@"start"] intValue])];
            if ([f[@"canvas"] length]) *outLink = f[@"canvas"];
            return;
        }
    }
    *outTitle = @"No classes";
}

static NSString *HHMMshort(int m) {
    int h24 = m / 60, mm = m % 60;
    int h = h24 % 12; if (h == 0) h = 12;
    return [NSString stringWithFormat:@"%d:%02d%s", h, mm, h24 >= 12 ? "p" : "a"];
}

static NSArray *cb_series(Schedule *s, int ymd, int mins, int day, int count) {
    NSMutableArray *out = [NSMutableArray array];
    if (s.loadError || ymd < s.termStart || ymd > s.termEnd) return out;

    int d = day, after = mins, guard = 0;
    BOOL checkNow = YES;

    while ((int)out.count < count && guard++ < 24) {
        NSDictionary *hit = nil;
        BOOL now = NO;

        if (checkNow) {
            for (NSDictionary *c in s.byDay[d]) {
                int st = [c[@"start"] intValue], en = [c[@"end"] intValue];
                if (mins >= st && mins < en) { hit = c; now = YES; break; }
            }
            checkNow = NO;
        }
        if (!hit)
            for (NSDictionary *c in s.byDay[d])
                if ([c[@"start"] intValue] > after) { hit = c; break; }

        if (hit) {
            int st = [hit[@"start"] intValue], en = [hit[@"end"] intValue];
            NSString *when;
            if (now)
                when = [NSString stringWithFormat:@"%@ • %@ left", HHMMshort(st), DUR(en - mins)];
            else if (d == day)
                when = [NSString stringWithFormat:@"%@ • in %@", HHMMshort(st), DUR(st - mins)];
            else
                when = [NSString stringWithFormat:@"%.3s %@", kDayName[d], HHMMshort(st)];

            [out addObject:@{
                @"title": hit[@"name"],
                @"code": hit[@"code"] ?: @"",
                @"when": when,
                @"room": [hit[@"room"] length] ? hit[@"room"] : @"",
                @"link": [hit[@"canvas"] length] ? hit[@"canvas"] : s.canvasHome,
                @"zoom": hit[@"zoom"] ?: @"",
                @"now": @(now)
            }];
            after = st;
            continue;
        }

        BOOL rolled = NO;
        for (int k = 1; k <= 7 && !rolled; k++) {
            int nd = (d + k) % 7;
            if ([s.byDay[nd] count]) { d = nd; after = -1; rolled = YES; }
        }
        if (!rolled) break;
    }
    return out;
}

static const char *kCatSVG =
    "<?xml version=\"1.0\" encoding=\"utf-8\"?><!-- Uploaded to: SVG Repo, www.svgrepo.com, Generator: SVG Repo Mixer Tools -->"
    "<svg width=\"800px\" height=\"800px\" viewBox=\"0 0 24 24\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">"
    "<path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M12.0196 14.9374C11.7284 14.9374 11.4307 14.9818 11.1784 15.0796C11.0546 15.1275 10.9032 15.2031 10.7699 15.3252C10.6361 15.4479 10.4632 15.6749 10.4632 15.9999C10.4632 16.3249 10.6361 16.5519 10.7699 16.6745C10.9032 16.7967 11.0546 16.8722 11.1784 16.9202C11.4307 17.018 11.7284 17.0624 12.0196 17.0624C12.3109 17.0624 12.6085 17.018 12.8609 16.9202C12.9846 16.8722 13.136 16.7967 13.2693 16.6745C13.4032 16.5519 13.5761 16.3249 13.5761 15.9999C13.5761 15.6749 13.4032 15.4479 13.2693 15.3252C13.136 15.2031 12.9846 15.1275 12.8609 15.0796C12.6085 14.9818 12.3109 14.9374 12.0196 14.9374Z\" fill=\"#1C274C\"/>"
    "<path d=\"M14.0365 12.6464C14.2015 12.38 14.5274 12.0625 15.0163 12.0625C15.5051 12.0625 15.831 12.38 15.996 12.6464C16.1681 12.9243 16.2501 13.2612 16.2501 13.5938C16.2501 13.9263 16.1681 14.2632 15.996 14.5411C15.831 14.8075 15.5051 15.125 15.0163 15.125C14.5274 15.125 14.2015 14.8075 14.0365 14.5411C13.8644 14.2632 13.7824 13.9263 13.7824 13.5938C13.7824 13.2612 13.8644 12.9243 14.0365 12.6464Z\" fill=\"#1C274C\"/>"
    "<path d=\"M9.01634 12.0625C8.52751 12.0625 8.20161 12.38 8.03658 12.6464C7.86445 12.9243 7.78247 13.2612 7.78247 13.5938C7.78247 13.9263 7.86445 14.2632 8.03658 14.5411C8.20161 14.8075 8.52751 15.125 9.01634 15.125C9.50518 15.125 9.83108 14.8075 9.9961 14.5411C10.1682 14.2632 10.2502 13.9263 10.2502 13.5938C10.2502 13.2612 10.1682 12.9243 9.9961 12.6464C9.83108 12.38 9.50518 12.0625 9.01634 12.0625Z\" fill=\"#1C274C\"/>"
    "<path fill-rule=\"evenodd\" clip-rule=\"evenodd\" d=\"M6.09485 4.25C5.48148 4.25 4.77463 4.42871 4.20882 4.91616C3.62226 5.4215 3.27004 6.18781 3.27004 7.1875V9.0625L3.27005 9.06545C3.2712 9.35941 3.3211 9.94757 3.4888 10.4392C3.54365 10.6001 3.63129 10.8134 3.77764 11.0058C3.49364 11.5688 3.35904 12.1495 3.29787 12.7095C3.2468 13.1771 3.24611 13.6679 3.25424 14.1211C2.5932 14.3507 1.90877 14.6349 1.5932 14.8387C1.24524 15.0634 1.14534 15.5277 1.37006 15.8756C1.59478 16.2236 2.05903 16.3235 2.40698 16.0988C2.5234 16.0236 2.86686 15.8664 3.31867 15.6939C3.38755 16.173 3.52716 16.6095 3.7221 17.0063C3.56621 17.1035 3.42847 17.1935 3.31889 17.2652C3.27694 17.2926 3.23912 17.3173 3.20599 17.3387C2.85803 17.5634 2.75813 18.0277 2.98285 18.3756C3.20757 18.7236 3.67182 18.8235 4.01978 18.5988C4.0609 18.5722 4.10473 18.5436 4.15098 18.5134C4.28216 18.4278 4.43287 18.3294 4.59701 18.2288C5.18653 18.8313 5.91865 19.2964 6.67916 19.6462C8.45998 20.4654 10.569 20.75 12.0001 20.75C13.4311 20.75 15.5402 20.4654 17.321 19.6462C18.0815 19.2964 18.8136 18.8313 19.4031 18.2288C19.5673 18.3294 19.718 18.4278 19.8491 18.5134C19.8954 18.5436 19.9392 18.5722 19.9803 18.5988C20.3283 18.8235 20.7925 18.7236 21.0173 18.3756C21.242 18.0277 21.1421 17.5634 20.7941 17.3387C20.761 17.3173 20.7232 17.2926 20.6812 17.2652C20.5716 17.1935 20.4339 17.1035 20.2781 17.0063C20.473 16.6095 20.6127 16.173 20.6815 15.6938C21.1335 15.8663 21.4771 16.0236 21.5936 16.0988C21.9415 16.3235 22.4058 16.2236 22.6305 15.8756C22.8552 15.5277 22.7553 15.0634 22.4074 14.8387C22.0917 14.6349 21.4071 14.3506 20.7459 14.121C20.7541 13.6678 20.7534 13.177 20.7023 12.7095C20.6412 12.1495 20.5065 11.5688 20.2225 11.0058C20.3689 10.8134 20.4565 10.6001 20.5114 10.4392C20.6791 9.94758 20.729 9.35941 20.7301 9.06545L20.7302 9.0625V7.18761C20.7302 6.18792 20.3779 5.42162 19.7914 4.91628C19.2256 4.42882 18.5187 4.25011 17.9054 4.25011C17.4969 4.25011 17.0744 4.40685 16.7337 4.56076C16.3726 4.72392 15.9952 4.9359 15.6558 5.13136C15.5828 5.17339 15.5119 5.21444 15.443 5.25432L15.441 5.25548C15.177 5.4084 14.9427 5.5441 14.7339 5.65167C14.6042 5.7185 14.5035 5.7643 14.4285 5.79206C14.3969 5.80377 14.3767 5.80966 14.3663 5.81242C14.1129 5.81102 13.9514 5.79033 13.7181 5.76044C13.6681 5.75403 13.6147 5.74719 13.5564 5.74003C13.2098 5.69743 12.7722 5.65636 12.0001 5.65636C11.228 5.65636 10.7905 5.69743 10.4438 5.74003C10.3855 5.74719 10.3322 5.75403 10.2821 5.76044C10.0489 5.79033 9.88738 5.81102 9.63388 5.81242C9.62352 5.80966 9.60332 5.80376 9.57174 5.79206C9.49678 5.7643 9.39604 5.71849 9.26633 5.65166C9.05755 5.54408 8.82331 5.40842 8.55926 5.25548C8.48975 5.21523 8.41818 5.17377 8.34446 5.13132C8.00502 4.93584 7.62764 4.72384 7.26652 4.56067C6.92587 4.40675 6.50329 4.25 6.09485 4.25ZM6.16192 17.6138C6.49595 17.8657 6.8808 18.0879 7.30604 18.2835C8.83694 18.9877 10.7179 19.25 12.0001 19.25C13.2823 19.25 15.1632 18.9877 16.6941 18.2835C17.1194 18.0879 17.5042 17.8657 17.8382 17.6138C17.4858 17.5524 17.2179 17.245 17.2179 16.875C17.2179 16.4608 17.5537 16.125 17.9679 16.125C18.2951 16.125 18.6295 16.2068 18.9399 16.3204C19.0985 15.9885 19.1959 15.625 19.2226 15.2271C18.9249 15.1544 18.7193 15.125 18.6134 15.125C18.1992 15.125 17.8634 14.7892 17.8634 14.375C17.8634 13.9608 18.1992 13.625 18.6134 13.625C18.8081 13.625 19.0284 13.6542 19.2504 13.6974C19.2505 13.4213 19.2415 13.1502 19.2112 12.8724C19.1407 12.227 18.958 11.6541 18.5269 11.1447C18.3727 10.9625 18.1809 10.7813 17.9402 10.6045C17.6063 10.3594 17.5344 9.88999 17.7796 9.55611C18.0247 9.22224 18.4941 9.15031 18.828 9.39546C18.9471 9.48292 19.0597 9.57282 19.1659 9.66506C19.2099 9.43686 19.2295 9.19817 19.2302 9.06087V7.18761C19.2302 6.56231 19.0238 6.23486 18.8123 6.0527C18.5801 5.85266 18.2496 5.75011 17.9054 5.75011C17.835 5.75011 17.659 5.78868 17.3513 5.92771C17.064 6.0575 16.7432 6.23612 16.4043 6.43125C16.3407 6.4679 16.2759 6.50544 16.2106 6.54328C15.9428 6.69843 15.666 6.85883 15.4209 6.98509C15.2663 7.06473 15.1052 7.14099 14.9495 7.19867C14.8058 7.25192 14.607 7.3125 14.3941 7.3125C14.0223 7.3125 13.7617 7.27877 13.5115 7.2464C13.4654 7.24043 13.4196 7.23449 13.3735 7.22883C13.0848 7.19336 12.7084 7.15636 12.0001 7.15636C11.2919 7.15636 10.9154 7.19336 10.6267 7.22883C10.5807 7.23449 10.5349 7.24042 10.4887 7.24639C10.2386 7.27877 9.97796 7.3125 9.6061 7.3125C9.39326 7.3125 9.19445 7.25191 9.05069 7.19866C8.89497 7.14098 8.73386 7.06471 8.57928 6.98506C8.33423 6.8588 8.05742 6.69839 7.78968 6.54325C7.72435 6.50539 7.65955 6.46784 7.59589 6.43118C7.25702 6.23603 6.93614 6.05741 6.64888 5.92761C6.34115 5.78856 6.16522 5.75 6.09485 5.75C5.75062 5.75 5.42007 5.85254 5.18787 6.05259C4.97643 6.23475 4.77004 6.56219 4.77004 7.1875V9.06088C4.7707 9.19819 4.79025 9.43686 4.83425 9.66506C4.94053 9.57281 5.05309 9.48292 5.1722 9.39546C5.50608 9.15031 5.97547 9.22224 6.22062 9.55612C6.46577 9.88999 6.39385 10.3594 6.05997 10.6045C5.81926 10.7813 5.62748 10.9625 5.47331 11.1447C5.04223 11.6541 4.85949 12.227 4.789 12.8724C4.75865 13.1502 4.74966 13.4213 4.74975 13.6975C4.97192 13.6543 5.19231 13.625 5.38719 13.625C5.80141 13.625 6.13719 13.9608 6.13719 14.375C6.13719 14.7892 5.80141 15.125 5.38719 15.125C5.28121 15.125 5.07549 15.1544 4.77758 15.2271C4.80434 15.625 4.90168 15.9885 5.06027 16.3203C5.37069 16.2068 5.70504 16.125 6.03224 16.125C6.44646 16.125 6.78224 16.4608 6.78224 16.875C6.78224 17.245 6.51433 17.5524 6.16192 17.6138Z\" fill=\"#1C274C\"/>"
    "</svg>";

static NSString *RefreshSVG(NSString *hex) {
    return [NSString stringWithFormat:
        @"<svg width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" "
         "xmlns=\"http://www.w3.org/2000/svg\">"
         "<path d=\"M21 3V8M21 8H16M21 8L18 5.29168C16.4077 3.86656 14.3051 3 12 3"
         "C7.02944 3 3 7.02944 3 12C3 16.9706 7.02944 21 12 21C16.2832 21 19.8675 "
         "18.008 20.777 14\" stroke=\"%@\" stroke-width=\"2\" stroke-linecap=\"round\" "
         "stroke-linejoin=\"round\"/></svg>", hex];
}

static NSImage *SVGImage(NSData *data, NSSize size) {
    NSImage *img = [[NSImage alloc] initWithData:data];
    if (!img) return nil;
    img.size = size;
    return img;
}

static NSImage *CatIconImage(void) {
    NSData *d = [NSData dataWithBytes:kCatSVG length:strlen(kCatSVG)];
    NSImage *img = SVGImage(d, NSMakeSize(18, 18));
    img.template = YES;
    return img;
}

static NSImage *RefreshIconImage(BOOL dark) {
    NSString *svg = RefreshSVG(dark ? @"#FFFFFF" : @"#000000");
    return SVGImage([svg dataUsingEncoding:NSUTF8StringEncoding], NSMakeSize(14, 14));
}

static NSImage *Symbol(NSString *name, CGFloat pt, NSColor *color) {
    NSImage *img = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
    if (!img) return nil;
    NSImageSymbolConfiguration *size =
        [NSImageSymbolConfiguration configurationWithPointSize:pt
                                                        weight:NSFontWeightSemibold
                                                         scale:NSImageSymbolScaleMedium];
    NSImageSymbolConfiguration *tint =
        [NSImageSymbolConfiguration configurationWithHierarchicalColor:color];
    return [img imageWithSymbolConfiguration:
        [size configurationByApplyingConfiguration:tint]];
}

static void DrawSymbol(NSString *name, CGFloat pt, NSColor *color, NSRect box) {
    NSImage *img = Symbol(name, pt, color);
    if (!img) return;
    NSSize sz = img.size;
    NSRect r = NSMakeRect(NSMidX(box) - sz.width / 2, NSMidY(box) - sz.height / 2,
                          sz.width, sz.height);
    [img drawInRect:r fromRect:NSZeroRect
          operation:NSCompositingOperationSourceOver fraction:1.0];
}

@interface CardView : NSView
@property (copy) NSString *title;
@property (copy) NSString *code;
@property (copy) NSString *when;
@property (copy) NSString *room;
@property (copy) NSString *link;
@property (copy) NSString *zoom;
@property (strong) NSColor *bg;
@property (assign) BOOL hovered;
@property (assign) BOOL overPill;
@end

@implementation CardView

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *a in [self.trackingAreas copy]) [self removeTrackingArea:a];
    [self addTrackingArea:[[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                     NSTrackingActiveAlways |
                     NSTrackingInVisibleRect
               owner:self userInfo:nil]];
}

- (void)syncHoverAt:(NSPoint)pt {
    BOOL onPill = self.zoom.length && NSPointInRect(pt, [self pillRect]);
    if (onPill != self.overPill || !self.hovered) {
        self.overPill = onPill;
        self.hovered = YES;
        self.needsDisplay = YES;
    }
}

- (void)mouseMoved:(NSEvent *)e {
    [self syncHoverAt:[self convertPoint:e.locationInWindow fromView:nil]];
}

- (NSRect)pillRect {
    if (!self.zoom.length) return NSZeroRect;
    NSRect box = NSInsetRect(self.bounds, 7, 3);
    NSDictionary *f = @{ NSFontAttributeName:
        [NSFont systemFontOfSize:9.5 weight:NSFontWeightSemibold] };
    CGFloat w = ceil([@"Zoom" sizeWithAttributes:f].width) + 25;
    CGFloat h = 15;
    CGFloat x = NSMaxX(box) - 8 - w;
    CGFloat y = NSMinY(box) + (NSHeight(box) * 0.5 - h) * 0.5 + 1;
    if (x < NSMinX(box) + 8) x = NSMinX(box) + 8;
    if (y < NSMinY(box) + 3) y = NSMinY(box) + 3;
    return NSMakeRect(x, y, w, h);
}

- (void)mouseEntered:(NSEvent *)e {
    [self syncHoverAt:[self convertPoint:e.locationInWindow fromView:nil]];
}

- (void)mouseExited:(NSEvent *)e {
    self.hovered = NO; self.overPill = NO; self.needsDisplay = YES;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (!self.window) { self.hovered = NO; self.overPill = NO; }
}

- (void)mouseUp:(NSEvent *)e {
    NSPoint pt = [self convertPoint:e.locationInWindow fromView:nil];
    NSString *target = (self.zoom.length && NSPointInRect(pt, [self pillRect]))
                     ? self.zoom : self.link;
    [self.enclosingMenuItem.menu cancelTracking];
    if (target.length) {
        NSURL *u = [NSURL URLWithString:target];
        if (u) [[NSWorkspace sharedWorkspace] openURL:u];
    }
}

- (void)drawRect:(NSRect)dirty {
    NSRect box = NSInsetRect(self.bounds, 7, 3);
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:box xRadius:7 yRadius:7];
    NSColor *fill = self.bg;
    if (self.hovered && !self.overPill) {
        NSColor *c = [self.bg colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        CGFloat hue = 0, sat = 0, bri = 0, alp = 1;
        [c getHue:&hue saturation:&sat brightness:&bri alpha:&alp];
        fill = [NSColor colorWithHue:hue
                          saturation:MIN(1.0, sat * 1.75 + 0.05)
                          brightness:MAX(0.0, bri * 0.985)
                               alpha:1.0];
    }
    [fill setFill];
    [p fill];

    NSDictionary *tAttr = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor blackColor]
    };
    NSDictionary *sAttr = @{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.13 alpha:1.0]
    };

    CGFloat topY = NSMaxY(box) - 22;
    CGFloat botY = NSMinY(box) + 7;

    NSMutableAttributedString *head = [[NSMutableAttributedString alloc]
        initWithString:self.title attributes:tAttr];
    if (self.code.length) {
        NSDictionary *cAttr = @{
            NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: [NSColor colorWithWhite:0.26 alpha:1.0]
        };
        [head appendAttributedString:[[NSAttributedString alloc]
            initWithString:[NSString stringWithFormat:@"  (%@)", self.code] attributes:cAttr]];
    }
    [head drawAtPoint:NSMakePoint(NSMinX(box) + 9, topY)];
    [self.when drawAtPoint:NSMakePoint(NSMinX(box) + 9, botY) withAttributes:sAttr];

    if (self.zoom.length) {
        NSRect pill = [self pillRect];
        NSBezierPath *pp = [NSBezierPath bezierPathWithRoundedRect:pill
                                                           xRadius:8.5 yRadius:8.5];
        [[NSColor colorWithWhite:self.overPill ? 0.16 : 0.44 alpha:1.0] setFill];
        [pp fill];
        NSDictionary *zAttr = @{
            NSFontAttributeName: [NSFont systemFontOfSize:9.5 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName: [NSColor whiteColor]
        };
        NSSize zs = [@"Zoom" sizeWithAttributes:zAttr];
        CGFloat tx = NSMinX(pill) + 8;
        [@"Zoom" drawAtPoint:NSMakePoint(tx, NSMidY(pill) - zs.height / 2 + 0.5)
              withAttributes:zAttr];
        DrawSymbol(@"arrow.up.right", 8.5, [NSColor whiteColor],
                   NSMakeRect(tx + zs.width + 2, NSMinY(pill), 11, NSHeight(pill)));
    } else {
        NSSize rs = [self.room sizeWithAttributes:sAttr];
        [self.room drawAtPoint:NSMakePoint(NSMaxX(box) - 9 - rs.width, botY)
                withAttributes:sAttr];
    }
}

@end

static NSMenuItem *CardItem(NSString *title, NSString *code, NSString *when, NSString *room,
                            NSString *link, NSString *zoom, NSColor *bg, CGFloat width) {
    CardView *v = [[CardView alloc] initWithFrame:NSMakeRect(0, 0, width, 52)];
    v.autoresizingMask = NSViewWidthSizable;
    v.title = title; v.code = code; v.when = when; v.room = room;
    v.link = link; v.zoom = zoom; v.bg = bg;
    NSMenuItem *i = [[NSMenuItem alloc] init];
    i.view = v;
    return i;
}

static NSArray *LoadUpcoming(void) {
    NSData *d = [NSData dataWithContentsOfFile:CachePath()];
    if (!d) return nil;
    id root = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    if (![root isKindOfClass:[NSDictionary class]]) return nil;
    id items = root[@"items"];
    return [items isKindOfClass:[NSArray class]] ? items : nil;
}

static NSDate *ParseISO(NSString *s) {
    static NSISO8601DateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ f = [[NSISO8601DateFormatter alloc] init]; });
    return [s isKindOfClass:[NSString class]] ? [f dateFromString:s] : nil;
}

static NSString *DueLabel(NSCalendar *cal, NSDate *due) {
    if (!due) return @"";
    NSDate *a, *b;
    [cal rangeOfUnit:NSCalendarUnitDay startDate:&a interval:NULL forDate:[NSDate date]];
    [cal rangeOfUnit:NSCalendarUnitDay startDate:&b interval:NULL forDate:due];
    NSInteger days = [[cal components:NSCalendarUnitDay fromDate:a toDate:b options:0] day];

    if (days < 0)  return @"late";
    if (days == 0) return @"today";
    if (days == 1) return @"tmr";
    if (days < 7)  return [NSString stringWithFormat:@"%ldd", (long)days];

    static const char *mon[] = {"Jan","Feb","Mar","Apr","May","Jun",
                                "Jul","Aug","Sep","Oct","Nov","Dec"};
    NSDateComponents *c = [cal components:(NSCalendarUnitMonth|NSCalendarUnitDay) fromDate:due];
    return [NSString stringWithFormat:@"%s %ld", mon[c.month - 1], (long)c.day];
}

static NSString *Clip(NSString *s, NSUInteger n) {
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (s.length <= n) return s;
    return [[s substringToIndex:n - 1] stringByAppendingString:@"…"];
}

@interface FooterView : NSView
@property (weak) id target;
@property (assign) SEL quitAction;
@property (assign) SEL refreshAction;
@property (assign) BOOL overRefresh;
@property (assign) BOOL hovered;
@end

@implementation FooterView

- (NSRect)refreshRect {
    return NSMakeRect(NSMaxX(self.bounds) - 34, NSMidY(self.bounds) - 9, 20, 18);
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *a in [self.trackingAreas copy]) [self removeTrackingArea:a];
    [self addTrackingArea:[[NSTrackingArea alloc]
        initWithRect:self.bounds
             options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved |
                     NSTrackingActiveAlways |
                     NSTrackingInVisibleRect
               owner:self userInfo:nil]];
}

- (void)syncAt:(NSPoint)pt {
    BOOL on = NSPointInRect(pt, NSInsetRect([self refreshRect], -6, -4));
    if (on != self.overRefresh || !self.hovered) {
        self.overRefresh = on; self.hovered = YES; self.needsDisplay = YES;
    }
}

- (void)mouseMoved:(NSEvent *)e {
    [self syncAt:[self convertPoint:e.locationInWindow fromView:nil]];
}

- (void)mouseEntered:(NSEvent *)e {
    [self syncAt:[self convertPoint:e.locationInWindow fromView:nil]];
}

- (void)mouseExited:(NSEvent *)e {
    self.hovered = NO; self.overRefresh = NO; self.needsDisplay = YES;
}

- (void)mouseUp:(NSEvent *)e {
    NSPoint pt = [self convertPoint:e.locationInWindow fromView:nil];
    BOOL refresh = NSPointInRect(pt, NSInsetRect([self refreshRect], -6, -4));
    [self.enclosingMenuItem.menu cancelTracking];
    SEL sel = refresh ? self.refreshAction : self.quitAction;
    if (self.target && sel) ((void (*)(id, SEL))objc_msgSend)(self.target, sel);
}

- (void)drawRect:(NSRect)dirty {
    NSDictionary *a = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13],
        NSForegroundColorAttributeName: [NSColor labelColor]
    };
    NSSize qs = [@"Quit" sizeWithAttributes:a];
    [@"Quit" drawAtPoint:NSMakePoint(14, NSMidY(self.bounds) - qs.height / 2)
          withAttributes:a];

    NSRect r = [self refreshRect];
    if (self.overRefresh) {
        NSBezierPath *bgp = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, -4, -2)
                                                            xRadius:5 yRadius:5];
        [[NSColor colorWithWhite:0.5 alpha:0.42] setFill];
        [bgp fill];
    }
    BOOL dark = [[self.effectiveAppearance bestMatchFromAppearancesWithNames:
        @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]]
        isEqualToString:NSAppearanceNameDarkAqua];
    NSImage *ri = RefreshIconImage(dark);
    if (ri) {
        NSSize sz = ri.size;
        [ri drawInRect:NSMakeRect(NSMidX(r) - sz.width / 2, NSMidY(r) - sz.height / 2,
                                  sz.width, sz.height)
              fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    }
}

@end

@interface ClassBar : NSObject <NSApplicationDelegate, NSMenuDelegate>
@property (strong) NSStatusItem *status;
@property (strong) Schedule *schedule;
@property (assign) NSTimeInterval scheduleStamp;
@property (copy)   NSString *link;
@end

@implementation ClassBar

- (void)applicationDidFinishLaunching:(NSNotification *)note __unused {
    [self reloadScheduleIfChanged];
    self.link = self.schedule.canvasHome;
    self.status = [[NSStatusBar systemStatusBar]
                    statusItemWithLength:NSVariableStatusItemLength];

    NSImage *img = CatIconImage();
    self.status.button.image = img;
    self.status.button.imagePosition = NSImageOnly;

    NSMenu *m = [[NSMenu alloc] init];
    m.delegate = self;
    m.autoenablesItems = NO;
    self.status.menu = m;
}

- (void)reloadScheduleIfChanged {
    NSDictionary *attrs = [[NSFileManager defaultManager]
        attributesOfItemAtPath:SchedulePath() error:NULL];
    NSTimeInterval stamp = [attrs.fileModificationDate timeIntervalSince1970];
    if (self.schedule && stamp == self.scheduleStamp) return;
    self.schedule = [Schedule loadFromDisk];
    self.scheduleStamp = stamp;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    [self reloadScheduleIfChanged];

    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *p = [cal
        components:(NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|
                    NSCalendarUnitHour|NSCalendarUnitMinute|NSCalendarUnitWeekday)
          fromDate:[NSDate date]];

    int ymd  = (int)p.year * 10000 + (int)p.month * 100 + (int)p.day;
    int mins = (int)p.hour * 60 + (int)p.minute;
    int day  = (int)p.weekday - 2;
    if (day < 0) day = 6;

    NSArray *up = LoadUpcoming();

    NSDictionary *rowFont = @{ NSFontAttributeName: [NSFont systemFontOfSize:12] };
    CGFloat rowMax = 0;
    for (NSDictionary *a in up) {
        if (![a isKindOfClass:[NSDictionary class]]) continue;
        NSString *nm = a[@"name"];
        if (![nm isKindOfClass:[NSString class]]) continue;
        NSString *label = [NSString stringWithFormat:@"%@   %@",
                           DueLabel(cal, ParseISO(a[@"due"])), Clip(nm, 32)];
        CGFloat w = [label sizeWithAttributes:rowFont].width;
        if (w > rowMax) rowMax = w;
    }
    CGFloat cardWidth = MAX(292.0, ceil(rowMax) + 26.0);

    NSArray *series = cb_series(self.schedule, ymd, mins, day, 2);
    if (series.count) {
        NSColor *purple = [NSColor colorWithSRGBRed:0.722 green:0.655 blue:0.945 alpha:1.0];
        NSColor *blue   = [NSColor colorWithSRGBRed:0.651 green:0.839 blue:0.933 alpha:1.0];
        for (NSUInteger k = 0; k < series.count; k++) {
            NSDictionary *e = series[k];
            NSString *t = k == 0 ? e[@"title"]
                        : [NSString stringWithFormat:@"Next: %@", e[@"title"]];
            [menu addItem:CardItem(t, e[@"code"], e[@"when"], e[@"room"], e[@"link"],
                                   e[@"zoom"], k == 0 ? purple : blue, cardWidth)];
        }
    } else {
        NSString *title = nil, *when = nil, *room = nil, *link = nil;
        cb_resolve(self.schedule, ymd, mins, day, &title, &when, &room, &link);
        [self head:menu text:title];
        if (when.length) [self sub:menu text:when];
    }

    if (up.count) {
        for (NSDictionary *a in up) {
            if (![a isKindOfClass:[NSDictionary class]]) continue;
            NSString *nm = a[@"name"], *cs = a[@"course"], *ur = a[@"url"];
            if (![nm isKindOfClass:[NSString class]]) continue;
            NSDate *due = ParseISO(a[@"due"]);
            NSString *dl = DueLabel(cal, due);

            NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:nm
                                                        action:@selector(openItem:)
                                                 keyEquivalent:@""];
            NSString *label = [NSString stringWithFormat:@"%@   %@", dl, Clip(nm, 32)];
            NSMutableAttributedString *at = [[NSMutableAttributedString alloc]
                initWithString:label attributes:@{
                    NSFontAttributeName: [NSFont systemFontOfSize:12]
                }];
            [at addAttributes:@{
                NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11
                                                                      weight:NSFontWeightMedium],
                NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
            } range:NSMakeRange(0, dl.length)];
            it.attributedTitle = at;
            it.target = self;
            it.enabled = [ur isKindOfClass:[NSString class]];
            it.representedObject = ur;
            it.toolTip = [cs isKindOfClass:[NSString class]] ? cs : nil;
            [menu addItem:it];
        }
    }

    FooterView *fv = [[FooterView alloc] initWithFrame:NSMakeRect(0, 0, cardWidth, 26)];
    fv.autoresizingMask = NSViewWidthSizable;
    fv.target = self;
    fv.quitAction = @selector(quitApp);
    fv.refreshAction = @selector(refreshNow);
    NSMenuItem *q = [[NSMenuItem alloc] init];
    q.view = fv;
    [menu addItem:q];
}

- (void)head:(NSMenu *)m text:(NSString *)s {
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:s action:nil keyEquivalent:@""];
    i.attributedTitle = [[NSAttributedString alloc] initWithString:s attributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold]
    }];
    i.enabled = NO;
    [m addItem:i];
}

- (void)sub:(NSMenu *)m text:(NSString *)s {
    NSMenuItem *i = [[NSMenuItem alloc] initWithTitle:s action:nil keyEquivalent:@""];
    i.attributedTitle = [[NSAttributedString alloc] initWithString:s attributes:@{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:11
                                                              weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    }];
    i.enabled = NO;
    [m addItem:i];
}

- (void)openCanvas {
    NSURL *u = [NSURL URLWithString:self.link];
    if (u) [[NSWorkspace sharedWorkspace] openURL:u];
}

- (void)openItem:(NSMenuItem *)sender {
    NSString *s = sender.representedObject;
    if (![s isKindOfClass:[NSString class]]) return;
    NSURL *u = [NSURL URLWithString:s];
    if (u) [[NSWorkspace sharedWorkspace] openURL:u];
}

- (void)refreshNow {
    NSString *label = self.schedule.refreshAgent;
    if (!label.length) { self.scheduleStamp = 0; return; }
    NSTask *t = [[NSTask alloc] init];
    t.executableURL = [NSURL fileURLWithPath:@"/bin/launchctl"];
    t.arguments = @[@"kickstart", @"-k",
                    [NSString stringWithFormat:@"gui/%u/%@", getuid(), label]];
    [t launchAndReturnError:NULL];
}

- (void)quitApp { [NSApp terminate:nil]; }

@end

#ifdef CLASSBAR_TEST
static int fails = 0;
static Schedule *gSched;

static void T(const char *label, int ymd, int mins, int day,
              const char *wantTitle, const char *wantWhen) {
    NSString *title = nil, *when = nil, *room = nil, *link = nil;
    cb_resolve(gSched, ymd, mins, day, &title, &when, &room, &link);
    BOOL okT = [title isEqualToString:@(wantTitle)];
    BOOL okW = (wantWhen == NULL) || [when isEqualToString:@(wantWhen)];
    if (!okT || !okW) {
        fails++;
        printf("  FAIL %-34s got [%s | %s]  want [%s | %s]\n", label,
               title.UTF8String, when.UTF8String, wantTitle, wantWhen ? wantWhen : "*");
    } else {
        printf("  ok   %-34s %s · %s%s%s\n", label, title.UTF8String, when.UTF8String,
               room ? " · " : "", room ? room.UTF8String : "");
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        gSched = [Schedule loadFromDisk];

        printf("schedule: %s (%s)\n", SchedulePath().UTF8String,
               gSched.loadError ? gSched.loadError.UTF8String : "loaded");
        for (int d = 0; d < 7; d++) {
            NSArray *l = gSched.byDay[d];
            if (!l.count) continue;
            printf("  %-9s ", kDayName[d]);
            for (NSDictionary *c in l)
                printf("%s(%s) ", [c[@"name"] UTF8String],
                       HHMM([c[@"start"] intValue]).UTF8String);
            printf("\n");
        }

        printf("\ncb_resolve cases\n");
        T("before term",              20260907, 600,  0, "Term hasn't started", NULL);
        T("Mon 9:00 (15m before)",     20260914, 540,  0, "Gen Chem",        "9:15 AM · in 15m");
        T("Mon 9:15 (start edge)",     20260914, 555,  0, "Gen Chem",        "ends 10:20 AM · 1h 5m left");
        T("Mon 10:19 (last minute)",   20260914, 619,  0, "Gen Chem",        "ends 10:20 AM · 1m left");
        T("Mon 10:20 (end edge)",      20260914, 620,  0, "CHEM Recitation", "11:45 AM · in 1h 25m");
        T("Mon 4:30 (CRWT just ended)",20260914, 990,  0, "Cornerstone 1",   "4:35 PM · in 5m");
        T("Mon 4:35 (Cornerstone)",    20260914, 995,  0, "Cornerstone 1",   "ends 5:40 PM · 1h 5m left");
        T("Mon 6:00 PM -> Wed",        20260914, 1080, 0, "Gen Chem",        "Wednesday · 9:15 AM");
        T("Tue anytime -> Wed",        20260915, 700,  1, "Gen Chem",        "Wednesday · 9:15 AM");
        T("Thu 6:00 PM -> Mon",        20260917, 1080, 3, "Gen Chem",        "Monday · 9:15 AM");
        T("Fri -> Mon",                20260918, 700,  4, "Gen Chem",        "Monday · 9:15 AM");
        T("Sun -> Mon",                20260920, 700,  6, "Gen Chem",        "Monday · 9:15 AM");
        T("Thu 10:30 -> Calculus",     20260917, 630,  3, "Calculus 2",      "1:35 PM · in 3h 5m");
        T("after term",                20261221, 600,  0, "Term is over",    "");

        printf("\nassignment cache\n");
        NSArray *up = LoadUpcoming();
        if (!up.count) printf("  (none at %s)\n", CachePath().UTF8String);
        for (NSDictionary *a in up) {
            NSDate *due = ParseISO(a[@"due"]);
            printf("  %-6s %s\n", DueLabel([NSCalendar currentCalendar], due).UTF8String, Clip(a[@"name"], 32).UTF8String);
        }

        printf("\n%s (%d failures)\n", fails ? "FAILED" : "ALL PASS", fails);
    }
    return fails ? 1 : 0;
}
#else
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
#endif
