import AudioCore
import SwiftUI

@main
struct AudioExtractorApp: App {
    @StateObject private var app: AppModel
    @StateObject private var player = PlayerService()

    init() {
        PlayerService.configureSession()
        let dir = UITestSupport.isUITesting ? UITestSupport.testLibraryDirectory() : LibraryStore.defaultDirectory()
        _app = StateObject(wrappedValue: AppModel(directory: dir))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(player)
                .onOpenURL { url in
                    // "Open in 音频提取" from other apps / Files.
                    app.importFile(at: url)
                }
                .task {
                    if UITestSupport.wantsTone, let tone = try? UITestSupport.makeTone() {
                        app.openEditor(with: tone)
                    }
                    await app.fillMissingDurations()
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var player: PlayerService
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $app.selectedTab) {
            NavigationStack(path: $app.homePath) {
                HomeView()
                    .navigationDestination(for: ImportedSource.self) { source in
                        EditorView(source: source, defaults: app.defaultOptions())
                    }
            }
            .tabItem { Label("提取", systemImage: "waveform.badge.plus") }
            .tag(AppTab.home)

            NavigationStack {
                LibraryView()
            }
            .tabItem { Label("作品库", systemImage: "music.note.list") }
            .tag(AppTab.library)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("设置", systemImage: "gearshape") }
            .tag(AppTab.settings)
        }
        .overlay {
            if app.isImporting { LoadingOverlay(text: "正在导入…") }
        }
        .alert("提示", isPresented: Binding(get: { app.alertMessage != nil }, set: { if !$0 { app.alertMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(app.alertMessage ?? "")
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { app.refresh() }
        }
    }
}
