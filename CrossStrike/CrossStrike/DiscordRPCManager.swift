import AppKit
import Combine

class DiscordRPCManager: ObservableObject {
    // MARK: - What you see in menu bar
    @Published var isCS2Running = false
    @Published var isRPCActive = false
    
    // MARK: - Private stuff (you don't need to touch these)
    private let workspace = NSWorkspace.shared
    private var cancellables = Set<AnyCancellable>()
    private var rpcProcess: Process?
    private let targetProcessName = "cs2.exe" // This must stay as "cs2.exe" - it's the process name to detect!
    private let appSupportFolder = "CrossStrike" // CHANGED: Folder name updated
    
    // NEW: Timer that checks for CS2 every 2 seconds
    private var checkTimer: Timer?
    private let checkInterval: TimeInterval = 2.0
    
    // MARK: - Initialization
    init() {
        print("🚀 DiscordRPCManager Initializing...")
        setupApplicationSupportFolder()
        setupProcessMonitoring()
        checkAlreadyRunning()
        startContinuousMonitoring()  // NEW: Starts the 2-second checker
    }
    
    // MARK: - Setup Methods
    private func setupApplicationSupportFolder() {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("❌ Failed to find Application Support directory")
            return
        }
        
        let folderURL = appSupportURL.appendingPathComponent(appSupportFolder)
        
        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            print("✅ Created CrossStrike folder at: \(folderURL.path)") // UPDATED: Message
        } catch {
            print("❌ Failed to create folder: \(error)")
        }
    }
    
    private func setupProcessMonitoring() {
        print("🔍 Setting up process monitoring...")
        
        let center = workspace.notificationCenter
        
        // Monitor app launches
        center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.handleAppLaunch(notification)
            }
            .store(in: &cancellables)
        
        // Monitor app terminations
        center.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.handleAppQuit(notification)
            }
            .store(in: &cancellables)
        
        print("✅ Process monitoring setup complete")
    }
    
    // NEW: Continuous monitoring that runs every 2 seconds
    private func startContinuousMonitoring() {
        print("🔄 Starting 2-second checker...")
        
        // Stop any existing timer
        checkTimer?.invalidate()
        
        // Create new timer that runs every 2 seconds
        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.checkForCS2()
        }
        
        print("✅ 2-second checker started")
    }
    
    private func stopContinuousMonitoring() {
        print("🔄 Stopping 2-second checker...")
        checkTimer?.invalidate()
        checkTimer = nil
    }
    
    // NEW: This checks for CS2 every 2 seconds
    private func checkForCS2() {
        let runningApps = workspace.runningApplications
        
        var foundCS2 = false
        
        // Look through all running apps
        for app in runningApps {
            if let executableURL = app.executableURL,
               executableURL.lastPathComponent == targetProcessName {
                foundCS2 = true
                
                // If CS2 is running but we don't know it
                if !isCS2Running {
                    print("🔄 2-SECOND CHECK: Found CS2! (PID: \(app.processIdentifier))")
                    DispatchQueue.main.async {
                        self.isCS2Running = true
                        self.startDiscordRPC()
                    }
                }
                break
            }
        }
        
        // If CS2 is NOT running but we think it is
        if !foundCS2 && isCS2Running {
            print("🔄 2-SECOND CHECK: CS2 disappeared")
            DispatchQueue.main.async {
                self.isCS2Running = false
                self.stopDiscordRPC()
            }
        }
    }
    
    private func checkAlreadyRunning() {
        print("🔎 Checking for already running CS2...")
        let runningApps = workspace.runningApplications
        
        for app in runningApps {
            if let executableURL = app.executableURL,
               executableURL.lastPathComponent == targetProcessName {
                print("✅ CS2 is already running!")
                DispatchQueue.main.async {
                    self.isCS2Running = true
                    self.startDiscordRPC()
                }
                break
            }
        }
    }
    
    // MARK: - Event Handlers
    private func handleAppLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let executableURL = app.executableURL else {
            print("⚠️ Launch notification missing app info")
            return
        }
        
        let appName = executableURL.lastPathComponent
        print("🟢 SYSTEM NOTIFICATION: App Launched - \(appName)")
        
        if appName == targetProcessName {
            print("🎮 CS2 LAUNCHED - Starting Discord RPC")
            DispatchQueue.main.async {
                self.isCS2Running = true
                self.startDiscordRPC()
            }
        }
    }
    
    private func handleAppQuit(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let executableURL = app.executableURL else {
            print("⚠️ Quit notification missing app info")
            return
        }
        
        let appName = executableURL.lastPathComponent
        print("🔴 SYSTEM NOTIFICATION: App Quit - \(appName)")
        
        if appName == targetProcessName {
            print("🛑 CS2 TERMINATED - Stopping Discord RPC")
            DispatchQueue.main.async {
                self.isCS2Running = false
                self.stopDiscordRPC()
            }
        }
    }
    
    // MARK: - Discord RPC Methods
    func startDiscordRPC() {
        guard !isRPCActive else {
            print("⚠️ Discord RPC already active")
            return
        }
        
        print("🟡 Starting Discord RPC...")
        
        // Stop any existing process first
        stopDiscordRPC()
        
        // Create the Python script
        let scriptContent = createPythonRPCScript()
        
        // Save and execute the script
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            print("❌ Failed to find Application Support directory")
            return
        }
        
        let scriptURL = appSupportURL
            .appendingPathComponent(appSupportFolder)
            .appendingPathComponent("discord_rpc.py")
        
        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            print("✅ Script saved to: \(scriptURL.path)")
            
            // Make script executable
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            
            // Execute the script
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [scriptURL.path]
            
            // Capture output for debugging
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            let outputHandle = pipe.fileHandleForReading
            outputHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    print("🐍 Python: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
            
            try process.run()
            rpcProcess = process
            isRPCActive = true
            
            print("✅ Discord RPC started successfully")
            
        } catch {
            print("❌ Failed to start Discord RPC: \(error)")
        }
    }
    
    private func createPythonRPCScript() -> String {
        return """
#!/usr/bin/env python3
# Created by irakli.akhvleda
import sys
import os
sys.path.append(os.path.expanduser("~/Library/Python/3.9/lib/python/site-packages"))
sys.path.append("/usr/local/lib/python3.9/site-packages")

try:
    from pypresence import Presence
    import time
    
    print("Initializing Discord RPC...")
    
    # Discord Application ID for CS2
    CLIENT_ID = "1158877933042143272"
    
    # Connect to Discord
    RPC = Presence(CLIENT_ID)
    
    try:
        RPC.connect()
        print("Connected to Discord!")
    except Exception as e:
        print(f"Failed to connect to Discord: {e}")
        sys.exit(1)
    
    # Update Rich Presence
    RPC.update(
        details="Ranked Competitive",
        state="Smurfing",
        start=int(time.time()),  # Start timer now
        large_image="cs2",
        large_text="Counter-Strike 2"
    )
    
    print("Rich Presence updated successfully!")
    print("Details: Ranked Competitive")
    print("State: Smurfing")
    print("Timer started")
    
    # Keep the connection alive
    try:
        while True:
            time.sleep(15)
    except KeyboardInterrupt:
        print("\\nShutting down RPC...")
    finally:
        RPC.close()
        print("Disconnected from Discord")

except ImportError:
    print("ERROR: pypresence module not found!")
    print("Please install it by running: pip3 install pypresence")
    sys.exit(1)
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
"""
    }
    
    func stopDiscordRPC() {
        guard isRPCActive else { return }
        
        print("🟡 Stopping Discord RPC...")
        
        if let process = rpcProcess, process.isRunning {
            process.terminate()
            print("✅ Discord RPC process terminated")
        }
        
        rpcProcess = nil
        isRPCActive = false
    }
    
    // MARK: - Cleanup
    func shutdown() {
        print("🛑 Shutting down DiscordRPCManager...")
        stopContinuousMonitoring()  // NEW: Stops the 2-second checker
        stopDiscordRPC()
        cancellables.removeAll()
    }
    
    deinit {
        shutdown()
    }
}
