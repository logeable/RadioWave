import ServiceManagement
import SwiftUI

struct RadioSettingsView: View {
    @ObservedObject var library: RadioLibraryViewModel
    @AppStorage("RadioWave.launchAtLogin") private var launchAtLogin = false
    @AppStorage("RadioWave.autoplayOnLaunch") private var autoplayOnLaunch = false
    @StateObject private var imageGeneration = ImageGenerationService.shared
    @State private var loginItemError: String?
    @State private var iconCacheCount = 0
    @State private var backgroundCacheCount = 0
    @State private var cacheMessage: String?

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

            Section("缓存") {
                CacheManagementRow(
                    title: "电台图标",
                    detail: "已缓存 \(iconCacheCount) 个",
                    symbol: "photo",
                    buttonTitle: "清空",
                    action: clearIconCache
                )

                CacheManagementRow(
                    title: "曲目背景",
                    detail: "已缓存 \(backgroundCacheCount) 张（最多 100 张）",
                    symbol: "music.note",
                    buttonTitle: "清空",
                    action: clearBackgroundCache
                )

                LabeledContent {
                    HStack(spacing: 6) {
                        Text("已缓存 \(library.cachedStationCount) 个电台")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if library.isLoading || library.isRefreshing {
                            if let progress = library.syncProgressFraction {
                                ProgressView(value: progress)
                                    .frame(width: 42)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(library.syncProgressPercentage.map { "\($0)%" } ?? "准备中")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            Button("重新缓存", action: library.recacheStations)
                                .controlSize(.small)
                            Button("清空", action: clearStationCache)
                                .controlSize(.small)
                        }
                    }
                } label: {
                    Label("电台数据", systemImage: "dot.radiowaves.left.and.right")
                }

                if let cacheMessage {
                    Text(cacheMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let loginItemError {
                Text(loginItemError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520, height: 680)
        .navigationTitle("设置")
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .task {
            iconCacheCount = await StationIconCache.shared.cachedImageCount()
            backgroundCacheCount = await imageGeneration.cachedBackgroundCount()
            guard !imageGeneration.baseURL.isEmpty else { return }
            await imageGeneration.refreshModels()
        }
    }

    private func clearIconCache() {
        Task {
            do {
                try await StationIconCache.shared.clear()
                iconCacheCount = 0
                cacheMessage = "已清空电台图标缓存。"
            } catch {
                cacheMessage = "清空电台图标缓存失败：\(error.localizedDescription)"
            }
        }
    }

    private func clearBackgroundCache() {
        Task {
            do {
                try await imageGeneration.clearBackgroundCache()
                backgroundCacheCount = 0
                cacheMessage = "已清空曲目背景缓存。"
            } catch {
                cacheMessage = "清空曲目背景缓存失败：\(error.localizedDescription)"
            }
        }
    }

    private func clearStationCache() {
        library.clearStationCache()
        cacheMessage = "已清空电台数据缓存；收藏内容未受影响。"
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

private struct CacheManagementRow: View {
    let title: String
    let detail: String
    let symbol: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(buttonTitle, action: action)
                    .controlSize(.small)
            }
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}
