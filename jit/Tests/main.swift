import Foundation

// Synthetic plist only; this checks the input boundary, not device pairing validity.
func expectRejected(_ data: Data) {
    do {
        try PairingPolicy.validate(data)
        fatalError("Invalid pairing payload was accepted")
    } catch { }
}
func encode(_ value: Any, format: PropertyListSerialization.PropertyListFormat = .xml) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: value, format: format, options: 0)
}
expectRejected(Data())
expectRejected(Data("not a property list".utf8))
expectRejected(Data(repeating: 0, count: PairingPolicy.maxBytes + 1))
expectRejected(try encode([String: String]()))
expectRejected(try encode(["synthetic array"]))
expectRejected(try encode(["Fixture":"synthetic unrelated plist"]))
expectRejected(try encode(["HostCertificate":Data([1,2,3])]))
let fixture:[String:Any]=["public_key":Data(repeating:0,count:32),
                          "private_key":Data(repeating:0,count:32),
                          "identifier":"synthetic-not-a-real-pairing-record"]
try PairingPolicy.validate(encode(fixture))
try PairingPolicy.validate(encode(fixture,format:.binary))
var broken=fixture;broken["public_key"]=Data([0]);expectRejected(try encode(broken))
broken=fixture;broken["private_key"]=nil;expectRejected(try encode(broken))
broken=fixture;broken["identifier"]="";expectRejected(try encode(broken))
print("RemoteRP pairing boundary tests passed (12 cases; synthetic records only)")

let point="com.apple.ar.viewer"
try HelperBundlePolicy.validate(host:HelperBundlePolicy.hostID,helper:HelperBundlePolicy.helperID,point:point)
let renamed=HelperBundlePolicy.hostID+".TEAMTEST"
try HelperBundlePolicy.validate(host:renamed,helper:renamed+".helper",point:point)
func rejectBundle(_ host:String?,_ helper:String?,_ extensionPoint:String?,_ code:Int) {
    do { try HelperBundlePolicy.validate(host:host,helper:helper,point:extensionPoint);fatalError("Invalid helper accepted") }
    catch { precondition((error as NSError).code==code) }
}
rejectBundle(renamed,HelperBundlePolicy.helperID,point,5)
rejectBundle(nil,HelperBundlePolicy.helperID,point,4)
rejectBundle(renamed,renamed+"X.helper",point,5)
rejectBundle(renamed,nil,point,5)
rejectBundle(renamed,renamed+".helper","other",6)
rejectBundle(renamed,renamed+".helper",nil,6)
let ping=TCClassicRequest(operation:.ping,pairing:nil)
let decoded=try JSONDecoder().decode(TCClassicRequest.self,from:JSONEncoder().encode(ping))
precondition(decoded.operation == .ping && decoded.pairing==nil)
print("Classic helper signing-prefix and request tests passed (9 cases)")

let prepared=TCClassicReply(message:"synthetic",success:true,txmPresent:true,devicePrepared:true)
let parsed=try JSONDecoder().decode(TCClassicReply.self,from:JSONEncoder().encode(prepared))
precondition(parsed.success && parsed.txmPresent==true && parsed.devicePrepared)
let pingReply=TCClassicReply(message:"synthetic ping",success:true)
precondition(!pingReply.devicePrepared && pingReply.txmPresent==nil)
print("Typed preparation response tests passed (2 cases)")
