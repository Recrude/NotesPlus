import AppKit
import SwiftUI

enum TimestampFormat {
    static let standard = "yyyy/MM/dd HH:mm"
    static let compact = "yyyyMMdd HHmmss"
    static func string(date:Date = Date(),format:String,timeZone:TimeZone = .current)->String {
        let formatter=DateFormatter()
        formatter.locale=Locale(identifier:"en_US_POSIX")
        formatter.calendar=Calendar(identifier:.gregorian)
        formatter.timeZone=timeZone
        formatter.dateFormat=format
        return formatter.string(from:date)
    }
    static func validated(_ format:String)->String {
        // Bound the user-controlled pattern and keep timestamps to a single line.
        guard !format.trimmingCharacters(in:.whitespaces).isEmpty,format.count<=120,
              !format.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}) else{return standard}
        return format
    }
}

enum TimestampShortcut {
    static let keys=Array("abcdefghijklmnopqrstuvwxyz0123456789").map(String.init)
    // Command + another modifier avoids consuming ordinary typing and editing shortcuts.
    static let combinations=["control","option","shift","controlShift","optionShift","controlOption","controlOptionShift"]
    static func modifiers(_ value:String)->EventModifiers {
        switch value {
        case "option": return [.command,.option]
        case "shift": return [.command,.shift]
        case "controlShift": return [.command,.control,.shift]
        case "optionShift": return [.command,.option,.shift]
        case "controlOption": return [.command,.control,.option]
        case "controlOptionShift": return [.command,.control,.option,.shift]
        default: return [.command,.control]
        }
    }
    static func label(_ value:String)->String {
        switch value {
        case "option": return "⌥⌘"
        case "shift": return "⇧⌘"
        case "controlShift": return "⌃⇧⌘"
        case "optionShift": return "⌥⇧⌘"
        case "controlOption": return "⌃⌥⌘"
        case "controlOptionShift": return "⌃⌥⇧⌘"
        default: return "⌃⌘"
        }
    }
    static func reserved(key:String,combination:String)->Bool {
        // Preserve common app/system editing and window commands.
        if combination=="shift" {return ["a","c","d","f","g","h","n","o","p","q","s","t","v","w","z","3","4","5"].contains(key)}
        if combination=="option" {return ["c","d","f","h","i","m","q","s","t","v","w"].contains(key)}
        if combination=="control" {return ["d","f","q"].contains(key)}
        if combination=="optionShift" {return ["v","s"].contains(key)}
        return false
    }
}
