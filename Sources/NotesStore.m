#import "NotesStore.h"
#import <ScriptingBridge/ScriptingBridge.h>

@protocol NPNotesObject <NSObject>
- (NSString *)id;
- (NSString *)name;
- (NSString *)body;
- (void)setBody:(NSString *)body;
- (NSString *)plaintext;
- (NSDate *)modificationDate;
- (NSDate *)creationDate;
- (BOOL)passwordProtected;
- (BOOL)shared;
- (SBElementArray *)accounts;
- (SBElementArray *)folders;
- (SBElementArray *)notes;
- (SBElementArray *)attachments;
- (id)container;
- (id)defaultFolder;
- (id)defaultAccount;
- (id)showSeparately:(BOOL)separately;
@end

@interface NPNotesStore () <SBApplicationDelegate>
@property(strong) SBApplication<NPNotesObject> *app;
@property(strong) NSError *lastFailure;
@end

@implementation NPNotesStore
- (id)eventDidFail:(const AppleEvent *)event withError:(NSError *)error {
    self.lastFailure=error;
    return nil;
}
- (BOOL)prepare:(NSError **)error {
    self.lastFailure=nil;
    if (!self.app) {
        self.app=(id)[SBApplication applicationWithURL:[NSURL fileURLWithPath:@"/System/Applications/Notes.app"]];
        self.app.delegate=self;
        self.app.timeout=60*30;
    }
    if (!self.app) {
        if(error) *error=[NSError errorWithDomain:@"NotesPlus" code:1 userInfo:@{NSLocalizedDescriptionKey:@"기본 메모 앱을 찾을 수 없습니다."}];
        return NO;
    }
    return YES;
}
- (BOOL)finish:(NSError **)error {
    if (!self.lastFailure) return YES;
    if(error) *error=self.lastFailure;
    return NO;
}
- (id<NPNotesObject>)folder:(NSString *)folderID { return (id)[self.app.folders objectWithID:folderID]; }
- (id<NPNotesObject>)note:(NSString *)noteID { return (id)[self.app.notes objectWithID:noteID]; }
- (void)collectFolders:(NSArray *)folders account:(NSString *)account parent:(NSString *)parent depth:(NSUInteger)depth visited:(NSMutableSet *)visited into:(NSMutableArray *)result {
    if(depth>24 || self.lastFailure) return;
    for(id<NPNotesObject> folder in folders) {
        NSString *identifier=folder.id;
        if(!identifier || [visited containsObject:identifier]) continue;
        [visited addObject:identifier];
        NSString *name=folder.name?:@"폴더";
        BOOL shared=folder.shared;
        [result addObject:@{@"id":identifier,@"name":name,@"account":account,@"parent":parent,@"depth":@(depth),@"shared":@(shared),@"count":@(folder.notes.count)}];
        [self collectFolders:[folder.folders get] account:account parent:identifier depth:depth+1 visited:visited into:result];
    }
}
- (NSArray *)foldersWithError:(NSError **)error {
    if(![self prepare:error]) return nil;
    NSMutableArray *result=[NSMutableArray array];
    NSMutableSet *visited=[NSMutableSet set];
    for(id<NPNotesObject> account in [self.app.accounts get]) {
        [self collectFolders:[account.folders get] account:account.name?:@"계정" parent:@"" depth:0 visited:visited into:result];
    }
    return [self finish:error] ? result : nil;
}
- (NSArray *)notesInFolder:(NSString *)folderID error:(NSError **)error {
    if(![self prepare:error]) return nil;
    SBElementArray *notes=[self folder:folderID].notes;
    NSArray *ids=[notes arrayByApplyingSelector:@selector(id)];
    NSArray *names=[notes arrayByApplyingSelector:@selector(name)];
    NSArray *dates=[notes arrayByApplyingSelector:@selector(modificationDate)];
    NSArray *created=[notes arrayByApplyingSelector:@selector(creationDate)];
    if(![self finish:error]) return nil;
    if(ids.count!=names.count || ids.count!=dates.count || ids.count!=created.count) {
        if(error) *error=[NSError errorWithDomain:@"NotesPlus" code:2 userInfo:@{NSLocalizedDescriptionKey:@"메모 목록이 변경되었습니다. 새로고침해 주세요."}];
        return nil;
    }
    NSMutableArray *result=[NSMutableArray array];
    for(NSUInteger i=0;i<ids.count;i++) if([ids[i] isKindOfClass:NSString.class]) {
        [result addObject:@{@"id":ids[i],@"name":[names[i] isKindOfClass:NSString.class]?names[i]:@"새 메모",
            @"modified":[dates[i] isKindOfClass:NSDate.class]?dates[i]:NSDate.distantPast,
            @"created":[created[i] isKindOfClass:NSDate.class]?created[i]:NSDate.distantPast,@"folderID":folderID}];
    }
    return [result sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){ return [b[@"modified"] compare:a[@"modified"]]; }];
}
- (NSDictionary *)readNote:(NSString *)noteID error:(NSError **)error {
    if(![self prepare:error]) return nil;
    id<NPNotesObject> note=[self note:noteID];
    NSString *identifier=note.id;
    NSString *name=note.name;
    BOOL locked=note.passwordProtected, shared=note.shared;
    NSDate *modified=note.modificationDate, *created=note.creationDate;
    NSString *html=locked?@"":note.body;
    NSString *plain=locked?@"":note.plaintext;
    NSUInteger attachments=locked?0:note.attachments.count;
    if(![self finish:error]) return nil;
    if(!identifier) {
        if(error) *error=[NSError errorWithDomain:@"NotesPlus" code:3 userInfo:@{NSLocalizedDescriptionKey:@"메모가 이동되었거나 삭제되었습니다."}];
        return nil;
    }
    return @{@"id":identifier,@"name":name?:@"새 메모",@"html":html?:@"",@"plain":plain?:@"",
        @"locked":@(locked),@"shared":@(shared),@"attachments":@(attachments),
        @"modified":modified?:NSDate.distantPast,@"created":created?:NSDate.distantPast};
}
- (NSDictionary *)createNoteInFolder:(NSString *)folderID html:(NSString *)html error:(NSError **)error {
    if(![self prepare:error]) return nil;
    id<NPNotesObject> folder=[self folder:folderID];
    if(folder.shared) {
        if(error) *error=[NSError errorWithDomain:@"NotesPlus" code:5 userInfo:@{NSLocalizedDescriptionKey:@"첫 버전에서는 공유 폴더에 메모를 만들지 않습니다."}];
        return nil;
    }
    SBObject<NPNotesObject> *newNote=(id)[[self.app classForScriptingClass:@"note"] alloc];
    newNote=(id)[newNote initWithProperties:@{@"body":html}];
    [folder.notes addObject:newNote];
    NSString *identifier=newNote.id;
    if(![self finish:error]) return nil;
    if(!identifier) {
        if(error) *error=[NSError errorWithDomain:@"NotesPlus" code:6 userInfo:@{NSLocalizedDescriptionKey:@"메모가 생성되었는지 확인할 수 없습니다. 목록을 새로고침해 주세요."}];
        return nil;
    }
    return [self readNote:identifier error:error];
}
- (NSDictionary *)saveNote:(NSString *)noteID expectedHTML:(NSString *)expectedHTML html:(NSString *)html error:(NSError **)error {
    NSDictionary *current=[self readNote:noteID error:error];
    if(!current) return nil;
    if([current[@"locked"] boolValue] || [current[@"shared"] boolValue] || [current[@"attachments"] unsignedIntegerValue]>0) {
        if(error) *error=[NSError errorWithDomain:@"NotesPlus" code:5 userInfo:@{NSLocalizedDescriptionKey:@"잠금·공유·첨부 메모는 기본 메모 앱에서 편집해 주세요."}];
        return nil;
    }
    if(![current[@"html"] isEqualToString:expectedHTML]) {
        if(error) *error=[NSError errorWithDomain:@"NotesPlus" code:409 userInfo:@{NSLocalizedDescriptionKey:@"다른 곳에서 메모가 변경되었습니다. 원본을 덮어쓰지 않았습니다."}];
        return nil;
    }
    self.lastFailure=nil;
    [[self note:noteID] setBody:html];
    if(![self finish:error]) return nil;
    return [self readNote:noteID error:error];
}
- (BOOL)showNote:(NSString *)noteID error:(NSError **)error {
    if(![self prepare:error]) return NO;
    [[self note:noteID] showSeparately:NO];
    [self.app activate];
    return [self finish:error];
}
@end
