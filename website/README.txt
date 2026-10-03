Yeet — website (EN mặc định, VI qua nút chuyển hoặc ?lang=vi)

Upload toàn bộ thư mục này lên web root của VPS (vd. /var/www/yeet/):

  index.html        trang chính
  privacy.html      Privacy Policy (URL này dán vào App Store Connect → App Privacy → Privacy Policy URL)
  support.html      trang Support tĩnh, không cần JS (URL này dán vào App Store Connect → Support URL)
  support.js        runtime hiển thị (bắt buộc, đặt cạnh index.html)
  images/           ảnh chụp màn hình + icon
  downloads/        tạo thư mục này và đặt Yeet-1.0.0.dmg vào

Trước khi đăng:
  1. Đặt file cài đặt tại downloads/Yeet-1.0.0.dmg (hoặc sửa downloadUrl trong index.html).
  2. Chạy: shasum -a 256 downloads/Yeet-1.0.0.dmg
     Dán mã vào chỗ "Paste the SHA-256..." trong index.html.
  3. Kiểm tra lại các mô tả bảo mật (không gửi dữ liệu, yêu cầu macOS) cho khớp với app thật.
  4. Sửa email support@example.com ở footer index.html và trong privacy.html.
  5. App Store Connect → App Privacy: chọn "Data Not Collected" (khớp với privacy.html).

Link trực tiếp: /?lang=en hoặc /?lang=vi. Lựa chọn ngôn ngữ được nhớ trong trình duyệt.
Trang cần Internet để tải React và Phosphor Icons từ unpkg.com.
File "Yeet Website.dc.html" và "Privacy.dc.html" là bản gốc để chỉnh sửa, không cần upload.
