import AppKit
import SwiftUI

struct OnboardingView: View {
    var onContinue: () -> Void
    @State private var ready = !BuildFlavor.isAppStore || FolderAccess.isGranted

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Welcome to Yeet", "Chào mừng đến với Yeet"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DS.text)
                    Text(L("Scan and clean caches from Xcode, npm, Yarn, Gradle, Git and Claude Code.", "Quét và dọn cache của Xcode, npm, Yarn, Gradle, Git và Claude Code."))
                        .font(.system(size: 13))
                        .foregroundStyle(DS.text2)
                }
            }

            Text(LocalizedStringKey(BuildFlavor.isAppStore
                 ? L("To measure sizes accurately, Yeet needs to read folders like ~/Library/Developer, ~/.npm, ~/.gradle and your project folders. The App Store version runs in a sandbox, so you need to **choose your Home folder** once. Yeet remembers this permission for next time.",
                     "Để đo chính xác dung lượng, Yeet cần đọc các thư mục như ~/Library/Developer, ~/.npm, ~/.gradle và thư mục dự án của bạn. Bản App Store chạy trong sandbox, nên bạn cần **chọn thư mục Home** một lần. Yeet ghi nhớ quyền này cho các lần sau.")
                 : L("To measure sizes accurately, Yeet needs to read folders like ~/Library/Developer, ~/.npm, ~/.gradle and your project folders. Grant Yeet **Full Disk Access** in System Settings → Privacy & Security → Full Disk Access.",
                     "Để đo chính xác dung lượng, Yeet cần đọc các thư mục như ~/Library/Developer, ~/.npm, ~/.gradle và thư mục dự án của bạn. Hãy cấp quyền **Full Disk Access** cho Yeet trong Cài đặt hệ thống → Quyền riêng tư & Bảo mật.")))
                .font(.system(size: 13.5))
                .lineSpacing(5)
                .foregroundStyle(DS.text2)
                .fixedSize(horizontal: false, vertical: true)

            DiskAccessPanel(ready: $ready)
            ProtectedFoldersPanel()

            Text(BuildFlavor.isAppStore
                 ? L("Yeet only deletes the items you select, runs no external commands and sends no data anywhere. Deleted items don't go to the Trash.",
                     "Yeet chỉ xoá những mục bạn đã chọn, không chạy lệnh ngoài và không gửi dữ liệu đi đâu. Mục xoá không vào Thùng rác.")
                 : L("Yeet doesn't use the App Sandbox and only deletes the items you select. Deleted items don't go to the Trash.",
                     "Yeet không dùng App Sandbox và chỉ xoá những mục bạn đã chọn. Mục xoá không vào Thùng rác."))
                .font(.system(size: 12))
                .foregroundStyle(DS.text3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Spacer()
                Button(L("Start Scanning", "Bắt đầu quét")) { onContinue() }
                    .buttonStyle(FilledButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ready)
            }
        }
        .padding(24)
        .frame(width: 500)
        .background(DS.surface)
    }
}
