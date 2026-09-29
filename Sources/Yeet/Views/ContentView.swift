import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(GrowthStore.self) private var growth
    @AppStorage("didOnboard") private var didOnboard = false
    @State private var showOnboarding = false
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(AppLanguage.key) private var language = AppLanguage.en.rawValue

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 248)
            Rectangle().fill(DS.border).frame(width: 1)
            Group {
                if model.selection == .growth {
                    GrowthView()
                } else {
                    VStack(spacing: 0) {
                        HeaderView()
                        HStack(alignment: .top, spacing: 16) {
                            CacheTreeView()
                            InspectorView().frame(width: 300)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                        .frame(maxHeight: .infinity)
                        FooterBar()
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        // Rebuild the content on a language change. Kept off the outer view so the
        // `.onAppear` below (rescan / onboarding logic) doesn't run again.
        .id(language)
        .background(DS.bg)
        .overlay {
            if model.showConfirm {
                ConfirmOverlay().id(language).transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(text: toast)
                    .padding(.bottom, 76)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.showConfirm)
        .animation(.easeOut(duration: 0.15), value: model.toast)
        .toolbar {
            ToolbarItem(placement: .principal) {
                (Text("Yeet — ").fontWeight(.semibold)
                    + Text(L("\(Fmt.size(model.grandTotal)) cleanable · \(Fmt.size(model.disk.free)) free on disk",
                             "\(Fmt.size(model.grandTotal)) có thể dọn · \(Fmt.size(model.disk.free)) trống trên ổ đĩa"))
                        .foregroundColor(DS.text2))
                    .font(.system(size: 13))
                    .foregroundColor(DS.text)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.rescan()
                } label: {
                    HStack(spacing: 6) {
                        SpinningIcon(systemName: "arrow.clockwise", active: model.phase == .scanning)
                        Text(model.phase == .scanning ? L("Scanning…", "Đang quét…") : L("Rescan", "Quét lại"))
                    }
                }
                .buttonStyle(OutlineButtonStyle(height: 28, fontSize: 13, horizontalPadding: 12))
                .disabled(model.phase != .idle || model.showConfirm)
                .help(L("Rescan all caches (⌘R)", "Quét lại toàn bộ cache (⌘R)"))
            }
        }
        .toolbarBackground(Color.white, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .navigationTitle("Yeet")
        .frame(minWidth: 1180, minHeight: 640)
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
            if didOnboard && (!BuildFlavor.isAppStore || FolderAccess.isGranted) {
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
}
