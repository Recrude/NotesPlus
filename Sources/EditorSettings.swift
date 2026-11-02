import AppKit
import SwiftUI

struct Preferences: Codable, Equatable {
    // Familiar Notes options, applied locally to NotesPlus.
    var sortBy = "created"
    var sortAscending = false
    var groupByDate = true
    var galleryView = false
    var newNoteStyle = "body"
    var defaultFolderID = ""
    var useDarkBackground = true
    var fontSize = 15.0
    // Extensions: typography and page layout.
    var fontName = "system"
    var fontWeight = "regular"
    var lineRatio = 1.6
    var paragraphSpacing = 0.0
    var characterSpacing = 0.0
    var horizontalPadding = 20.0
    var verticalPadding = 5.0
    var readableWidth = 0.0
    var tabWidth = 4
    // Each trigger can independently create a structural list.
    var numberPeriod = true
    var numberParen = true
    var starBullet = false
    var dashBullet = false
    var plusBullet = false
    var bulletSymbol = "•"
    var continueBullets = true
    var exitEmptyList = true
    var preserveIndent = true
    var tabInsertsSpaces = false
    // AppKit typing controls.
    var spellChecking = true
    var grammarChecking = false
    var spellingCorrection = false
    var smartQuotes = false
    var smartDashes = false
    var textReplacement = true
    var textCompletion = false
    var smartInsertDelete = true
    var timestampFormat = TimestampFormat.standard
    var timestampKey = "t"
    var timestampModifiers = "control"
    // Appearance and navigation.
    var appearance = "system"
    var showNoteDate = true
    var showCharacterCount = false
    var showFolderCounts = true
    var previewLines = 1
    var listDensity = "standard"
    var listFontSize = 14.0
    var searchScope = "preview"
    var showFormatTool = true
    var showChecklistTool = true
    var showTableTool = true
    var showAttachmentTool = true
    var showShareTool = true
    // Automatic save stays on; only timing is customizable.
    var autosaveDelay = 1.2
    var autosaveMaxInterval = 8.0
    var syncInterval = 3.0
    var restoreLastNote = true

    mutating func validate() {
        func clamp(_ value:Double,_ range:ClosedRange<Double>,_ fallback:Double)->Double {
            value.isFinite ? min(range.upperBound,max(range.lowerBound,value)) : fallback
        }
        fontSize=clamp(fontSize,10...40,15); lineRatio=clamp(lineRatio,1...3,1.6)
        paragraphSpacing=clamp(paragraphSpacing,0...40,0); characterSpacing=clamp(characterSpacing,-1...5,0)
        horizontalPadding=clamp(horizontalPadding,8...100,20); verticalPadding=clamp(verticalPadding,0...80,5)
        readableWidth=readableWidth == 0 ? 0 : clamp(readableWidth,320...1200,640)
        listFontSize=clamp(listFontSize,11...20,14); previewLines=min(3,max(0,previewLines))
        autosaveDelay=clamp(autosaveDelay,0.3...3,1.2); autosaveMaxInterval=clamp(autosaveMaxInterval,3...30,8); syncInterval=clamp(syncInterval,2...30,3)
        if ![2,4,8].contains(tabWidth) { tabWidth=4 }
        if !["modified","created","title"].contains(sortBy) { sortBy="created" }
        timestampFormat=TimestampFormat.validated(timestampFormat)
        timestampKey=timestampKey.lowercased()
        if !TimestampShortcut.keys.contains(timestampKey) {timestampKey="t"}
        if !TimestampShortcut.combinations.contains(timestampModifiers) {timestampModifiers="control"}
        if TimestampShortcut.reserved(key:timestampKey,combination:timestampModifiers) {timestampKey="t"; timestampModifiers="control"}
        if !["body","title","heading","subheading"].contains(newNoteStyle) { newNoteStyle="body" }
        if !["system","light","dark"].contains(appearance) { appearance="system" }
        if !["regular","medium","semibold"].contains(fontWeight) { fontWeight="regular" }
        if !["compact","standard","comfortable"].contains(listDensity) { listDensity="standard" }
        if !["title","preview"].contains(searchScope) { searchScope="preview" }
        if !["•","–","◦"].contains(bulletSymbol) { bulletSymbol="•" }
        if fontName != "system", NSFont(name:fontName,size:fontSize) == nil { fontName="system" }
    }
}

@dynamicMemberLookup @MainActor final class EditorSettings: ObservableObject {
    @Published var values:Preferences {
        didSet {
            var checked=values; checked.validate()
            if checked != values {values=checked; return}
            persist()
        }
    }
    private let defaults:UserDefaults
    static let key="preferences.v4"
    init(defaults:UserDefaults = .standard) {
        self.defaults=defaults
        if let data=defaults.data(forKey:Self.key), var decoded=try? Self.decode(data) {
            if !defaults.bool(forKey:"createdSortDefault.v6"),decoded.sortBy=="modified" {decoded.sortBy="created"}
            values=decoded
        }
        else {
            var p=Preferences()
            for key in ["fontSize","lineRatio","paragraphSpacing"] where defaults.object(forKey:key) != nil {
                if key=="fontSize" { p.fontSize=defaults.double(forKey:key) }
                if key=="lineRatio" { p.lineRatio=defaults.double(forKey:key) }
                if key=="paragraphSpacing" { p.paragraphSpacing=defaults.double(forKey:key) }
            }
            p.fontName=defaults.string(forKey:"fontName") ?? "system"
            p.starBullet=defaults.bool(forKey:"autoLists")
            if defaults.object(forKey:"groupByDate") != nil { p.groupByDate=defaults.bool(forKey:"groupByDate") }
            p.galleryView=defaults.bool(forKey:"galleryView")
            p.validate(); values=p
        }
        defaults.set(true,forKey:"createdSortDefault.v6")
        persist()
    }
    subscript<T>(dynamicMember keyPath:WritableKeyPath<Preferences,T>)->T {
        get { values[keyPath:keyPath] }
        set { values[keyPath:keyPath]=newValue }
    }
    private func persist() { if let data=try? JSONEncoder().encode(values) { defaults.set(data,forKey:Self.key) } }
    func reset() { values=Preferences() }
    func reset(_ keys:[PartialKeyPath<Preferences>]) {
        // Section resets merge only the section's keys, preserving all other preferences.
        let baseline=Preferences()
        for key in keys {
            if let k=key as? WritableKeyPath<Preferences,Bool> { values[keyPath:k]=baseline[keyPath:k] }
            else if let k=key as? WritableKeyPath<Preferences,Double> { values[keyPath:k]=baseline[keyPath:k] }
            else if let k=key as? WritableKeyPath<Preferences,Int> { values[keyPath:k]=baseline[keyPath:k] }
            else if let k=key as? WritableKeyPath<Preferences,String> { values[keyPath:k]=baseline[keyPath:k] }
        }
    }
    func listPreset(_ mode:String) {
        values.numberPeriod=mode != "manual"; values.numberParen=mode != "manual"
        values.starBullet=mode=="all"; values.dashBullet=mode=="all"; values.plusBullet=mode=="all"
        values.continueBullets=mode != "manual"
    }
    func exportData() throws -> Data {
        let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        return try encoder.encode(values)
    }
    func importData(_ data:Data) throws { values=try Self.decode(data) }
    private static func decode(_ data:Data) throws -> Preferences {
        guard data.count<1_000_000,
              let incoming=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              var base=try JSONSerialization.jsonObject(with:JSONEncoder().encode(Preferences())) as? [String:Any] else {
            throw NSError(domain:"NotesPlus",code:1,userInfo:[NSLocalizedDescriptionKey:"NotesPlus 설정 JSON 파일이 아닙니다."])
        }
        guard !incoming.isEmpty, Set(incoming.keys).isSubset(of:Set(base.keys)) else {
            throw NSError(domain:"NotesPlus",code:2,userInfo:[NSLocalizedDescriptionKey:"알 수 없는 설정 항목이 있습니다. 파일을 확인해 주세요."])
        }
        for (key,value) in incoming { base[key]=value }
        var result=try JSONDecoder().decode(Preferences.self,from:JSONSerialization.data(withJSONObject:base))
        result.validate(); return result
    }
    var font:NSFont {
        let weight:NSFont.Weight=self.fontWeight=="semibold" ? .semibold : (self.fontWeight=="medium" ? .medium : .regular)
        if self.fontName=="system" { return .systemFont(ofSize:self.fontSize,weight:weight) }
        let original=NSFont(name:self.fontName,size:self.fontSize) ?? .systemFont(ofSize:self.fontSize)
        if self.fontWeight=="regular" {return original}
        let descriptor=original.fontDescriptor.addingAttributes([.traits:[NSFontDescriptor.TraitKey.weight:weight.rawValue]])
        return NSFont(descriptor:descriptor,size:self.fontSize) ?? original
    }
    var paragraph:NSParagraphStyle {
        let p=NSMutableParagraphStyle()
        p.minimumLineHeight=self.fontSize*self.lineRatio; p.maximumLineHeight=self.fontSize*self.lineRatio
        p.paragraphSpacing=self.paragraphSpacing; p.lineBreakMode = .byWordWrapping
        let space=(" " as NSString).size(withAttributes:[.font:font]).width
        p.tabStops=[]; p.defaultTabInterval=space*Double(self.tabWidth)
        return p
    }
    var colorScheme:ColorScheme? { self.appearance=="system" ? nil : (self.appearance=="dark" ? .dark : .light) }

#if !STRUCTURED_APP
    var newNoteProfile:EditingProfile {
        let tag=["title":"h1","heading":"h2","subheading":"h3"][self.newNoteStyle]
        return EditingProfile(titleTemplate:tag.map { "<div><\($0)>\(NoteCodec.titleToken)</\($0)></div>" })
    }
#endif
}
