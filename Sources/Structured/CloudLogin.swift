import AppKit
import WebKit

@MainActor final class CloudLogin:NSObject,WKNavigationDelegate,WKUIDelegate {
    private var window:NSWindow?
    private var web:WKWebView?
    private let client:any CloudRequesting
    var onAccount:((CloudAccount)->Void)?
    private var status:NSTextField?
    init(client:any CloudRequesting) {self.client=client}
    func show() {
        if let window {window.makeKeyAndOrderFront(nil);return}
        let config=WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web=WKWebView(frame:.zero,configuration:config);self.web=web
        web.navigationDelegate=self;web.uiDelegate=self
        let root=NSView(frame:NSRect(x:0,y:0,width:1000,height:780))
        web.frame=NSRect(x:0,y:58,width:1000,height:722);web.autoresizingMask=[.width,.height];root.addSubview(web)
        let button=NSButton(title:"로그인 완료 · 연결",target:self,action:#selector(connect))
        button.frame=NSRect(x:800,y:13,width:180,height:32);button.autoresizingMask=[.minXMargin];button.bezelStyle = .rounded;root.addSubview(button)
        let status=NSTextField(labelWithString:"Apple 페이지에서 로그인한 뒤 연결을 누르세요.")
        status.frame=NSRect(x:20,y:18,width:760,height:22);status.autoresizingMask=[.width];root.addSubview(status);self.status=status
        let win=NSWindow(contentRect:root.bounds,styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        win.title="NotesPlus — iCloud 연결";win.contentView=root;win.isReleasedWhenClosed=false;win.center();win.makeKeyAndOrderFront(nil);window=win
        web.load(URLRequest(url:URL(string:"https://www.icloud.com/notes/")!))
    }
    @objc private func connect() {
        status?.stringValue="연결 확인 중…"
        web?.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            Task { @MainActor in
                guard let self else{return}
                let cookie=cookies.filter {let d=$0.domain.trimmingCharacters(in:CharacterSet(charactersIn:"."));return d=="icloud.com" || d.hasSuffix(".icloud.com")}.map{"\($0.name)=\($0.value)"}.joined(separator:"; ")
                guard !cookie.isEmpty else{self.status?.stringValue="Apple 로그인을 먼저 완료해 주세요.";return}
                let session=CloudSession(cookie:cookie,clientId:UUID().uuidString,clientBuildNumber:"2624Build27",clientMasteringNumber:"2624Build27",capturedAt:ISO8601DateFormatter().string(from:Date()))
                do {
                    let payload=["session":try JSONSerialization.jsonObject(with:JSONEncoder().encode(session))]
                    let account=try await self.client.request("authorize",account:nil,payload:payload,as:CloudAccount.self)
                    try await Task.detached(priority:.userInitiated){try CloudKeychain.save(account)}.value
                    self.onAccount?(account);self.window?.close()
                } catch {self.status?.stringValue=error.localizedDescription}
            }
        }
    }
    func webView(_ webView:WKWebView,createWebViewWith configuration:WKWebViewConfiguration,for navigationAction:WKNavigationAction,windowFeatures:WKWindowFeatures)->WKWebView? {
        // Apple sign-in links that target a new window stay in the visible login window.
        if navigationAction.targetFrame==nil {webView.load(navigationAction.request)}
        return nil
    }
}
