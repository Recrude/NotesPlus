import AppKit
import Foundation

@main struct SettingsTests {
    @MainActor static var checks=0
    @MainActor static func check(_ okay:Bool,_ name:String) {
        guard okay else {fatalError("FAIL: \(name)")}
        checks += 1; print("PASS: \(name)")
    }
    static func end(_ text:String)->NSRange {NSRange(location:(text as NSString).length,length:0)}
    static func replacing(_ text:String,_ edit:TextEdit?)->String? {edit.map{(text as NSString).replacingCharacters(in:$0.range,with:$0.replacement)}}
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let suite="dev.notesplus.settings-test.\(UUID().uuidString)"
        let d=UserDefaults(suiteName:suite)!
        defer {d.removePersistentDomain(forName:suite)}
        d.set(1.75,forKey:"lineRatio"); d.set(true,forKey:"autoLists")
        let s=EditorSettings(defaults:d)
        check(s.lineRatio==1.75 && s.starBullet,"v0.3 typography and star preference migrate")
        s.listPreset("numbers")
        check(s.numberPeriod && s.numberParen && !s.starBullet && !s.dashBullet && !s.plusBullet,"number-only preset keeps star literal")
        s.fontSize=18; s.syncInterval=7
        check(EditorSettings(defaults:d).fontSize==18 && EditorSettings(defaults:d).syncInterval==7,"settings survive a new instance")
        s.reset([\Preferences.fontSize])
        check(s.fontSize==15 && s.syncInterval==7,"section reset preserves unrelated settings")
        let exported=try s.exportData(); let copy=EditorSettings(defaults:UserDefaults(suiteName:suite)!)
        copy.reset(); try copy.importData(exported)
        check(copy.values==s.values,"all preferences export and import losslessly")
        let before=copy.values
        do {try copy.importData(Data("{\"lineRatio\":\"oops\"}".utf8)); check(false,"invalid import rejected")} catch {check(copy.values==before,"invalid import leaves every existing setting unchanged")}
        do {try copy.importData(Data("{\"unrecognized\":true}".utf8)); check(false,"unknown key rejected")} catch {check(copy.values==before,"unknown settings rejected without mutation")}
        try copy.importData(Data("{\"fontSize\":999,\"lineRatio\":-1,\"sortBy\":\"invalid\",\"syncInterval\":0}".utf8))
        check(copy.fontSize==40 && copy.lineRatio==1 && copy.sortBy=="created" && copy.syncInterval==2,"import validates ranges and enum values")
        s.reset()
        check(s.lineRatio==1.6 && s.numberPeriod && !s.starBullet,"default matches requested numbered-only setup")
        check(s.sortBy=="created" && !s.sortAscending,"new default sorts by creation date, newest first")
        var legacy=Preferences(); legacy.sortBy="modified"; legacy.lineRatio=1.85
        d.set(try JSONEncoder().encode(legacy),forKey:EditorSettings.key); d.removeObject(forKey:"createdSortDefault.v6")
        let migrated=EditorSettings(defaults:d)
        check(migrated.sortBy=="created" && migrated.lineRatio==1.85,"upgrade adopts creation-date order while preserving typography")
        migrated.sortBy="modified"
        check(EditorSettings(defaults:d).sortBy=="modified","later explicit modified-date choice survives relaunch")
        let fixedDate=Date(timeIntervalSince1970:1793437445) // 2026-10-31 18:04:05 in Seoul.
        let zone=TimeZone(identifier:"Asia/Seoul")!
        check(TimestampFormat.string(date:fixedDate,format:TimestampFormat.standard,timeZone:zone)=="2026/10/31 18:04","timestamp default uses Gregorian year, month, day and 24-hour minutes")
        check(TimestampFormat.string(date:fixedDate,format:TimestampFormat.compact,timeZone:zone)=="20261031 180405","compact timestamp includes seconds")
        s.timestampFormat=TimestampFormat.compact; s.timestampKey="y"; s.timestampModifiers="option"
        let reloaded=EditorSettings(defaults:d)
        check(reloaded.timestampFormat==TimestampFormat.compact && reloaded.timestampKey=="y" && reloaded.timestampModifiers=="option","timestamp format and shortcut persist together")
        try copy.importData(s.exportData())
        check(copy.timestampFormat==s.timestampFormat && copy.timestampKey=="y" && copy.timestampModifiers=="option","timestamp options survive settings export and import")
        try copy.importData(Data("{\"timestampKey\":\"z\",\"timestampModifiers\":\"shift\",\"timestampFormat\":\"\"}".utf8))
        check(copy.timestampFormat==TimestampFormat.standard && copy.timestampKey=="t" && copy.timestampModifiers=="control","empty format and conflicting undo shortcut fall back safely")
        s.reset([\Preferences.timestampFormat,\.timestampKey,\.timestampModifiers])
        check(s.timestampFormat==TimestampFormat.standard && s.timestampKey=="t" && s.timestampModifiers=="control","timestamp section reset restores command-control-T")
        var p=s.values
        check(ListRules.trigger("1.",preferences:p)?.ordered==true,"period trigger creates an ordered list")
        check(ListRules.trigger("7)",preferences:p)?.start==7,"parenthesis trigger carries starting number")
        check(ListRules.trigger("*",preferences:p)==nil,"disabled asterisk stays literal")
        p.numberPeriod=false
        check(ListRules.trigger("1.",preferences:p)==nil && ListRules.trigger("1)",preferences:p) != nil,"period and parenthesis triggers are independent")
        check(ListRules.trigger("3.14",preferences:p)==nil,"decimal text does not start a list")
        check(ListRules.trigger("본문 1.",preferences:p)==nil,"number trigger applies only at paragraph start")
        check(ListRules.newline(text:"\t본문",selection:end("\t본문"),preferences:p)?.replacement=="\n\t","plain paragraph indent maintained")
        s.newNoteStyle="heading"
        check(NoteCodec.html(for:"한글 제목\n본문",profile:s.newNoteProfile).contains("<h2>한글 제목</h2>"),"new note style changes saved heading markup")

        // Real TextKit 2 storage with structural list attributes, isolated from user notes.
        var changes:[String]=[]
        let editor=NoteEditor(text:"",noteID:"test",settings:s,editable:true,focusToken:UUID(),onChange:{text,_ in changes.append(text)})
        let c=editor.makeCoordinator(); let view=PlainNoteTextView(usingTextLayoutManager:true)
        view.frame=NSRect(x:0,y:0,width:800,height:600); view.textContentStorage?.includesTextListMarkers=false
        view.isRichText=true; view.allowsUndo=true; view.delegate=c; c.view=view
        s.starBullet=false; view.string="1."; view.setSelectedRange(end("1."))
        let allow=c.textView(view,shouldChangeTextIn:end("1."),replacementString:" ")
        check(!allow && view.string.trimmingCharacters(in:.newlines).isEmpty && RichTextBridge.capture(view).paragraphs[0].lists.first?.kind=="decimal","number trigger creates a structural list without number characters")
        view.undoManager?.undo()
        check(view.string=="1." && !RichTextBridge.capture(view).hasLists,"undo restores text and removes list attributes")
        view.undoManager?.redo()
        check(view.string.trimmingCharacters(in:.newlines).isEmpty && RichTextBridge.capture(view).hasLists,"redo restores structural list attributes")
        view.string="1."; view.isPasting=true
        check(c.textView(view,shouldChangeTextIn:end("1."),replacementString:" ") && view.string=="1.","paste bypasses enabled transformations")
        view.isPasting=false
        let numbered=NoteDocument(paragraphs:[NoteParagraph(text:"한글",lists:[NoteList(id:1,kind:"decimal")])])
        let (attributed,typing)=RichTextBridge.attributed(numbered,settings:s)
        view.textStorage!.setAttributedString(attributed); view.typingAttributes=typing; view.setSelectedRange(NSRange(location:"한글".utf16.count,length:0))
        check(c.textView(view,doCommandBy:NSSelectorFromString("insertNewline:")) && RichTextBridge.capture(view).paragraphs.dropLast().last?.lists.first?.kind=="decimal","Return continues the actual NSTextList")
        check(c.textView(view,doCommandBy:NSSelectorFromString("insertNewline:")) && RichTextBridge.capture(view).paragraphs.last?.lists.isEmpty==true,"Return on an empty list item exits the actual list")
        s.spellChecking=false; s.smartQuotes=true; s.smartDashes=true; s.textCompletion=false
        s.horizontalPadding=30; s.readableWidth=600; s.useDarkBackground=false; c.applyInputSettings()
        check(!view.isContinuousSpellCheckingEnabled && view.isAutomaticQuoteSubstitutionEnabled && view.isAutomaticDashSubstitutionEnabled && !view.isAutomaticTextCompletionEnabled,"typing toggles reach NSTextView")
        check(view.textContainerInset.width==100 && view.appearance?.name == .aqua,"page width and light body appearance reach NSTextView")
        s.lineRatio=1.8; s.characterSpacing=0.8; c.applyStyle(force:true)
        let attrs=view.textStorage!.attributes(at:0,effectiveRange:nil)
        check(abs((attrs[.paragraphStyle] as! NSParagraphStyle).minimumLineHeight-27)<0.01 && (attrs[.kern] as! Double)==0.8,"line height and character spacing reach rendered text attributes")
        check((attrs[.paragraphStyle] as! NSParagraphStyle).textLists.count==1,"custom line height preserves native list attributes")
        view.editorSettings=s
        view.undoManager?.removeAllActions()
        view.setSelectedRange(NSRange(location:0,length:"한글".utf16.count))
        let beforeStamp=RichTextBridge.capture(view)
        let stamp=TimestampFormat.string(date:fixedDate,format:s.timestampFormat)
        view.insertTimestamp(at:fixedDate)
        check(view.string.hasPrefix(stamp) && changes.last==view.string,"timestamp replaces the selection through the normal autosave change callback")
        check(RichTextBridge.capture(view).paragraphs[0].lists.first?.ordered==true,"timestamp inside an ordered list preserves actual list structure")
        view.undoManager?.undo()
        check(RichTextBridge.capture(view)==beforeStamp,"one undo restores text and list structure before timestamp")
        view.undoManager?.redo()
        check(view.string.hasPrefix(stamp),"timestamp redo restores the insertion")
        view.isEditable=false; let protected=view.string; view.insertTimestamp(at:fixedDate)
        check(view.string==protected,"timestamp cannot modify a protected read-only note")
        view.isEditable=true
        view.setMarkedText("ㅎ",selectedRange:NSRange(location:1,length:0),replacementRange:end(view.string))
        let composing=view.string; view.insertTimestamp(at:fixedDate)
        check(view.string==composing && view.hasMarkedText(),"timestamp leaves active Korean composition untouched")
        view.unmarkText(); view.undoManager?.removeAllActions()
        s.tabInsertsSpaces=true; s.tabWidth=2; view.string=""; view.typingAttributes=RichTextBridge.attributes(settings:s); view.setSelectedRange(end(""))
        check(c.textView(view,doCommandBy:NSSelectorFromString("insertTab:")) && view.string=="  ","Tab inserts configured spaces")
        let longText="제목\n"+String(repeating:"한글 본문을 길게 입력하는 성능 검증 문장입니다.\n",count:2000)
        c.parent.titleTemplate="<h1>title</h1>"
        view.textStorage!.setAttributedString(NSAttributedString(string:longText,attributes:RichTextBridge.attributes(settings:s)))
        c.applyStyle(force:true); let fullPasses=c.fullStylePasses
        var durations:[Double]=[]
        for _ in 0..<100 {
            let range=end(view.string); view.setSelectedRange(range)
            let start=CFAbsoluteTimeGetCurrent()
            _ = c.textView(view,shouldChangeTextIn:range,replacementString:"a")
            view.insertText("a",replacementRange:range)
            durations.append((CFAbsoluteTimeGetCurrent()-start)*1000)
        }
        check(c.fullStylePasses==fullPasses,"100 keystrokes in a 56k-character titled note never restyle the whole document")
        let sorted=durations.sorted(); print("PERF: 100 keystrokes, p95=\(sorted[94])ms max=\(sorted.last!)ms")
        print("\(checks) checks passed.")
    }
}
