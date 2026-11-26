import Foundation
import Darwin

// Private extension discovery API used for our own embedded preparation helper.
// No PID, debugger script or attach operation is accepted by this transport.
@objc private protocol TCClassicFactory {
    @objc(extensionWithIdentifier:error:)
    func lookup(_ identifier: String) throws -> AnyObject
}
@objc private protocol TCClassicEndpoint {
    @objc(beginExtensionRequestWithInputItems:completion:)
    func begin(_ items: [Any], completion: @escaping (NSUUID?) -> Void)
    @objc(setRequestCompletionBlock:)
    func onCompletion(_ block: @escaping (NSUUID?, [Any]?) -> Void)
    @objc(setRequestCancellationBlock:)
    func onCancellation(_ block: @escaping (NSUUID?, NSError?) -> Void)
    @objc(setRequestInterruptionBlock:)
    func onInterruption(_ block: @escaping (NSUUID?) -> Void)
}

@MainActor final class TCClassicSession {
    private let retained: AnyObject
    private let endpoint: TCClassicEndpoint
    private var callback: ((Result<TCClassicReply,Error>) -> Void)?
    static func open() throws -> TCClassicSession {
        guard let root=Bundle.main.builtInPlugInsURL,
              let helper=Bundle(url:root.appendingPathComponent("TCJITHelper.appex")),
              let id=helper.bundleIdentifier else {
            throw HelperBundlePolicy.issue(7,"Embedded helper missing. Keep app extensions when signing.")
        }
        let meta=helper.infoDictionary?["NSExtension"] as? [String:Any]
        if getenv("LC_HOME_PATH") != nil {
            let info=NSDictionary(contentsOfFile: Bundle.main.bundleURL.appendingPathComponent("LCAppInfo.plist").path)
            guard getenv("LP_HOME_PATH")==nil, info?["helperProcessesSupport"] as? Bool == true,
                  FileManager.default.fileExists(atPath:helper.bundleURL.appendingPathComponent("LCAppExtension.plist").path) else {
                throw HelperBundlePolicy.issue(8,"LiveContainer helper support is not prepared. Enable it and reinstall the guest, or install standalone.")
            }
            guard meta?["NSExtensionPointIdentifier"] as? String == "com.apple.ar.viewer" else {
                throw HelperBundlePolicy.issue(6,"Classic helper extension metadata missing.")
            }
        } else {
            try HelperBundlePolicy.validate(host:Bundle.main.bundleIdentifier,helper:id,point:meta?["NSExtensionPointIdentifier"] as? String)
        }
        if NSClassFromString("NSExtension")==nil {
            _=dlopen("/System/Library/Frameworks/ExtensionFoundation.framework/ExtensionFoundation",RTLD_NOW)
        }
        guard let cls=NSClassFromString("NSExtension") else { throw HelperBundlePolicy.issue(9,"Extension discovery API unavailable.") }
        let factory=unsafeBitCast(cls as AnyObject,to:TCClassicFactory.self)
        let found=try factory.lookup(id)
        return TCClassicSession(found)
    }
    private init(_ object: AnyObject) {
        retained=object
        endpoint=unsafeBitCast(object,to:TCClassicEndpoint.self)
    }
    func send(_ request: TCClassicRequest, completion: @escaping (Result<TCClassicReply,Error>)->Void) throws {
        guard callback==nil else { throw HelperBundlePolicy.issue(10,"Helper request already active.") }
        let data=try JSONEncoder().encode(request)
        callback=completion
        endpoint.onCompletion { [weak self] _, items in
            let payload=(items?.first as? NSExtensionItem)?.userInfo?[TCClassicReply.key] as? Data
            Task { @MainActor in
                guard let payload, let reply=try? JSONDecoder().decode(TCClassicReply.self,from:payload) else {
                    self?.finish(.failure(HelperBundlePolicy.issue(11,"Helper returned no valid response.")));return
                }
                self?.finish(.success(reply))
            }
        }
        endpoint.onCancellation { [weak self] _, error in
            Task { @MainActor in self?.finish(.failure(error ?? HelperBundlePolicy.issue(12,"Helper cancelled."))) }
        }
        endpoint.onInterruption { [weak self] _ in
            Task { @MainActor in self?.finish(.failure(HelperBundlePolicy.issue(13,"Helper interrupted."))) }
        }
        let item=NSExtensionItem()
        item.userInfo=[TCClassicRequest.key:data]
        endpoint.begin([item]) { [weak self] identifier in
            if identifier==nil { Task { @MainActor in self?.finish(.failure(HelperBundlePolicy.issue(14,"Helper did not start."))) } }
        }
    }
    private func finish(_ result: Result<TCClassicReply,Error>) {
        let handler=callback;callback=nil;handler?(result)
    }
}
