import Foundation
import StikJIT

@objc(TCClassicHelperHandler)
final class TCClassicHelperHandler: NSObject, NSExtensionRequestHandling {
    private static let queue=DispatchQueue(label:"com.sky9662.tcjithost.prepare")
    func beginRequest(with context: NSExtensionContext) {
        let bytes=(context.inputItems.first as? NSExtensionItem)?.userInfo?[TCClassicRequest.key] as? Data
        Self.queue.async {
            let reply: TCClassicReply
            if let bytes, bytes.count <= 2*PairingPolicy.maxBytes,
               let request=try? JSONDecoder().decode(TCClassicRequest.self,from:bytes) {
                reply=Self.handle(request)
            } else { reply=TCClassicReply(message:"Invalid preparation request.",success:false) }
            let item=NSExtensionItem()
            item.userInfo=[TCClassicReply.key:(try? JSONEncoder().encode(reply)) ?? Data()]
            context.completeRequest(returningItems:[item],completionHandler:nil)
        }
    }
    private static func handle(_ request: TCClassicRequest) -> TCClassicReply {
        if request.operation == .ping {
            return TCClassicReply(message:"TCJIT protocol 2: helper reachable. No debugger operation.",success:true)
        }
        do {
            guard let data=request.pairing else { throw HelperBundlePolicy.issue(1,"Pairing file missing.") }
            try PairingPolicy.validate(data)
            let fm=FileManager.default
            let folder=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
            try fm.createDirectory(at:folder,withIntermediateDirectories:false)
            defer { try? fm.removeItem(at:folder) }
            let temporary=folder.appendingPathComponent("pairing.plist")
            try data.write(to:temporary,options:[.atomic,.completeFileProtection])
            let library=try fm.url(for:.libraryDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
            let cache=library.appendingPathComponent("StikJIT",isDirectory:true)
            try fm.createDirectory(at:cache,withIntermediateDirectories:true)
            switch StikJIT.prepareDevice(pairingFile:temporary,paths:DDIPaths.default(in:cache)) {
            case .ready(let security):
                let txm=security.isTXMPresent.map{$0 ? "present":"not present"} ?? "unknown"
                return TCClassicReply(message:"Device preparation ready; TXM: \(txm). Debugger not attached; game launch blocked.",success:true,txmPresent:security.isTXMPresent,devicePrepared:true)
            case .unreachable(let reason), .preparationFailed(let reason):
                return TCClassicReply(message:reason,success:false)
            @unknown default: return TCClassicReply(message:"Unrecognized readiness result.",success:false)
            }
        } catch { return TCClassicReply(message:error.localizedDescription,success:false) }
    }
}
