# Yeet

[English](README.md) · **Tiếng Việt**

Ứng dụng macOS native (SwiftUI, macOS 14+) quét và dọn cache của các công cụ lập trình: **Xcode, npm, Yarn, Gradle, Git và Claude Code**. Mỗi mục hiển thị dung lượng, đường dẫn thật trên ổ đĩa, mức ảnh hưởng khi xoá và lệnh dùng để dọn.

**Ngôn ngữ:** giao diện có tiếng Anh (mặc định) và tiếng Việt. Đổi trong **Cài đặt (⌘,) → Ngôn ngữ**.

## Build & chạy

Yêu cầu:

- macOS 14 Sonoma trở lên
- Xcode 15+ (hoặc Command Line Tools có Swift 5.9+)
- Tuỳ chọn: [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) nếu bạn sửa `project.yml`

```bash
git clone git@github.com:tranhuuthinhit/yeet.git
cd yeet

# Chạy nhanh khi phát triển (SwiftPM, không có bundle/icon)
swift run

# Đóng gói bản phân phối trực tiếp (không sandbox, có icon)
./scripts/build-app.sh             # → build/Yeet.app
./scripts/build-app.sh --install   # → copy vào /Applications

# Mở bằng Xcode (có icon, asset, 3 cấu hình Debug / Release / AppStore)
open Yeet.xcodeproj                # scheme "Yeet" → ⌘R
```

Build bằng dòng lệnh với Xcode:

```bash
xcodebuild -project Yeet.xcodeproj -scheme Yeet -configuration Release \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

`Yeet.xcodeproj` được sinh từ `project.yml`. Nếu thêm/xoá file nguồn, chạy `xcodegen generate` để cập nhật project (SwiftPM tự nhận file mới).

**Ký app:** `build-app.sh` tự dùng chứng chỉ *Apple Development* / *Developer ID* nếu có, không thì ký ad-hoc. Chọn chứng chỉ khác bằng `SIGN_IDENTITY="Apple Development: Tên (TEAMID)" ./scripts/build-app.sh`. Trong Xcode, chọn Team của bạn ở target **Yeet → Signing & Capabilities**.

**Đổi Bundle ID khi fork:** Bundle ID mặc định là **`vn.stevetran.yeet`** (trong `project.yml`, `scripts/build-app.sh`, `scripts/release-appstore.sh`). Nếu phát hành bản riêng, hãy đổi sang ID của bạn.

Icon nằm ở `Support/Assets.xcassets/AppIcon.appiconset` (Xcode) và `Support/AppIcon.icns` (SwiftPM build).

### Thêm / sửa chuỗi giao diện

Mọi chuỗi hiển thị dùng hàm `L(_ en:, _ vi:)` trong `Sources/Yeet/Core/L10n.swift`, hai bản dịch nằm cạnh nhau:

```swift
Text(L("Rescan", "Quét lại"))
```

Khi thêm chuỗi mới, luôn điền cả tiếng Anh và tiếng Việt.

## Đẩy lên Mac App Store bằng Xcode

`Yeet.xcodeproj` có sẵn scheme **Yeet**:

- **Run** (⌘R) dùng cấu hình *Debug*: không sandbox.
- **Archive** dùng cấu hình **AppStore**: bật App Sandbox, cờ `APPSTORE`, file `Support/YeetAppStore.entitlements`.

**1. Chọn Team (một lần).** Mở `Yeet.xcodeproj`, chọn target **Yeet** → **Signing & Capabilities**, chọn **Team**. Giữ *Automatically manage signing*. Bundle ID đã là `vn.stevetran.yeet`.

**2. Tăng số build** ở target Yeet → **General** → *Build*: mỗi lần upload phải lớn hơn lần trước. *Version* (1.0.0) chỉ đổi khi ra bản mới.

**3. Archive.** Ở thanh chọn đích, chọn **Any Mac (Apple Silicon, Intel)**, rồi **Product → Archive**. Xong, Organizer tự mở.

**4. Upload.** Trong Organizer, chọn archive vừa tạo:

1. Bấm **Distribute App**, chọn **App Store Connect**, rồi **Upload** (bản mới là *TestFlight & App Store*).
2. Ở bước ký, chọn một trong hai:
   - *Automatically manage signing*: Xcode tự dùng chứng chỉ Apple Distribution.
   - *Manually manage signing*: chọn chứng chỉ **Apple Distribution** và provisioning profile **Mac App Store** bạn đã tạo cho `vn.stevetran.yeet`.
3. Bấm **Upload**. Sau 5–30 phút build xuất hiện trong App Store Connect → TestFlight. Từ đó bạn gắn build vào phiên bản 1.0 rồi **Submit for Review**.

**Trước khi Submit:** điền listing (xem `AppStore/Listing.md`), tải ảnh chụp trong `AppStore/Screenshots/`, thêm Privacy Policy URL, chọn *Data Not Collected*, và dán gợi ý *App Review notes*.

> Không muốn dùng giao diện Xcode? `./scripts/release-appstore.sh` làm cùng các bước bằng `xcodebuild` (đọc `scripts/appstore.env`).

**Khác biệt của bản App Store (sandbox):**

- Người dùng chọn thư mục Home một lần, quyền được lưu bằng security-scoped bookmark. Bản này không dùng Full Disk Access.
- Không chạy lệnh CLI (`npm`, `yarn`, `git`, `xcrun`, `gradle`); mọi mục đều xoá file trực tiếp.
- Không có nhóm Git (chỉ `git` mới dọn an toàn được). Cũng không có simulator runtime, Conda và bộ cài macOS trong `/Applications`.

Lần đầu mở, Yeet hiển thị bước hướng dẫn cấp **Full Disk Access** (Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Full Disk Access → thêm `Yeet.app`). Không cấp vẫn quét được phần lớn cache trong thư mục người dùng. Nên cấp quyền cho bản `.app` trong `/Applications` để macOS ghi nhớ.

### Đã cấp Full Disk Access mà vẫn báo "Chưa có"?

1. **Chạy đúng Yeet.app.** Khi chạy bằng `swift run` hoặc Xcode, macOS áp quyền cho Terminal/Xcode chứ không cho Yeet. Hãy build bằng `./scripts/build-app.sh --install` và mở `/Applications/Yeet.app`.
2. **Mở lại app.** macOS thường chỉ áp quyền mới sau khi app khởi động lại. Nút **Mở lại Yeet** nằm trong màn hình quyền (và trong Cài đặt ⌘,).
3. **Sau khi build lại:** chữ ký ad-hoc đổi sau mỗi lần build, nên quyền cũ mất hiệu lực. Chạy `tccutil reset SystemPolicyAllFiles vn.stevetran.yeet`, rồi thêm lại Yeet.app vào danh sách Full Disk Access. Nếu máy có chứng chỉ *Apple Development* (đăng nhập Apple ID trong Xcode là có), script sẽ tự dùng chứng chỉ đó và quyền được giữ qua các lần build.

## Tính năng

- Sidebar "Tất cả" và từng công cụ, kèm dung lượng. Có thanh dung lượng ổ đĩa và tổng dung lượng **Đã giải phóng** (lưu lại giữa các lần mở).
- Cây cache với checkbox 3 trạng thái, mở/đóng nhóm, badge mức độ **An toàn / Tải lại**.
- Inspector: đường dẫn (chọn được, **Sao chép**, **Mở Finder**), số tệp, sửa lần cuối, ảnh hưởng khi xoá, lệnh dọn.
- **Chọn mục an toàn**, **Dọn dẹp…** với hộp xác nhận (cảnh báo khi app liên quan còn đang chạy), thanh tiến trình và toast.
- Quét song song từng công cụ (`TaskGroup`), kết quả hiện dần. Sau khi dọn, Yeet quét lại các công cụ bị ảnh hưởng.
- Cài đặt (⌘,): hiện đường dẫn, ẩn mục trống, xác nhận trước khi dọn, và danh sách thư mục chứa repo Git (mặc định `~/Projects`, `~/Developer`).
- **Ẩn công cụ không dùng.**
  - Chuột phải vào một công cụ trên sidebar → *Ẩn*, hoặc vào Cài đặt → **Công cụ được quét** để bật/tắt từng công cụ (có nút *Bật tất cả* và *Chỉ giữ công cụ có trên máy*).
  - Công cụ bị tắt không được quét, không hiện, không tính vào tổng.
  - *Tự ẩn công cụ không có trên máy* (mặc định bật) giấu các nhóm 0 KB sau khi quét.
  - Dòng "Đã ẩn N công cụ" cuối sidebar dẫn thẳng tới phần quản lý.
- **Dừng phân tích:** trong lúc chụp dung lượng, bấm *Dừng phân tích* ở thanh dưới, trên thanh menu, hoặc ⌘. / Esc. Lượt chụp dừng ngay, không lưu gì, số liệu cũ giữ nguyên.
- Phím tắt: ⌘R quét lại · ⇧⌘G phân tích dung lượng · ⌘. dừng phân tích · ⇧⌘S chọn mục an toàn · ⇧⌘D bỏ chọn · ⌘⌫ dọn dẹp.

## Tăng trưởng: dung lượng tăng do đâu?

Mục **Tăng trưởng** (sidebar → Tổng quan, hoặc ⇧⌘G để phân tích ngay) trả lời câu hỏi "hôm qua ổ đĩa còn trống 120 GB, sao hôm nay còn 105 GB?".

- **Chụp số liệu mỗi ngày.** Khi Yeet đang mở và lần chụp trước đã quá 20 giờ, Yeet ghi lại:
  - dung lượng đã dùng của ổ đĩa;
  - kích thước mọi thư mục ≥ 1 MB trong `~` (sâu 3 cấp, ví dụ `~/Library/Developer/Xcode`);
  - với bản trực tiếp, thêm `/Applications`, `/Library/Developer`, `/opt/homebrew` và số snapshot Time Machine cục bộ.

  Mỗi lần chụp đi hết cây thư mục một lượt, ở mức ưu tiên thấp, thường mất 1–5 phút. Số liệu lưu trong `~/Library/Application Support/Yeet/Snapshots` (60 ngày), không gửi đi đâu.
- **So sánh** hôm nay với lần chụp trước, ~7 ngày, ~30 ngày hoặc một ngày bất kỳ:
  - biểu đồ dung lượng 30 ngày;
  - tổng mức tăng của Ổ đĩa, Thư mục người dùng, Ứng dụng & công cụ, và **Hệ thống & khác** (phần tăng không nằm trong thư mục nào đo được: macOS, snapshot APFS/Time Machine, swap);
  - cây thư mục xếp theo mức tăng (chỉ hiện thay đổi ≥ 10 MB).
- **Inspector:** trước/sau, các thư mục con tăng nhiều nhất, Mở Finder, và nút **Dọn trong Yeet** nếu thư mục đó là cache Yeet dọn được. Nếu không phải cache (dự án, ảnh, máy ảo…), Yeet chỉ chỉ ra để bạn tự kiểm tra, **không xoá gì**.
- **Cài đặt → Theo dõi dung lượng:**
  - *Mở Yeet khi đăng nhập* (SMAppService), để ngày nào cũng có số liệu;
  - *Thông báo khi ổ đĩa tăng nhanh*, với ngưỡng 1–20 GB/ngày. Thông báo ghi thư mục tăng nhiều nhất.

### Chạy nền trên thanh menu

- Yeet có biểu tượng trên thanh menu (ổ đĩa). Bấm vào để xem dung lượng trống, mức tăng so với lần chụp trước, thư mục tăng nhiều nhất, và các nút **Phân tích ngay**, **Mở Yeet**, **Thoát Yeet**.
- **Đóng cửa sổ:** Yeet vẫn chạy nền, ẩn khỏi Dock, và vẫn chụp mỗi ngày (kiểm tra mỗi giờ, và 1 phút sau khi máy thức dậy). Muốn thoát hẳn thì dùng **Thoát Yeet** trên thanh menu hoặc ⌘Q.
- **Mở cùng lúc đăng nhập:** bật *Mở Yeet khi đăng nhập* thì Yeet khởi động thẳng lên thanh menu, không mở cửa sổ.
- **Tắt chế độ nền:** tắt *Hiện trên thanh menu & chạy nền* trong Cài đặt → Theo dõi dung lượng thì đóng cửa sổ là thoát Yeet như trước.

### Quyền truy cập: không bao giờ hỏi bất ngờ

macOS hỏi quyền lần đầu một app đọc Desktop, Documents, Downloads, dữ liệu của app khác (`~/Library/Containers`) hoặc ổ đĩa đám mây. Yeet **không tự đụng vào** các chỗ này khi chạy nền hay quét tự động. Chúng chỉ được đo khi:

- Yeet có **Full Disk Access** (không có hộp thoại nào), hoặc
- bạn bấm **Cho phép ngay** trong màn hình giới thiệu hoặc Cài đặt → Quyền truy cập ổ đĩa. Hộp thoại hiện đúng lúc bạn đang nhìn, trả lời một lần là macOS ghi nhớ. Yeet ghi nhận riêng từng thư mục đã được hỏi, nên thư mục bật thêm về sau không làm hộp thoại tự hiện.

Bạn cũng tắt được từng thư mục (Desktop / Documents / Downloads) nếu không muốn Yeet đo.

- **Containers (Docker, Mail, Notes…):** bật *Đo cả dữ liệu ứng dụng*, rồi bấm Cho phép ngay; macOS hỏi "truy cập dữ liệu của ứng dụng khác" một lần.
- **Ổ đĩa đám mây:** `~/Library/CloudStorage` (Dropbox, Google Drive, OneDrive) và iCloud Drive chỉ được đo khi có Full Disk Access.
- **Thư mục chưa đo:** màn hình Tăng trưởng liệt kê chúng kèm nút *Cấp quyền…*. Mức tăng ở đó được tính vào "Hệ thống, chưa đo & khác".
- **Khi quyền thay đổi giữa hai lần chụp**, Yeet loại hẳn các thư mục mà một trong hai lần chụp không đọc được, để không báo tăng/giảm ảo.
- **Bản App Store** (sandbox) không đọc được dữ liệu của app khác. Desktop, Documents và Downloads đã nằm trong quyền thư mục Home bạn cấp lúc đầu.

## Những gì được quét

Yeet chỉ liệt kê mục **An toàn** (tự tạo lại) hoặc **Tải lại** (tải/build lại ở lần dùng sau). Những thứ không tạo lại được thì **không bao giờ được liệt kê**:

- Xcode Archives, lịch sử phiên Claude Code và `sessiondata.img` của Cowork.
- Bản sao lưu iPhone, tệp đính kèm iMessage, snapshot Time Machine.
- Emulator Android, ổ đĩa Docker, virtualenv/Conda env.

Đường dẫn tính từ `~` trừ khi ghi khác.

| Nhóm | Đường dẫn | Cách dọn |
|---|---|---|
| **Xcode** | `Library/Developer/Xcode/DerivedData/*`, `*DeviceSupport/*`, `CoreSimulator/Caches`, `DocumentationCache`, `iOS Device Logs`, `Library/Caches/com.apple.dt.Xcode`, `Library/Developer/XCPGDevices` | `rm -rf`, `xcrun simctl delete unavailable` |
| | Simulator runtime (`xcrun simctl runtime list`), chỉ bản trực tiếp | `xcrun simctl runtime delete` |
| **CocoaPods & SPM** | `Library/Caches/CocoaPods`, `Library/Caches/org.swift.swiftpm`, `Library/Caches/org.carthage.CarthageKit` | `pod cache clean --all`, `rm -rf` |
| **npm** | `.npm/_cacache`, `_npx`, `_logs` | `npm cache clean --force` |
| **Yarn** | `Library/Caches/Yarn/v*`, `.yarn/berry/cache` | `yarn cache clean` |
| **pnpm & Bun** | `Library/pnpm/store`, `Library/Caches/pnpm`, `.bun/install/cache` | `rm -rf`, `bun pm cache rm` |
| **node_modules** | `node_modules` cạnh `package.json` trong thư mục dự án (không mở hơn 30 ngày thì là An toàn) | `rm -rf` |
| **Python** | `Library/Caches/pip`, `Library/Caches/pypoetry/{cache,artifacts}`, `.cache/uv`, `*conda*/pkgs` (chỉ bản trực tiếp) | `uv cache clean`, `conda clean --all` |
| **Go** | `Library/Caches/go-build`, `go/pkg/mod` | `go clean -cache` / `-modcache` |
| **Rust** | `.cargo/registry/{cache,src}`, `.cargo/git/checkouts`, `target/` của dự án (có `CACHEDIR.TAG`) | `rm -rf`, `cargo clean` |
| **Gradle** | `.gradle/caches/*`, `wrapper/dists/*`, `daemon` | `rm -rf`, `gradle --stop` |
| **Maven** | `.m2/repository`, `.m2/wrapper/dists` | `rm -rf` |
| **Flutter & Dart** | `.pub-cache/hosted`, `.pub-cache/git` | `rm -rf` |
| **Homebrew** | `Library/Caches/Homebrew`, `Library/Logs/Homebrew` | `brew cleanup --prune=all -s` |
| **Git** (chỉ bản trực tiếp) | `.git/lfs/objects`, loose objects | `git lfs prune`, `git gc --prune=now` |
| **Claude Code** | `Library/Caches/claude-cli-nodejs`, `.claude/shell-snapshots`, `.claude/todos`; máy ảo Cowork `vm_bundles/*.bundle` (`rootfs.img`, `.zst`/`.partial` thừa, kernel/initrd); `Cache`, `Code Cache` của app | `rm -rf`, khi Claude đã thoát |
| **IDE & Editor** | VS Code / Cursor / Windsurf: `Cache`, `CachedData`, `CachedExtensionVSIXs`, `Code Cache`, `GPUCache`, `logs`; JetBrains: cache của **phiên bản cũ**, `Library/Logs/JetBrains` | `rm -rf`, khi IDE đã thoát |
| **Cache ứng dụng** | Slack, Discord, Teams, Figma, Notion (`Cache`, `Code Cache`, `GPUCache`); `Library/Caches/Google/Chrome`; các thư mục `Library/Caches/<bundle id>` khác ≥ 10 MB (không gồm `com.apple.*`) | `rm -rf`, khi app đã thoát |
| **macOS** | `Library/Logs/DiagnosticReports` và log khác ≥ 1 MB, `.Trash`, `.dmg/.pkg/.xip/.ipsw` trong `Downloads`, `/Applications/Install macOS *.app` (chỉ bản trực tiếp), `Library/iTunes/*Software Updates`, tệp Mail đã mở | `rm -rf` |

Thư mục dự án (dùng cho Git, node_modules và `target/` của Rust) chỉnh trong Cài đặt → **Thư mục dự án**. Mặc định là `~/Projects` và `~/Developer`.

**Các lớp bảo vệ khi xoá:**

- Chỉ xoá bên trong thư mục người dùng; ngoại lệ duy nhất là `/Applications/Install macOS *.app`.
- Từ chối xoá khi thư mục là symlink trỏ ra ngoài Home.
- Không quét vào bên trong các file `.app`.
- Yêu cầu thoát app trước khi xoá cache của app đó.

Dung lượng là dung lượng thực chiếm trên ổ (`totalFileAllocatedSize`), đơn vị thập phân giống Finder.

**An toàn khi xoá:** Yeet chỉ xoá đường dẫn nằm trong thư mục người dùng (và không bao giờ xoá chính thư mục đó). Lệnh riêng của từng công cụ chạy qua `zsh -lc` để có PATH của Homebrew/nvm. Nếu lệnh không chạy được, Yeet xoá trực tiếp thư mục cache. Riêng Git chỉ chạy lệnh `git`, không bao giờ xoá `.git/objects`.

## Cấu trúc

```
Sources/Yeet/
  YeetApp.swift          App, Window, menu Cache, Settings
  Core/
    Models.swift         Risk, ToolKind, CacheNode, CleanAction…
    Scanner.swift        Tìm và đo cache cho từng công cụ
    ScannerExtra.swift   Các nhóm cache bổ sung (SPM, pnpm, Python, Go, Rust, IDE, app, macOS…)
    Growth.swift         Snapshot dung lượng hằng ngày, so sánh, thông báo, mở khi đăng nhập
    ProtectedFolders.swift  Desktop/Documents/Downloads/Containers: chỉ đọc khi đã được phép
    Cleaner.swift        Xoá / chạy lệnh, kiểm tra Full Disk Access
    AppModel.swift       Trạng thái (@Observable): chọn, mở rộng, quét, dọn
    Format.swift         Định dạng dung lượng/ngày theo ngôn ngữ, đường dẫn
    L10n.swift           Ngôn ngữ giao diện (EN/VI) và hàm L(en, vi)
    Theme.swift          Design tokens, button styles, card
  Views/                 Sidebar, Header, CacheTree, Inspector, Footer,
                         ConfirmOverlay, Onboarding, Settings, Components
Support/
  Info.plist             Bundle metadata (vn.stevetran.yeet)
  Assets.xcassets        App icon (Xcode) · AppIcon.icns (SwiftPM)
  Yeet.entitlements      Bản trực tiếp (không sandbox)
  YeetAppStore.entitlements  Bản App Store (sandbox + bookmark)
  PrivacyInfo.xcprivacy  Privacy manifest
Yeet.xcodeproj           Project Xcode (scheme Yeet: Run = Debug, Archive = AppStore)
AppStore/                Listing EN/VI, screenshots, icon 1024
scripts/
  build-app.sh           Đóng gói Yeet.app (phân phối trực tiếp)
  release-appstore.sh    Archive + upload Mac App Store
  appstore.env.example   Cấu hình team / API key
```

## Ghi chú

- **Không thấy icon trên Dock khi Run bằng Xcode?** Hãy mở `Yeet.xcodeproj`, không phải `Package.swift` (bản SwiftPM không có bundle và asset). Nếu vẫn còn icon mặc định, chạy **Product → Clean Build Folder** (⇧⌘K) rồi `killall Dock` để macOS nạp lại cache icon.

- Giao diện dùng chế độ sáng theo thiết kế (dark mode chưa làm).
- Bản trực tiếp (Debug/Release, `build-app.sh`) không dùng App Sandbox. Bản Mac App Store là cấu hình `AppStore`.

## Giấy phép

[MIT](LICENSE) © 2026 Steve Tran
