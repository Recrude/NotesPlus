import Foundation

struct TextEdit: Equatable { let range:NSRange; let replacement:String }

// Pure UTF-16 editing rules shared by the AppKit delegate and regression tests.
// Invoked for keyboard commands only, never for paste, IME composition or loading notes.
enum ListRules {
    static func trigger(_ prefix:String,preferences p:Preferences)->NoteList? {
        if let parts=match("^([0-9]{1,9})([.)])$",prefix),
           (parts[1]=="." ? p.numberPeriod : p.numberParen),let n=Int(parts[0]),n>0 {
            return NoteList(id:0,kind:"decimal",start:n)
        }
        let enabled=(prefix=="*" && p.starBullet) || (prefix=="-" && p.dashBullet) || (prefix=="+" && p.plusBullet)
        guard enabled else{return nil}
        return NoteList(id:0,kind:p.bulletSymbol=="–" ? "dash" : (p.bulletSymbol=="◦" ? "circle" : "disc"))
    }
    private static func match(_ pattern:String,_ text:String)->[String]? {
        guard let r=try? NSRegularExpression(pattern:pattern), let m=r.firstMatch(in:text,range:NSRange(location:0,length:(text as NSString).length)) else { return nil }
        return (1..<m.numberOfRanges).map { m.range(at:$0).location==NSNotFound ? "" : (text as NSString).substring(with:m.range(at:$0)) }
    }
    static func space(text:String,selection:NSRange,preferences p:Preferences)->TextEdit? {
        let ns=text as NSString
        guard selection.length==0, selection.location<=ns.length else { return nil }
        let prefix=ns.substring(to:selection.location)
        let line=prefix.components(separatedBy:"\n").last ?? ""
        guard let parts=match("^([\\t ]*)([*+\\-])$",line) else { return nil }
        let enabled=parts[1]=="*" ? p.starBullet : (parts[1]=="-" ? p.dashBullet : p.plusBullet)
        guard enabled else { return nil }
        return TextEdit(range:NSRange(location:selection.location-1,length:1),replacement:p.bulletSymbol+" ")
    }
    static func newline(text:String,selection:NSRange,preferences p:Preferences)->TextEdit? {
        let ns=text as NSString
        guard selection.length==0, selection.location<=ns.length else { return nil }
        let prefix=ns.substring(to:selection.location)
        let line=prefix.components(separatedBy:"\n").last ?? ""
        let start=selection.location-(line as NSString).length
        let atEnd=selection.location==ns.length || ns.substring(with:NSRange(location:selection.location,length:1))=="\n"
        if let parts=match("^([\\t ]*)([0-9]{1,9})([.)]) ([\\s\\S]*)$",line),
           (parts[2]=="." ? p.numberPeriod : p.numberParen), let n=Int(parts[1]) {
            if parts[3].trimmingCharacters(in:.whitespaces).isEmpty && atEnd && p.exitEmptyList {
                return TextEdit(range:NSRange(location:start,length:(line as NSString).length),replacement:"")
            }
            return TextEdit(range:selection,replacement:"\n"+parts[0]+String(n+1)+parts[2]+" ")
        }
        if p.continueBullets, let parts=match("^([\\t ]*)([•◦–]) ([\\s\\S]*)$",line) {
            if parts[2].trimmingCharacters(in:.whitespaces).isEmpty && atEnd && p.exitEmptyList {
                return TextEdit(range:NSRange(location:start,length:(line as NSString).length),replacement:"")
            }
            return TextEdit(range:selection,replacement:"\n"+parts[0]+parts[1]+" ")
        }
        if p.preserveIndent, let indent=match("^([\\t ]+)",line)?.first {
            return TextEdit(range:selection,replacement:"\n"+indent)
        }
        return nil
    }
}
