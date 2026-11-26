import SwiftUI

/// Shown above an empty scan result when the sandbox kept Yeet out of the Home folder or some of
/// its folders. Lets the user grant the Home folder again, then rescans.
@MainActor
struct AccessBanner: View {
    let report: HomeAccess.Report
    let rescan: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DS.warning)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Yeet can’t read all of your Home folder", "Yeet chưa đọc được toàn bộ thư mục Home"))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS.text)
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS.text2)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if FolderAccess.request() { rescan() }
                } label: {
                    Label(L("Grant Home Folder Access…", "Cấp quyền thư mục Home…"), systemImage: "folder.badge.plus")
                }
                .buttonStyle(FilledButtonStyle())
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DS.warning.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DS.warning.opacity(0.3), lineWidth: 1))
    }

    private var detail: String {
        if !report.coversHome {
            let g = report.granted ?? L("no folder", "chưa có thư mục nào")
            return L("Access was granted to \(g), not to your Home folder (\(Paths.tilde(Paths.home))). Choose your Home folder so Yeet can search it.",
                     "Quyền đang được cấp cho \(g), không phải thư mục Home (\(Paths.tilde(Paths.home))). Hãy chọn thư mục Home để Yeet tìm trong đó.")
        }
        if !report.homeReadable {
            return L("macOS blocked Yeet from listing your Home folder. Choose it again to renew access.",
                     "macOS đang chặn Yeet đọc thư mục Home. Hãy chọn lại để cấp quyền mới.")
        }
        let names = report.blocked.joined(separator: ", ")
        return L("These folders couldn’t be read: \(names). Choose your Home folder again, and allow access if macOS asks.",
                 "Không đọc được các thư mục: \(names). Hãy chọn lại thư mục Home và cho phép nếu macOS hỏi.")
    }
}
