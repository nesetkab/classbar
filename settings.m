#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "settings.h"
#import "ics.h"
#import "schedule.h"
#import "store.h"

static NSDate *DateFromYMD(int ymd) {
    NSDateComponents *c = [[NSDateComponents alloc] init];
    c.year = ymd / 10000;
    c.month = (ymd / 100) % 100;
    c.day = ymd % 100;
    if (c.year < 1970 || c.month < 1 || c.month > 12) return [NSDate date];
    return [[NSCalendar currentCalendar] dateFromComponents:c] ?: [NSDate date];
}

@implementation SettingsWindow

- (instancetype)init {
    self = [super init];
    if (self) {
        self.classes = [NSMutableArray array];
        [self buildWindow];
    }
    return self;
}

- (NSTextField *)labelWithText:(NSString *)text {
    NSTextField *f = [NSTextField labelWithString:text];
    f.alignment = NSTextAlignmentRight;
    return f;
}

- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.bezelStyle = NSBezelStyleRounded;
    return b;
}

- (NSTableColumn *)columnWithId:(NSString *)ident title:(NSString *)title
                          width:(CGFloat)width {
    NSTableColumn *c = [[NSTableColumn alloc] initWithIdentifier:ident];
    c.title = title;
    c.width = width;
    c.minWidth = 40;
    return c;
}

- (void)buildWindow {
    self.window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 1000, 620)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.window.title = @"ClassBar Settings";
    self.window.releasedWhenClosed = NO;
    [self.window center];

    self.feedField = [NSTextField textFieldWithString:@""];
    self.feedField.placeholderString =
        @"https://school.instructure.com/feeds/calendars/user_….ics";
    self.homeField = [NSTextField textFieldWithString:@""];
    self.homeField.placeholderString = @"https://school.instructure.com/";
    self.beforeField = [NSTextField textFieldWithString:@""];
    self.beforeField.placeholderString = @"Classes begin Sep 9";

    self.startPicker = [[NSDatePicker alloc] init];
    self.startPicker.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    self.startPicker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    self.endPicker = [[NSDatePicker alloc] init];
    self.endPicker.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    self.endPicker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;

    self.capField = [NSTextField textFieldWithString:@""];
    self.capField.alignment = NSTextAlignmentRight;
    self.capField.target = self;
    self.capField.action = @selector(capFieldEdited);
    [self.capField.widthAnchor constraintEqualToConstant:56].active = YES;

    self.capStepper = [[NSStepper alloc] init];
    self.capStepper.minValue = kMinAssignmentCap;
    self.capStepper.maxValue = kMaxAssignmentCap;
    self.capStepper.increment = 1;
    self.capStepper.valueWraps = NO;
    self.capStepper.target = self;
    self.capStepper.action = @selector(capStepperMoved);

    self.hideDoneCheck = [NSButton checkboxWithTitle:@"Hide completed assignments"
                                              target:nil action:NULL];

    NSTextField *capSuffix = [NSTextField labelWithString:@"rows in the menu"];
    capSuffix.textColor = [NSColor secondaryLabelColor];

    NSStackView *capRow = [NSStackView stackViewWithViews:@[
        self.capField, self.capStepper, capSuffix]];
    capRow.spacing = 6;

    NSStackView *doneRow = [NSStackView stackViewWithViews:@[
        self.hideDoneCheck,
        [self buttonWithTitle:@"Restore…" action:@selector(openDoneSheet)]]];
    doneRow.spacing = 10;

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[self labelWithText:@"Canvas feed URL"], self.feedField],
        @[[self labelWithText:@"Canvas home"], self.homeField],
        @[[self labelWithText:@"Term starts"], self.startPicker],
        @[[self labelWithText:@"Term ends"], self.endPicker],
        @[[self labelWithText:@"Before term"], self.beforeField],
        @[[self labelWithText:@"Show at most"], capRow],
        @[[self labelWithText:@"Completed"], doneRow],
    ]];
    grid.rowSpacing = 8;
    grid.columnSpacing = 10;
    [grid columnAtIndex:0].width = 130;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:1].xPlacement = NSGridCellPlacementFill;
    for (NSNumber *row in @[@2, @3, @5, @6])
        [grid cellAtColumnIndex:1 rowIndex:row.integerValue].xPlacement =
            NSGridCellPlacementLeading;

    self.table = [[NSTableView alloc] init];
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.allowsMultipleSelection = YES;
    self.table.usesAlternatingRowBackgroundColors = YES;
    self.table.columnAutoresizingStyle = NSTableViewNoColumnAutoresizing;
    for (NSArray *spec in @[ @[@"name", @"Name", @160], @[@"code", @"Code", @80],
                             @[@"room", @"Room", @140], @[@"days", @"Days", @120],
                             @[@"start", @"Start", @60], @[@"end", @"End", @60],
                             @[@"canvas", @"Canvas link", @170],
                             @[@"zoom", @"Zoom link", @170] ])
        [self.table addTableColumn:[self columnWithId:spec[0] title:spec[1]
                                                width:[spec[2] doubleValue]]];

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.documentView = self.table;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = YES;
    scroll.borderType = NSBezelBorder;

    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.textColor = [NSColor secondaryLabelColor];
    self.statusLabel.font = [NSFont systemFontOfSize:11];

    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                       forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSButton *save = [self buttonWithTitle:@"Save" action:@selector(save)];
    save.keyEquivalent = @"\r";

    NSStackView *buttons = [NSStackView stackViewWithViews:@[
        [self buttonWithTitle:@"Add Class" action:@selector(addClass)],
        [self buttonWithTitle:@"Remove" action:@selector(removeSelected)],
        [self buttonWithTitle:@"Import from .ics…" action:@selector(importICS)],
        spacer,
        self.statusLabel,
        [self buttonWithTitle:@"Refresh Assignments" action:@selector(refresh)],
        save,
    ]];
    buttons.spacing = 8;

    NSTextField *heading = [NSTextField labelWithString:@"Classes"];
    heading.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];

    NSStackView *root = [NSStackView stackViewWithViews:@[grid, heading, scroll, buttons]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 12;
    root.edgeInsets = NSEdgeInsetsMake(18, 18, 18, 18);
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *content = self.window.contentView;
    [content addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:content.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [grid.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-36],
        [scroll.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-36],
        [buttons.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-36],
        [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:300],
    ]];
}

- (void)show {
    [self load];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)setStatus:(NSString *)text {
    self.statusLabel.stringValue = text ?: @"";
}

- (void)setCap:(int)cap {
    int clamped = ClampCap(cap);
    self.capField.stringValue = [NSString stringWithFormat:@"%d", clamped];
    self.capStepper.integerValue = clamped;
}

- (void)capFieldEdited {
    [self setCap:self.capField.intValue];
}

- (void)capStepperMoved {
    [self setCap:(int)self.capStepper.integerValue];
}

- (void)load {
    NSData *d = [NSData dataWithContentsOfFile:SchedulePath()];
    id root = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil;
    if (![root isKindOfClass:[NSDictionary class]]) root = @{};

    self.feedField.stringValue = [root[@"canvasFeed"] isKindOfClass:[NSString class]]
        ? root[@"canvasFeed"] : @"";
    self.homeField.stringValue = [root[@"canvasHome"] isKindOfClass:[NSString class]]
        ? root[@"canvasHome"] : @"";
    [self setCap:[root[@"assignmentCap"] isKindOfClass:[NSNumber class]]
        ? [root[@"assignmentCap"] intValue] : kDefaultAssignmentCap];
    self.hideDoneCheck.state = [root[@"hideDone"] boolValue] ? NSControlStateValueOn
                                                             : NSControlStateValueOff;

    NSDictionary *term = [root[@"term"] isKindOfClass:[NSDictionary class]]
        ? root[@"term"] : @{};
    self.startPicker.dateValue = DateFromYMD([term[@"start"] intValue]);
    self.endPicker.dateValue = DateFromYMD([term[@"end"] intValue]);
    self.beforeField.stringValue = [term[@"beforeLabel"] isKindOfClass:[NSString class]]
        ? term[@"beforeLabel"] : @"";

    [self.classes removeAllObjects];
    for (NSDictionary *c in root[@"classes"]) {
        if (![c isKindOfClass:[NSDictionary class]]) continue;
        NSMutableArray *days = [NSMutableArray array];
        for (NSNumber *n in c[@"days"])
            if ([n isKindOfClass:[NSNumber class]]) [days addObject:n];
        [self.classes addObject:[@{
            @"name": c[@"name"] ?: @"", @"code": c[@"code"] ?: @"",
            @"room": c[@"room"] ?: @"", @"days": days,
            @"start": c[@"start"] ?: @"", @"end": c[@"end"] ?: @"",
            @"canvas": c[@"canvas"] ?: @"", @"zoom": c[@"zoom"] ?: @"",
        } mutableCopy]];
    }
    [self.table reloadData];
    [self setStatus:@""];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv {
    if (tv == self.doneTable) return (NSInteger)self.doneRows.count;
    return (NSInteger)self.classes.count;
}

- (NSView *)tableView:(NSTableView *)tv viewForTableColumn:(NSTableColumn *)column
                  row:(NSInteger)row {
    NSString *key = column.identifier;
    if (tv == self.doneTable) {
        NSTextField *cell = [tv makeViewWithIdentifier:key owner:self];
        if (!cell) {
            cell = [NSTextField labelWithString:@""];
            cell.identifier = key;
            cell.font = [NSFont systemFontOfSize:12];
        }
        NSDictionary *entry = self.doneRows[(NSUInteger)row];
        if ([key isEqualToString:@"doneDue"]) {
            NSDate *due = ParseISO(entry[@"due"]);
            cell.stringValue = due ? DueLabel([NSCalendar currentCalendar], due) : @"";
        } else {
            cell.stringValue = [entry[@"name"] length] ? entry[@"name"] : entry[@"key"];
        }
        return cell;
    }
    NSTextField *field = [tv makeViewWithIdentifier:key owner:self];
    if (!field) {
        field = [NSTextField textFieldWithString:@""];
        field.identifier = key;
        field.bordered = NO;
        field.drawsBackground = NO;
        field.font = [NSFont systemFontOfSize:12];
        field.target = self;
        field.action = @selector(cellEdited:);
    }
    NSDictionary *c = self.classes[(NSUInteger)row];
    field.stringValue = [key isEqualToString:@"days"] ? DaysToText(c[@"days"])
                                                      : (c[key] ?: @"");
    return field;
}

- (void)cellEdited:(NSTextField *)sender {
    NSInteger row = [self.table rowForView:sender];
    if (row < 0 || row >= (NSInteger)self.classes.count) return;
    NSMutableDictionary *c = self.classes[(NSUInteger)row];
    NSString *key = sender.identifier;
    if ([key isEqualToString:@"days"]) {
        NSArray *days = TextToDays(sender.stringValue);
        c[@"days"] = [days mutableCopy];
        sender.stringValue = DaysToText(days);
    } else {
        c[key] = sender.stringValue;
    }
}

- (void)addClass {
    [self.classes addObject:[@{ @"name": @"New Class", @"code": @"", @"room": @"",
                                @"days": [NSMutableArray array],
                                @"start": @"09:00", @"end": @"10:00",
                                @"canvas": @"", @"zoom": @"" } mutableCopy]];
    [self.table reloadData];
    NSInteger row = (NSInteger)self.classes.count - 1;
    [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
            byExtendingSelection:NO];
    [self.table scrollRowToVisible:row];
}

- (void)removeSelected {
    NSIndexSet *rows = self.table.selectedRowIndexes;
    if (!rows.count) return;
    [self.classes removeObjectsAtIndexes:rows];
    [self.table reloadData];
}

- (void)importICS {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    UTType *ics = [UTType typeWithFilenameExtension:@"ics"];
    if (ics) panel.allowedContentTypes = @[ics];
    panel.allowsMultipleSelection = NO;
    panel.message = @"Choose a calendar export that contains your class meetings.";
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;

    NSString *text = [NSString stringWithContentsOfURL:panel.URL
                                              encoding:NSUTF8StringEncoding error:NULL];
    NSDictionary *result = text ? cb_ics_classes(text) : nil;
    if (!result) {
        [self alert:@"Nothing to import"
               info:@"No weekly class meetings were found in that calendar."];
        return;
    }
    [self applyImport:result];
}

- (void)applyImport:(NSDictionary *)result {
    NSMutableDictionary *previous = [NSMutableDictionary dictionary];
    for (NSMutableDictionary *c in self.classes) {
        NSString *key = [c[@"code"] length] ? c[@"code"] : c[@"name"];
        NSMutableArray *list = previous[key];
        if (!list) { list = [NSMutableArray array]; previous[key] = list; }
        [list addObject:c];
    }

    NSMutableArray *merged = [NSMutableArray array];
    for (NSDictionary *c in result[@"classes"]) {
        NSString *key = [c[@"code"] length] ? c[@"code"] : c[@"name"];
        NSMutableArray *list = previous[key];
        NSMutableDictionary *old = list.count ? list[0] : nil;
        if (old) [list removeObjectAtIndex:0];
        NSMutableDictionary *entry = [c mutableCopy];
        entry[@"canvas"] = old[@"canvas"] ?: @"";
        entry[@"zoom"] = old[@"zoom"] ?: @"";
        if ([old[@"name"] length]) entry[@"name"] = old[@"name"];
        [merged addObject:entry];
    }

    self.classes = merged;
    NSDictionary *term = result[@"term"];
    self.startPicker.dateValue = DateFromYMD([term[@"start"] intValue]);
    self.endPicker.dateValue = DateFromYMD([term[@"end"] intValue]);
    if (!self.beforeField.stringValue.length)
        self.beforeField.stringValue = term[@"beforeLabel"] ?: @"";
    [self.table reloadData];
    [self setStatus:[NSString stringWithFormat:@"Imported %lu classes. Not saved yet.",
                     (unsigned long)merged.count]];
}

- (void)openDoneSheet {
    self.doneRows = [[DoneEntries() mutableCopy] ?: [NSMutableArray array] mutableCopy];

    if (!self.doneSheet) {
        self.doneSheet = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 460, 320)
                      styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                        backing:NSBackingStoreBuffered
                          defer:NO];
        self.doneSheet.title = @"Completed Assignments";

        self.doneTable = [[NSTableView alloc] init];
        self.doneTable.dataSource = self;
        self.doneTable.delegate = self;
        self.doneTable.allowsMultipleSelection = YES;
        self.doneTable.usesAlternatingRowBackgroundColors = YES;
        [self.doneTable addTableColumn:[self columnWithId:@"doneName"
                                                    title:@"Assignment" width:300]];
        [self.doneTable addTableColumn:[self columnWithId:@"doneDue"
                                                    title:@"Due" width:120]];

        NSScrollView *scroll = [[NSScrollView alloc] init];
        scroll.documentView = self.doneTable;
        scroll.hasVerticalScroller = YES;
        scroll.borderType = NSBezelBorder;

        NSView *spacer = [[NSView alloc] init];
        [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                           forOrientation:NSLayoutConstraintOrientationHorizontal];

        NSButton *close = [self buttonWithTitle:@"Done" action:@selector(closeDoneSheet)];
        close.keyEquivalent = @"\r";

        NSStackView *buttons = [NSStackView stackViewWithViews:@[
            [self buttonWithTitle:@"Restore Selected" action:@selector(restoreSelected)],
            [self buttonWithTitle:@"Restore All" action:@selector(restoreAll)],
            spacer, close]];
        buttons.spacing = 8;

        NSStackView *root = [NSStackView stackViewWithViews:@[scroll, buttons]];
        root.orientation = NSUserInterfaceLayoutOrientationVertical;
        root.alignment = NSLayoutAttributeLeading;
        root.spacing = 12;
        root.edgeInsets = NSEdgeInsetsMake(18, 18, 18, 18);
        root.translatesAutoresizingMaskIntoConstraints = NO;

        NSView *content = self.doneSheet.contentView;
        [content addSubview:root];
        [NSLayoutConstraint activateConstraints:@[
            [root.topAnchor constraintEqualToAnchor:content.topAnchor],
            [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
            [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
            [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
            [scroll.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-36],
            [buttons.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-36],
        ]];
    }

    [self.doneTable reloadData];
    [self.window beginSheet:self.doneSheet completionHandler:nil];
}

- (void)closeDoneSheet {
    [self.window endSheet:self.doneSheet];
}

- (void)restoreKeys:(NSArray *)keys {
    if (!keys.count) return;
    RestoreDone(keys);
    self.doneRows = [[DoneEntries() mutableCopy] ?: [NSMutableArray array] mutableCopy];
    [self.doneTable reloadData];
    [self setStatus:[NSString stringWithFormat:@"Restored %lu",
                     (unsigned long)keys.count]];
}

- (void)restoreSelected {
    NSMutableArray *keys = [NSMutableArray array];
    [self.doneTable.selectedRowIndexes enumerateIndexesUsingBlock:
        ^(NSUInteger i, BOOL *stop __unused) {
        if (i < self.doneRows.count) [keys addObject:self.doneRows[i][@"key"]];
    }];
    [self restoreKeys:keys];
}

- (void)restoreAll {
    NSMutableArray *keys = [NSMutableArray array];
    for (NSDictionary *r in self.doneRows) [keys addObject:r[@"key"]];
    [self restoreKeys:keys];
}

- (void)alert:(NSString *)title info:(NSString *)info {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = title;
    a.informativeText = info;
    [a beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)refresh {
    if (self.target && self.refreshAction)
        ((void (*)(id, SEL))objc_msgSend)(self.target, self.refreshAction);
}

- (NSArray *)problems {
    NSMutableArray *problems = [NSMutableArray array];
    for (NSUInteger i = 0; i < self.classes.count; i++) {
        NSDictionary *c = self.classes[i];
        NSString *label = [c[@"name"] length] ? c[@"name"]
                        : [NSString stringWithFormat:@"Row %lu", (unsigned long)i + 1];
        if (![c[@"name"] length])
            [problems addObject:[NSString stringWithFormat:@"%@ has no name", label]];
        if (![c[@"days"] count])
            [problems addObject:[NSString stringWithFormat:@"%@ has no days", label]];
        if (ParseClock(c[@"start"]) < 0 || ParseClock(c[@"end"]) < 0)
            [problems addObject:[NSString stringWithFormat:
                @"%@ needs times as HH:MM, 24 hour", label]];
    }
    return problems;
}

- (NSDictionary *)buildRoot {
    NSMutableArray *classes = [NSMutableArray array];
    for (NSDictionary *c in self.classes) {
        NSMutableDictionary *entry = [@{ @"name": c[@"name"], @"code": c[@"code"] ?: @"",
                                         @"room": c[@"room"] ?: @"", @"days": c[@"days"],
                                         @"start": c[@"start"], @"end": c[@"end"] } mutableCopy];
        if ([c[@"canvas"] length]) entry[@"canvas"] = c[@"canvas"];
        if ([c[@"zoom"] length]) entry[@"zoom"] = c[@"zoom"];
        [classes addObject:entry];
    }

    return @{
        @"canvasHome": self.homeField.stringValue,
        @"canvasFeed": self.feedField.stringValue,
        @"assignmentCap": @(ClampCap(self.capField.intValue)),
        @"hideDone": @(self.hideDoneCheck.state == NSControlStateValueOn),
        @"term": @{ @"start": @(YMD(self.startPicker.dateValue)),
                    @"end": @(YMD(self.endPicker.dateValue)),
                    @"beforeLabel": self.beforeField.stringValue },
        @"classes": classes,
    };
}

- (void)save {
    [self.window makeFirstResponder:nil];

    NSArray *problems = [self problems];
    if (problems.count) {
        [self alert:@"Fix these first" info:[problems componentsJoinedByString:@"\n"]];
        return;
    }

    NSDictionary *root = [self buildRoot];
    NSData *json = [NSJSONSerialization dataWithJSONObject:root
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:NULL];
    [[NSFileManager defaultManager]
             createDirectoryAtPath:[SchedulePath() stringByDeletingLastPathComponent]
       withIntermediateDirectories:YES attributes:nil error:NULL];
    if (!json || ![json writeToFile:SchedulePath() atomically:YES]) {
        [self alert:@"Could not save" info:SchedulePath()];
        return;
    }

    [self setStatus:@"Saved"];
    if (self.target && self.savedAction)
        ((void (*)(id, SEL))objc_msgSend)(self.target, self.savedAction);
}

@end
