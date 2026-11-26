import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(GrowthStore.self) private var growth
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var showOnboarding = false
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(AppLanguage.key) private var language = AppLanguage.en.rawValue

    var body: some View {
        let hue = model.module.hue

        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 248)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
            moduleView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Rebuild the content on a language change. Kept off the outer view so the
        // `.onAppear` below (rescan / onboarding logic) doesn't run again.
        .id(language)
        .background(HueBackground(hue: hue).animation(.easeInOut(duration: 0.35), value: model.module))
        .environment(\.hue, hue)
        .overlay {
            if let request = model.review {
                ReviewSheet(request: request) { model.review = nil }
                    .id(language)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(text: toast)
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.review?.id)
        .animation(.easeOut(duration: 0.15), value: model.toast)
        .foregroundStyle(DS.text)
        .tint(.white)
        .navigationTitle("Yeet")
        .frame(minWidth: 1180, minHeight: 680)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView {
                didOnboard = true
                showOnboarding = false
                model.rescan()
                growth.startSchedule()
            }
            .id(language)
        }
        .onAppear {
            model.refreshDisk()
            // Consume the flag on the first appearance only, so a later "Open Yeet" never
            // dismisses the window again.
            let atLogin = AppDelegate.launchedAtLogin
            AppDelegate.launchedAtLogin = false
            if didOnboard && FolderAccess.isGranted {
                if atLogin && BackgroundMode.isOn {
                    // Started at login: stay in the menu bar; the window opens from there.
                    growth.startSchedule()
                    Task { @MainActor in dismissWindow(id: "main") }
                    return
                }
                model.rescan(announce: false)
                growth.startSchedule()
            } else {
                showOnboarding = true
            }
        }
    }

    @ViewBuilder
    private var moduleView: some View {
        switch model.module {
        case .overview: OverviewView()
        case .devCaches, .systemJunk: CacheModuleView(module: model.module).id(model.module)
        case .largeFiles: LargeFilesView()
        case .duplicates: DuplicatesView()
        case .browsers: BrowsersView()
        case .apps: AppsView()
        case .startup: StartupView()
        case .growth: GrowthView()
        case .health: HealthView()
        }
    }
}
