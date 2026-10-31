#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// All calls must use the same serial queue. Only the documented Notes scripting
// interface is used; no private frameworks, filesystem database access, or SIP changes.
@interface NPNotesStore : NSObject
- (nullable NSArray<NSDictionary *> *)foldersWithError:(NSError **)error;
- (nullable NSArray<NSDictionary *> *)notesInFolder:(NSString *)folderID error:(NSError **)error;
- (nullable NSDictionary *)readNote:(NSString *)noteID error:(NSError **)error;
- (nullable NSDictionary *)createNoteInFolder:(NSString *)folderID html:(NSString *)html error:(NSError **)error;
- (nullable NSDictionary *)saveNote:(NSString *)noteID expectedHTML:(NSString *)expectedHTML html:(NSString *)html error:(NSError **)error;
- (BOOL)showNote:(NSString *)noteID error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
