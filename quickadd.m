#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import "quickadd.h"
#import "store.h"

@implementation ComposerPanel

- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (void)cancelOperation:(id)sender __unused {
    [self.composer cancel];
}

@end

@implementation TaskComposer

- (instancetype)init {
    self = [super init];
    if (self) [self build];
    return self;
}

- (NSTextField *)mutedLabel:(NSString *)text {
    NSTextField *f = [NSTextField labelWithString:text];
    f.font = [NSFont systemFontOfSize:12];
    f.textColor = [NSColor secondaryLabelColor];
    return f;
}

- (NSDatePicker *)pickerWithElements:(NSDatePickerElementFlags)flags {
    NSDatePicker *p = [[NSDatePicker alloc] init];
    p.datePickerElements = flags;
    p.datePickerStyle = NSDatePickerStyleTextField;
    p.font = [NSFont systemFontOfSize:12];
    p.bordered = NO;
    p.drawsBackground = NO;
    p.focusRingType = NSFocusRingTypeNone;
    p.textColor = [NSColor labelColor];
    return p;
}

- (void)build {
    self.nameField = [NSTextField textFieldWithString:@""];
    self.nameField.placeholderString = @"New task";
    self.nameField.font = [NSFont systemFontOfSize:12];
    self.nameField.bordered = NO;
    self.nameField.drawsBackground = NO;
    self.nameField.focusRingType = NSFocusRingTypeNone;
    self.nameField.target = self;
    self.nameField.action = @selector(add);

    self.dayPicker = [self pickerWithElements:NSDatePickerElementFlagYearMonthDay];
    self.timePicker = [self pickerWithElements:NSDatePickerElementFlagHourMinute];

    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                       forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSTextField *hint = [self mutedLabel:@"return to add"];
    hint.font = [NSFont systemFontOfSize:10.5];
    hint.textColor = [NSColor tertiaryLabelColor];

    NSStackView *dueRow = [NSStackView stackViewWithViews:@[
        [self mutedLabel:@"Due"], self.dayPicker, self.timePicker, spacer, hint]];
    dueRow.spacing = 10;

    NSStackView *root = [NSStackView stackViewWithViews:@[self.nameField, dueRow]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 9;
    root.edgeInsets = NSEdgeInsetsMake(12, 14, 12, 14);
    root.translatesAutoresizingMaskIntoConstraints = NO;

    self.backdrop = [[NSVisualEffectView alloc]
        initWithFrame:NSMakeRect(0, 0, 320, 74)];
    self.backdrop.material = NSVisualEffectMaterialMenu;
    self.backdrop.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    self.backdrop.state = NSVisualEffectStateActive;
    self.backdrop.emphasized = NO;
    self.backdrop.layer.cornerRadius = 10;
    self.backdrop.layer.masksToBounds = YES;
    self.backdrop.layer.borderWidth = 1;
    self.backdrop.layer.borderColor =
        [NSColor colorWithWhite:1.0 alpha:0.12].CGColor;
    [self.backdrop addSubview:root];

    self.widthRule = [self.backdrop.widthAnchor constraintEqualToConstant:320];
    [NSLayoutConstraint activateConstraints:@[
        self.widthRule,
        [root.topAnchor constraintEqualToAnchor:self.backdrop.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:self.backdrop.bottomAnchor],
        [root.leadingAnchor constraintEqualToAnchor:self.backdrop.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:self.backdrop.trailingAnchor],
        [self.nameField.widthAnchor constraintEqualToAnchor:root.widthAnchor
                                                   constant:-28],
        [dueRow.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-28],
    ]];

    self.panel = [[ComposerPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 320, 74)
                  styleMask:NSWindowStyleMaskBorderless |
                            NSWindowStyleMaskNonactivatingPanel
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.panel.composer = self;
    self.panel.opaque = NO;
    self.panel.backgroundColor = [NSColor clearColor];
    self.panel.hasShadow = YES;
    self.panel.level = NSPopUpMenuWindowLevel;
    self.panel.releasedWhenClosed = NO;
    self.panel.contentView = self.backdrop;
    self.panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                    NSWindowCollectionBehaviorFullScreenAuxiliary;
}

- (void)showBelow:(NSView *)anchor width:(CGFloat)width {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *parts = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth |
                                               NSCalendarUnitDay)
                                     fromDate:[NSDate date]];
    parts.hour = 23;
    parts.minute = 59;
    NSDate *tonight = [cal dateFromComponents:parts] ?: [NSDate date];

    self.nameField.stringValue = @"";
    self.dayPicker.dateValue = tonight;
    self.timePicker.dateValue = tonight;

    self.widthRule.constant = MAX(280.0, width);
    [self.backdrop layoutSubtreeIfNeeded];
    CGFloat height = self.backdrop.fittingSize.height;
    if (height < 50) height = 74;
    [self.panel setContentSize:NSMakeSize(self.widthRule.constant, height)];

    if (!anchor.window) return;
    NSRect item = [anchor.window convertRectToScreen:anchor.bounds];
    [self.panel setFrameOrigin:NSMakePoint(NSMinX(item),
                                           NSMinY(item) - height - 5)];

    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(cancel)
               name:NSWindowDidResignKeyNotification object:self.panel];

    [NSApp activateIgnoringOtherApps:YES];
    [self.panel makeKeyAndOrderFront:nil];
    [self.panel makeFirstResponder:self.nameField];
}

- (void)cancel {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.panel orderOut:nil];
}

- (NSDate *)chosenDue {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *day = [cal components:(NSCalendarUnitYear | NSCalendarUnitMonth |
                                             NSCalendarUnitDay)
                                   fromDate:self.dayPicker.dateValue];
    NSDateComponents *clock = [cal components:(NSCalendarUnitHour | NSCalendarUnitMinute)
                                     fromDate:self.timePicker.dateValue];
    day.hour = clock.hour;
    day.minute = clock.minute;
    day.second = 0;
    return [cal dateFromComponents:day] ?: self.dayPicker.dateValue;
}

- (void)add {
    if (self.adding) return;

    NSString *name = self.nameField.stringValue;
    if (![name stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]].length) {
        NSBeep();
        return;
    }

    self.adding = YES;
    AddTask(name, [self chosenDue]);
    self.nameField.stringValue = @"";
    [self cancel];
    self.adding = NO;

    if (self.target && self.addedAction)
        ((void (*)(id, SEL))objc_msgSend)(self.target, self.addedAction);
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
