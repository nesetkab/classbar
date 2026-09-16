#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import "quickadd.h"
#import "store.h"

@implementation QuickAddWindow

- (instancetype)init {
    self = [super init];
    if (self) [self buildWindow];
    return self;
}

- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)action {
    NSButton *b = [NSButton buttonWithTitle:title target:self action:action];
    b.bezelStyle = NSBezelStyleRounded;
    return b;
}

- (void)buildWindow {
    self.window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 420, 150)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    self.window.title = @"New Task";
    self.window.releasedWhenClosed = NO;
    [self.window center];

    self.nameField = [NSTextField textFieldWithString:@""];
    self.nameField.placeholderString = @"What do you need to do?";
    self.nameField.target = self;
    self.nameField.action = @selector(add);

    self.duePicker = [[NSDatePicker alloc] init];
    self.duePicker.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    self.duePicker.datePickerStyle = NSDatePickerStyleTextFieldAndStepper;
    [self.duePicker.widthAnchor constraintGreaterThanOrEqualToConstant:118].active = YES;

    NSTextField *dueLabel = [NSTextField labelWithString:@"Due"];
    dueLabel.alignment = NSTextAlignmentRight;
    [dueLabel.widthAnchor constraintEqualToConstant:34].active = YES;

    NSView *spacer = [[NSView alloc] init];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow
                       forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSButton *add = [self buttonWithTitle:@"Add" action:@selector(add)];
    add.keyEquivalent = @"\r";

    NSStackView *dueRow = [NSStackView stackViewWithViews:@[
        dueLabel, self.duePicker, spacer,
        [self buttonWithTitle:@"Cancel" action:@selector(close)], add]];
    dueRow.spacing = 8;

    NSStackView *root = [NSStackView stackViewWithViews:@[self.nameField, dueRow]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 16;
    root.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSView *content = self.window.contentView;
    [content addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:content.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:content.bottomAnchor],
        [root.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],
        [self.nameField.widthAnchor constraintEqualToAnchor:root.widthAnchor
                                                   constant:-40],
        [dueRow.widthAnchor constraintEqualToAnchor:root.widthAnchor constant:-40],
    ]];
}

- (void)show {
    self.nameField.stringValue = @"";
    self.duePicker.dateValue = [NSDate date];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.nameField];
}

- (void)close {
    [self.window orderOut:nil];
}

- (void)add {
    NSString *name = self.nameField.stringValue;
    if (![name stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]].length) {
        NSBeep();
        return;
    }
    AddTask(name, self.duePicker.dateValue);
    [self close];
    if (self.target && self.addedAction)
        ((void (*)(id, SEL))objc_msgSend)(self.target, self.addedAction);
}

@end
