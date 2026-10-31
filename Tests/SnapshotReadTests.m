#import "../Sources/NotesStore.h"

// Public scripting properties arrive in separate events. Exercise interleavings
// without connecting to or changing a real user's Notes account.
@interface ChangingNote:NSObject
@property NSUInteger version;
@property NSUInteger reads;
@property BOOL changeOnce;
@property BOOL changeAlways;
@property BOOL dateOnly;
@property BOOL lockOnRead;
@property BOOL passwordProtected;
@end
@implementation ChangingNote
- (NSString *)id {return @"synthetic-note";}
- (NSString *)name {return @"Synthetic";}
- (BOOL)shared {return NO;}
- (NSArray *)attachments {return @[];}
- (NSDate *)creationDate {return [NSDate dateWithTimeIntervalSince1970:1];}
- (NSDate *)modificationDate {return [NSDate dateWithTimeIntervalSince1970:100+self.version];}
- (NSString *)body {return [NSString stringWithFormat:@"<div>version %lu</div>",(unsigned long)(self.dateOnly?0:self.version)];}
- (NSString *)plaintext {
    self.reads++;
    if (self.changeOnce || self.changeAlways) {self.version++; self.changeOnce=NO;}
    if (self.lockOnRead) {self.passwordProtected=YES; self.lockOnRead=NO;}
    return [NSString stringWithFormat:@"version %lu",(unsigned long)(self.dateOnly?0:self.version)];
}
@end

@interface SnapshotStore:NPNotesStore
@property ChangingNote *fixture;
@end
@implementation SnapshotStore
- (BOOL)prepare:(NSError **)error {return YES;}
- (BOOL)finish:(NSError **)error {return YES;}
- (id)note:(NSString *)noteID {return self.fixture;}
@end

static int checks=0;
static void check(BOOL okay,NSString *message) {
    if (!okay) {fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1);}
    checks++; printf("PASS: %s\n",message.UTF8String);
}
int main(void) {@autoreleasepool {
    SnapshotStore *store=[SnapshotStore new]; store.fixture=[ChangingNote new];
    NSError *error=nil;
    NSDictionary *value=[store readNote:@"synthetic-note" error:&error];
    check(value!=nil && error==nil && store.fixture.reads==1,@"stable scripting properties produce one complete snapshot");
    store.fixture=[ChangingNote new]; store.fixture.changeOnce=YES;
    value=[store readNote:@"synthetic-note" error:&error];
    check([value[@"html"] isEqual:@"<div>version 1</div>"] && [value[@"plain"] isEqual:@"version 1"] && store.fixture.reads==2,@"a body change between HTML and plaintext reads retries the whole snapshot");
    store.fixture=[ChangingNote new]; store.fixture.changeOnce=YES; store.fixture.dateOnly=YES;
    value=[store readNote:@"synthetic-note" error:&error];
    check(store.fixture.reads==2 && [value[@"modified"] isEqual:[NSDate dateWithTimeIntervalSince1970:101]],@"a metadata-only change also invalidates a torn read");
    store.fixture=[ChangingNote new]; store.fixture.changeAlways=YES;
    value=[store readNote:@"synthetic-note" error:&error];
    check(value==nil && error.code==425 && store.fixture.reads==3,@"continuous remote edits defer reading after bounded retries");
    store.fixture=[ChangingNote new]; store.fixture.lockOnRead=YES; error=nil;
    value=[store readNote:@"synthetic-note" error:&error];
    check([value[@"locked"] boolValue] && [value[@"html"] length]==0 && [value[@"plain"] length]==0,@"a note locked during the read never yields an editable snapshot");
    printf("%d snapshot checks passed.\n",checks);
    return 0;
}}
