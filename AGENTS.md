# FPTU SE Brain — Hướng dẫn cho agent

## 1. Mục tiêu dự án

Đây là Lab 1 của Nhóm 1: ứng dụng desktop Flutter cho Windows tên **FPTU SE Brain**.

Ứng dụng giúp sinh viên FPTU đọc và học từ các ghi chú Obsidian. Ứng dụng đọc một thư mục ghi chú (Vault), không cần Firebase, đăng nhập hoặc đồng bộ cloud trong Lab 1.

Nguyên tắc quan trọng: ứng dụng phải giúp người dùng học tốt hơn Windows File Explorer, không chỉ liệt kê file. Giá trị chính là trình bày Markdown đẹp, tìm kiếm và trợ lý AI học tập.

## 2. Phạm vi demo bắt buộc

Luồng chính phải hoạt động trên Windows:

1. Người dùng nhấn **Chọn thư mục ghi chú**.
2. Ứng dụng đọc các file `.md` trong thư mục đã chọn và thư mục con.
3. Ứng dụng hiển thị cây thư mục hoặc danh sách ghi chú.
4. Người dùng chọn ghi chú và xem nội dung Markdown dễ đọc.
5. Người dùng có thể tìm ghi chú.
6. AI có thể tóm tắt ghi chú đang mở và tạo câu hỏi ôn tập.

Không đưa các chức năng sau vào trước khi luồng chính ổn định: Firebase, đăng nhập, đồng bộ cloud, chỉnh sửa ghi chú phức tạp, Knowledge Graph hoặc AI hỏi toàn bộ Vault.

## 3. Giao diện và ngôn ngữ

- Ngôn ngữ hiển thị chính: **tiếng Việt**.
- Phong cách: desktop hiện đại, nền xanh đen, panel xanh đậm, màu nhấn cam FPT; chữ dễ đọc và tương phản tốt.
- Bố cục ưu tiên ba cột:
  - trái: Vault, môn học và danh sách ghi chú;
  - giữa: nội dung Markdown của ghi chú;
  - phải: thông tin ghi chú và Trợ lý AI.
- Giao diện phải chịu được khi thay đổi kích thước cửa sổ; nội dung dài cần cuộn, không tràn hoặc che nút.
- Luôn có trạng thái rõ ràng: chưa chọn Vault, đang tải, không có ghi chú, lỗi đọc file, AI đang xử lý và lỗi kết nối AI.

## 4. Phân công theo vai trò

- **Người 1 — UI và tích hợp:** theme, thanh trên, bố cục ba cột, trạng thái giao diện, ghép các phần và xử lý lỗi giao diện.
- **Người 2 — Vault và file system:** chọn thư mục, quét file `.md`, tạo cây thư mục, đọc UTF-8 và xử lý file lỗi.
- **Người 3 — Markdown Viewer:** render Markdown, code block, metadata/YAML, tags và ghi chú liên quan.
- **Người 4 — AI và tìm kiếm:** tìm kiếm, kết nối AI, tóm tắt note đang mở và tạo câu hỏi ôn tập.

Không sửa sâu phần việc của thành viên khác khi chưa kiểm tra interface hoặc trao đổi với nhóm. Nếu cần thay đổi dữ liệu dùng chung, cập nhật rõ model và thông báo trong commit/PR.

## 5. Quy tắc kỹ thuật

- Nền tảng chính là Flutter Windows. Ưu tiên chạy với `flutter run -d windows`.
- Bắt đầu bằng giải pháp đơn giản, dễ giải thích. Không thêm kiến trúc hoặc package phức tạp khi chưa cần.
- Dùng model dữ liệu chung cho ghi chú (ví dụ: tên, đường dẫn, nội dung, ngày sửa, tags). Không tạo nhiều model trùng chức năng.
- Ưu tiên widget nhỏ, đặt tên dễ hiểu và tách UI theo khu vực màn hình.
- Không hard-code nội dung Vault thật vào giao diện; dữ liệu giả chỉ dùng tạm trong lúc chờ tích hợp.
- Không thêm package mới nếu Flutter/Dart có sẵn cách xử lý phù hợp. Nếu cần package AI, quản lý file hoặc Markdown, nêu rõ lý do và cập nhật `pubspec.yaml` cùng lockfile.

## 6. Quy tắc AI và bảo mật

- AI chỉ được dùng với **ghi chú đang mở** trong Lab 1.
- Chức năng AI bắt buộc: tóm tắt và tạo câu hỏi ôn tập bằng tiếng Việt.
- Khi mất mạng hoặc AI lỗi, ứng dụng vẫn phải đọc được ghi chú; chỉ panel AI hiển thị thông báo lỗi và nút thử lại.
- Không đưa API key, token, mật khẩu hoặc nội dung riêng tư vào source code, commit, log, ảnh chụp màn hình hay GitHub.
- Nếu dùng file cấu hình local như `.env`, cập nhật `.gitignore` trước khi tạo key thật. Có thể commit `.env.example` chỉ chứa key mẫu.
- Không tự ý chọn hoặc kích hoạt dịch vụ AI tốn phí nếu nhóm chưa cung cấp cấu hình hợp lệ.

## 7. Quy tắc Git

- `main` chỉ chứa phiên bản ổn định để demo.
- `develop` là nhánh tích hợp chung.
- Làm việc trên nhánh riêng theo dạng `feature/<ten-cong-viec>`.
- Agent được phép commit và push lên **nhánh feature hiện tại** khi thay đổi đã được kiểm tra.
- Agent không được tự merge, force-push, reset hoặc push trực tiếp vào `develop` hay `main` nếu chưa có yêu cầu rõ ràng.
- Không commit file sinh tự động hoặc file lớn: `build/`, `.dart_tool/`, `.idea/`, `windows/flutter/ephemeral/`, file `*.iml`, `.env`.
- Trước khi commit, kiểm tra `git status` để chắc chắn chỉ có source code, cấu hình cần thiết và tài liệu liên quan.
- Commit message ngắn, bằng tiếng Anh, theo dạng: `feat: ...`, `fix: ...`, `chore: ...`, `docs: ...`.

## 8. Kiểm tra trước khi bàn giao

Sau khi thay đổi code, chạy các bước phù hợp:

```powershell
flutter analyze
flutter test
flutter run -d windows
```

- Nếu thay đổi chỉ là tài liệu, không cần chạy ứng dụng.
- Nếu thay đổi UI hoặc luồng chính, kiểm tra bằng cửa sổ Windows thật.
- Nếu một lệnh không chạy được, báo rõ lệnh nào lỗi, nguyên nhân nhìn thấy và không che giấu lỗi.
- Khi hoàn thành, nêu ngắn gọn: phần đã thay đổi, cách kiểm tra và rủi ro còn lại (nếu có).

## 9. Thứ tự ưu tiên khi thời gian ít

1. Chọn Vault và đọc file `.md`.
2. File Tree và Markdown Viewer.
3. Giao diện desktop ổn định, đẹp và dễ demo.
4. Tìm kiếm theo tên ghi chú.
5. AI tóm tắt note đang mở.
6. AI tạo câu hỏi ôn tập.

Không hy sinh luồng đọc file thật để chạy theo tính năng nâng cao.
