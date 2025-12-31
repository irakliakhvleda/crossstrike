import SwiftUI
import LaunchAtLogin


@main
struct CrossStrikeApp: App {
    @StateObject private var rpcManager = DiscordRPCManager()
    
    var body: some Scene {
        // 2. MENU BAR TITLE
        MenuBarExtra("CrossStrike", systemImage: "gamecontroller.fill") {
            VStack(alignment: .leading, spacing: 8) {
                // 3. MENU HEADER
                Text("CrossStrike Rich Presence")
                    .font(.headline)
                    .padding(.horizontal)
                
                Divider()
                
                LaunchAtLogin.Toggle("Launch at Login")
                    .padding(.horizontal)
                
                Divider()
                
                // 4. STATUS DISPLAY TEXT
                HStack {
                    Circle()
                        .fill(rpcManager.isCS2Running ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(rpcManager.isCS2Running ? "CrossStrike: Running" : "CrossStrike: Not Running")
                        .font(.caption)
                    Spacer()
                    if rpcManager.isRPCActive {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        Text("Discord: Active")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                
                Divider()
                
                Button("Quit") {
                    rpcManager.shutdown()
                    NSApp.terminate(nil)
                }
                .padding(.horizontal)
                .keyboardShortcut("q")
                
                // 5. ATTRIBUTION
                Divider()
                Text("Made by irakli.akhvleda")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 4)
            }
            .padding(.vertical, 8)
            .frame(width: 280)
        }
        .menuBarExtraStyle(.window)
    }
}
