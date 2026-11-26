import Foundation
import SwiftUI
import UIKit
import Combine
import UniformTypeIdentifiers
import Darwin

@MainActor final class Coordinator: ObservableObject {
    @Published var status = "Import an authorized pairing file. Game execution remains blocked."
    @Published var busy = false
    @Published private(set) var devicePrepared = false
    private var session: TCClassicSession?
    private var generation = UUID()
    private var deadline: Task<Void, Never>?
    private var pairingURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StikJIT/pairingFile.plist")
    }

    func importPairing(_ url: URL) {
        guard !busy else { status = "Finish the current check before importing."; return }
        status = "File received. Checking pairing record…"
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: PairingPolicy.maxBytes + 1) ?? Data()
            try PairingPolicy.validate(data)
            try FileManager.default.createDirectory(at: pairingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: pairingURL, options: [.atomic, .completeFileProtection])
            devicePrepared = false
            status = "RemoteRP format accepted. Validity against device not yet verified."
        } catch { status = "Pairing import failed: \(error.localizedDescription)" }
    }

    func removePairing() {
        guard !busy else { return }
        do {
            if FileManager.default.fileExists(atPath: pairingURL.path) {
                try FileManager.default.removeItem(at: pairingURL)
            }
            devicePrepared = false
            status = "Local pairing copy removed."
        } catch { status = "Unable to remove local pairing copy: \(error.localizedDescription)" }
    }

    func checkLocalAllocation() {
        guard !busy else { return }
        status = "Baseline: " + Self.memoryPermission()
    }

    func cancel() {
        // Preparation may already be running. Avoid starting another helper.
        status = "Current preparation is still active; wait for its result or close the app."
    }

    func prepare(pingOnly: Bool = false, combined: Bool = false) async {
        guard !busy else { return }
        if !pingOnly { devicePrepared=false }
        let token=UUID()
        generation=token
        busy=true
        status="Discovering installed classic helper…"
        do {
            guard pingOnly || TCHasDebugAuthorization() else {
                throw HelperBundlePolicy.issue(16,"Missing get-task-allow; device preparation not started.")
            }
            let data: Data?
            if pingOnly { data=nil }
            else {
                let handle=try FileHandle(forReadingFrom:pairingURL)
                defer { try? handle.close() }
                let bytes=try handle.read(upToCount:PairingPolicy.maxBytes+1) ?? Data()
                try PairingPolicy.validate(bytes)
                data=bytes
            }
            let active=try TCClassicSession.open()
            session=active
            let baseline=combined ? "Host get-task-allow: \(TCHasDebugAuthorization() ? "present":"absent")\nBaseline: \(Self.memoryPermission())\n" : ""
            deadline=Task { [weak self] in
                do { try await Task.sleep(for:.seconds(pingOnly ? 20:180)) } catch { return }
                guard let self,self.generation==token,self.busy else { return }
                self.status="Helper has not returned; close app if necessary. No second request started."
            }
            status=baseline+"Checking helper…"
            let operation: TCClassicRequest.Operation = pingOnly || combined ? .ping : .prepare
            try active.send(TCClassicRequest(operation:operation,pairing:operation == .ping ? nil:data)) { [weak self] result in
                guard let self,self.generation==token,self.busy else { return }
                switch result {
                case .failure(let error): self.finish(token,baseline+error.localizedDescription)
                case .success(let reply):
                    if combined && reply.success {
                        self.status=baseline+reply.message+"\nPreparing device…"
                        do {
                            try active.send(TCClassicRequest(operation:.prepare,pairing:data)) { [weak self] result in
                                switch result {
                                case .success(let response):
                                    self?.acceptPreparation(response,token:token)
                                    self?.finish(token,baseline+reply.message+"\n"+response.message)
                                case .failure(let error): self?.finish(token,baseline+error.localizedDescription)
                                }
                            }
                        } catch { self.finish(token,baseline+error.localizedDescription) }
                    } else {
                        if !pingOnly { self.acceptPreparation(reply,token:token) }
                        self.finish(token,baseline+reply.message)
                    }
                }
            }
        } catch { finish(token,"Preparation failed: \(error.localizedDescription)") }
    }

    private func acceptPreparation(_ reply: TCClassicReply, token: UUID) {
        guard generation==token,busy else { return }
        devicePrepared=reply.success && reply.devicePrepared
    }

    // Allocation only: never writes or executes generated instructions.
    private static func memoryPermission() -> String {
        let length = Int(getpagesize())
        let pointer = mmap(nil, length, PROT_READ | PROT_WRITE | PROT_EXEC,
                           MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0)
        guard pointer != MAP_FAILED else {
            let code = errno
            return "MAP_JIT permission denied (errno \(code)); no generated code executed."
        }
        guard munmap(pointer, length) == 0 else { return "MAP_JIT mapped but cleanup failed; no generated code executed." }
        return "MAP_JIT allocation and cleanup succeeded; executable-code and game allocator remain unverified."
    }

    private func finish(_ token: UUID, _ result: String) {
        guard generation == token, busy else { return }
        deadline?.cancel()
        deadline = nil
        generation = UUID()
        busy = false
        status = result
        session = nil
    }
}

@main struct TCJITHost: App {
    @StateObject private var coordinator = Coordinator()
    @State private var importing = false
    var body: some Scene {
        WindowGroup {
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("TC JIT preparation").font(.title)
                Text("Developer Mode and LocalDevVPN must be active. This is a diagnostic, not the game.")
                Text(coordinator.status).textSelection(.enabled)
                if coordinator.devicePrepared {
                    Text("Device preparation verified for this session. JIT execution not verified.").foregroundStyle(.green)
                }
                Button("Test bundled helper (no pairing)") { Task { await coordinator.prepare(pingOnly: true) } }.disabled(coordinator.busy)
                Button("Check baseline MAP_JIT allocation") { coordinator.checkLocalAllocation() }.disabled(coordinator.busy)
                Button("Import pairing file") {
                    coordinator.status = "Choose the pairing file in Files."
                    importing = true
                }.disabled(coordinator.busy)
                Button("Remove imported pairing file", role: .destructive) { coordinator.removePairing() }.disabled(coordinator.busy)
                Button("Run combined device readiness check") { Task { await coordinator.prepare(combined: true) } }.disabled(coordinator.busy)
                Button("Prepare device") { Task { await coordinator.prepare() } }.disabled(coordinator.busy)
                Text("Classic helper supports preparation only; debugger attach is not implemented in this build.").font(.footnote)
                if coordinator.busy { Button("Check pending request") { coordinator.cancel() } }
                Text("Game launch blocked: macOS JIT allocator is not yet compatible.").font(.footnote)
            }.padding()
            }.sheet(isPresented: $importing) {
                TCPairingPicker(
                    selected: { url in
                        importing = false
                        coordinator.importPairing(url)
                    },
                    cancelled: {
                        importing = false
                        coordinator.status = "File selection cancelled. No pairing file changed."
                    }
                ).ignoresSafeArea()
            }
        }
    }
}
