import ServiceManagement
import SwiftUI

struct RadioSettingsView: View {
    @AppStorage("RadioWave.launchAtLogin") private var launchAtLogin = false
    @AppStorage("RadioWave.autoplayOnLaunch") private var autoplayOnLaunch = false
    @StateObject private var imageGeneration = ImageGenerationService.shared
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

            Section("生图模型") {
                SettingToggleRow(
                    title: "生成音乐背景",
                    detail: "检测到曲目信息后，为主窗口生成氛围背景",
                    isOn: $imageGeneration.isEnabled
                )

                LabeledContent("背景透明度") {
                    HStack(spacing: 12) {
                        Slider(value: $imageGeneration.backgroundTransparency, in: 0...1)
                        Text("\(Int((imageGeneration.backgroundTransparency * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }

                LabeledContent("背景模糊") {
                    HStack(spacing: 12) {
                        Slider(value: $imageGeneration.backgroundBlurRadius, in: 0...40, step: 1)
                        Text("\(Int(imageGeneration.backgroundBlurRadius)) pt")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                TextField(
                    "API 地址",
                    text: $imageGeneration.baseURL,
                    prompt: Text("https://api.example.com/v1")
                )
                    .textFieldStyle(.roundedBorder)
                    .help("填写兼容 OpenAI API 的服务地址，程序会在末尾请求 /models 和 /images/generations")

                SecureField("API Key", text: $imageGeneration.apiKey)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Picker("模型", selection: $imageGeneration.selectedModel) {
                        if imageGeneration.availableModels.isEmpty {
                            Text("请先获取模型").tag("")
                        }
                        ForEach(imageGeneration.availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .disabled(imageGeneration.availableModels.isEmpty)

                    Button {
                        Task { await imageGeneration.refreshModels() }
                    } label: {
                        if imageGeneration.isLoadingModels {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 78)
                        } else {
                            Text("获取模型")
                                .frame(width: 78)
                        }
                    }
                    .disabled(imageGeneration.isLoadingModels || imageGeneration.baseURL.isEmpty)
                }

                if let statusMessage = imageGeneration.statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(imageGeneration.statusIsError ? .red : .secondary)
                }

                Text("检测到曲目信息时，使用所选模型生成主界面背景。API Key 保存在钥匙串中；HTTP 请求本身不加密。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let loginItemError {
                Text(loginItemError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 500)
        .navigationTitle("设置")
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .task {
            guard !imageGeneration.baseURL.isEmpty else { return }
            await imageGeneration.refreshModels()
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
