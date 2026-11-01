import Foundation
import Security

struct CloudSpan: Codable, Equatable, Sendable {
    var length:Int; var bold=false; var italic=false; var underline=false; var strikethrough=false; var link=""
}
struct CloudParagraph: Codable, Equatable, Sendable {
    var kind="body"; var text=""; var start=0; var indent=0; var blockQuoteLevel=0; var startNumber=0
    var done:Bool?; var spans:[CloudSpan]=[]; var tableID:String?; var separator:String?="\n"
    init(text:String="",kind:String="body") {self.text=text;self.kind=kind;spans=text.isEmpty ? [] : [CloudSpan(length:(text as NSString).length)]}
}
struct CloudTable: Codable, Equatable, Sendable {var id:String;var grid:[[String]]}
struct CloudDocument: Codable, Equatable, Sendable {var paragraphs:[CloudParagraph];var tables:[CloudTable]=[]}
struct CloudSummary: Codable, Identifiable, Sendable {var id:String;var title:String;var created:Double}
struct CloudSnapshot: Codable, Sendable {var id:String;var title:String;var tag:String;var document:CloudDocument;var created:Double}
struct CloudListing: Codable, Sendable {var folderID:String?;var notes:[CloudSummary]}
struct CloudSession: Codable, Sendable {var cookie:String;var clientId:String;var clientBuildNumber:String;var clientMasteringNumber:String;var capturedAt:String}
struct CloudAccount: Codable, Sendable {var session:CloudSession;var dsid:String;var host:String}
struct CloudFailure: Error, Codable, LocalizedError, Sendable {var code:String;var message:String;var errorDescription:String?{message}}
private struct CloudResponse<T:Decodable & Sendable>:Decodable {var ok:Bool;var result:T?;var error:CloudFailure?}

enum CloudKeychain {
    static let service="dev.notesplus.structured.icloud"
    static func load()->CloudAccount? {
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"session",kSecReturnData as String:true]
        var result:CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&result)==errSecSuccess,let data=result as? Data else{return nil}
        return try? JSONDecoder().decode(CloudAccount.self,from:data)
    }
    static func save(_ account:CloudAccount)throws {
        let data=try JSONEncoder().encode(account)
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"session"]
        let status=SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status==errSecItemNotFound {
            var item=query;item[kSecValueData as String]=data;item[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary,nil)==errSecSuccess else{throw CloudFailure(code:"KEYCHAIN",message:"iCloud 연결 정보를 키체인에 보관하지 못했습니다.")}
        } else if status != errSecSuccess {throw CloudFailure(code:"KEYCHAIN",message:"키체인 접근을 허용해 주세요.")}
    }
}
protocol CloudRequesting:Sendable {
    func request<T:Decodable & Sendable>(_ command:String,account:CloudAccount?,payload:[String:Any],as:T.Type) async throws ->T
}
extension CloudRequesting {
    func request<T:Decodable & Sendable>(_ command:String,account:CloudAccount?,as:T.Type) async throws ->T {try await request(command,account:account,payload:[:],as:T.self)}
}
actor CloudClient:CloudRequesting {
    let replica:String
    init() {
        let key="structuredReplicaID", defaults=UserDefaults.standard
        replica=defaults.string(forKey:key) ?? UUID().uuidString
        defaults.set(replica,forKey:key)
    }
    func request<T:Decodable & Sendable>(_ command:String,account:CloudAccount?,payload:[String:Any]=[:],as:T.Type) async throws ->T {
        var input=payload;input["command"]=command;input["replica"]=replica
        if let account {input["account"]=try JSONSerialization.jsonObject(with:JSONEncoder().encode(account))}
        let data=try JSONSerialization.data(withJSONObject:input)
        let raw:Data=try await Task.detached(priority:.utility) {
            guard let resources=Bundle.main.resourceURL else{throw CloudFailure(code:"BUILD",message:"연결 구성요소가 없습니다.")}
            let process=Process(),stdin=Pipe(),stdout=Pipe(),stderr=Pipe()
            process.executableURL=resources.appendingPathComponent("node")
            process.arguments=[resources.appendingPathComponent("bridge.mjs").path]
            process.standardInput=stdin;process.standardOutput=stdout;process.standardError=stderr
            // Credentials travel over the private pipe, never argv, env, or a temporary file.
            try process.run()
            stdin.fileHandleForWriting.write(data);try stdin.fileHandleForWriting.close()
            let output=stdout.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
            guard process.terminationStatus==0,!output.isEmpty else{throw CloudFailure(code:"PROCESS",message:"iCloud 연결 구성요소 실행에 실패했습니다.")}
            return output
        }.value
        let response=try JSONDecoder().decode(CloudResponse<T>.self,from:raw)
        if let result=response.result,response.ok{return result}
        throw response.error ?? CloudFailure(code:"RESPONSE",message:"iCloud 응답을 읽지 못했습니다.")
    }
}
