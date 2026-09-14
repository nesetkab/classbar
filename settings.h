#import <Cocoa/Cocoa.h>

@interface SettingsWindow : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property (strong) NSWindow *window;
@property (strong) NSMutableArray *classes;
@property (strong) NSTextField *feedField;
@property (strong) NSTextField *homeField;
@property (strong) NSDatePicker *startPicker;
@property (strong) NSDatePicker *endPicker;
@property (strong) NSTextField *beforeField;
@property (strong) NSTextField *capField;
@property (strong) NSStepper *capStepper;
@property (strong) NSButton *hideDoneCheck;
@property (strong) NSWindow *doneSheet;
@property (strong) NSTableView *doneTable;
@property (strong) NSMutableArray *doneRows;
@property (strong) NSTableView *table;
@property (strong) NSTextField *statusLabel;
@property (weak)   id target;
@property (assign) SEL savedAction;
@property (assign) SEL refreshAction;
- (void)show;
- (void)load;
- (void)setStatus:(NSString *)text;
- (void)setCap:(int)cap;
- (NSArray *)problems;
- (NSDictionary *)buildRoot;
- (void)openDoneSheet;
- (void)closeDoneSheet;
@end
