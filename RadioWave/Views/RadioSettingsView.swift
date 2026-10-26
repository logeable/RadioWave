import ServiceManagement
import SwiftUI

struct RadioSettingsView: View {
    @AppStorage("RadioWave.launchAtLogin") private var launchAtLogin = false
    @AppStorage("RadioWave.autoplayOnLaunch") private var autoplayOnLaunch = false
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section("通用") {
                SettingToggleRow(
                    title: "开机时启动",
                    detail: "登录 macOS 后自动打开 Radio",
                    isOn: loginItemBinding
                )
                SettingToggleRow(
                    title: "启动时自动播放",
                    detail: "自动播放上次收听的电台",
                    isOn: $autoplayOnLaunch
                )
                LabeledContent("外观", value: "跟随 macOS")
            }

            if let loginItemError {
                Text(loginItemError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 480, height: 300)
        .navigationTitle("设置")
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private var loginItemBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchAtLogin = enabled
                    loginItemError = nil
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                    loginItemError = "无法更改登录启动设置：\(error.localizedDescription)"
                }
            }
        )
    }
}
