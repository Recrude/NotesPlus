import AppKit
import Foundation
_ = NSApplication.shared
let source=NSWorkspace.shared.icon(forFile:"/System/Applications/Notes.app")
let directory=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
let representations=NSBitmapImageRep.imageReps(with:source.tiffRepresentation!).compactMap { $0 as? NSBitmapImageRep }
for size in [16,32,64,128,256,512,1024] {
    let bitmap=representations.first { $0.pixelsWide==size && $0.pixelsHigh==size }!
    precondition(bitmap.pixelsWide==size && bitmap.pixelsHigh==size)
    try bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("native-\(size).png"))
}
