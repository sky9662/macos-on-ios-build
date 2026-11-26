import Foundation

enum PairingPolicy {
    static let maxBytes = 1024 * 1024
    static func validate(_ data: Data) throws {
        guard !data.isEmpty, data.count <= maxBytes,
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let record = object as? [String: Any], !record.isEmpty else {
            throw NSError(domain: "TCJIT", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid pairing property list."])
        }
        // Remote pairing uses Ed25519 keys, not lockdown certificates.
        // Check structure before replacing the previous local pairing file.
        guard let pub=record["public_key"] as? Data, pub.count==32,
              let priv=record["private_key"] as? Data, priv.count==32,
              let id=record["identifier"] as? String, !id.isEmpty else {
            throw NSError(domain:"TCJIT",code:15,userInfo:[NSLocalizedDescriptionKey:
                "Not a RemoteRP pairing record. Choose PairingFile_RemoteRP.plist; existing pairing unchanged."])
        }
    }
}

enum HelperBundlePolicy {
    static let hostID = "com.sky9662.tcjithost"
    static let helperID = hostID + ".helper"
    static func validate(host: String?, helper: String?, point: String?) throws {
        guard let host, !host.isEmpty else { throw issue(4,"Host bundle identifier missing.") }
        guard let helper, helper.hasPrefix(host + "."), helper.count > host.count+1 else {
            throw issue(5,"Embedded helper identifier does not match the installed host prefix.")
        }
        guard point == "com.apple.ar.viewer" else { throw issue(6,"Classic helper extension metadata missing.") }
    }
    static func issue(_ code: Int,_ message: String) -> NSError {
        NSError(domain:"TCJIT",code:code,userInfo:[NSLocalizedDescriptionKey:message])
    }
}
struct TCClassicRequest: Codable {
    enum Operation: String, Codable { case ping, prepare }
    static let key = "TCJIT.request.v2"
    let operation: Operation
    let pairing: Data?
}
struct TCClassicReply: Codable {
    static let key = "TCJIT.reply.v2"
    let message: String
    let success: Bool
    var txmPresent: Bool? = nil
    var devicePrepared: Bool = false
}
