# Bàn giao Người 2 — Vault và file system

## Phạm vi đã viết code
- Hộp chọn thư mục Windows thật; Cancel giữ nguyên Vault hiện tại.
- Quét đệ quy `.md`/`.MD`; bỏ qua `.obsidian` ở mọi cấp.
- Cây thư mục đóng/mở, thư mục trước file, sắp xếp tên, đánh dấu file đang chọn.
- Chỉ đọc nội dung khi chọn file; UTF-8 nghiêm ngặt, hỗ trợ BOM và tiếng Việt.
- File rỗng hiển thị trạng thái riêng; trả đường dẫn, kích thước bytes và ngày sửa.
- Lỗi quyền truy cập/quét thư mục con thành cảnh báo; lỗi Vault gốc thành thông báo.
- File bị xóa/di chuyển hoặc UTF-8 hỏng không làm dừng ứng dụng.
- Quét lại Vault bằng nút refresh; bấm lại file để đọc phiên bản mới nhất.
- Bỏ qua symbolic links/junctions để tránh vòng lặp khi quét.
- Bỏ kết quả đọc cũ khi đổi file hoặc Vault trong lúc đang tải.

Không thêm dependency nên pubspec.yaml và pubspec.lock giữ nguyên.
Folder picker dùng Windows IFileOpenDialog qua MethodChannel; CMake đã thêm source và thư viện hệ thống. Phải copy cả thư mục windows khi dùng bản sửa, không chỉ lib.

## Chạy trên Windows
Mở terminal tại thư mục chứa pubspec.yaml. Cần Flutter có Dart tương thích ràng buộc `^3.12.2` của project gốc và Visual Studio với Desktop development with C++.

```powershell
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run -d windows
```

Sau khi sửa native C++, phải dừng app và chạy lại hoàn toàn; hot reload không nạp phần native mới. Nếu đang chép đè vào project đã build, chạy `flutter clean` rồi `flutter pub get` trước khi chạy.

## Điểm tích hợp cho nhóm
- `lib/vault/note_file.dart`: model chung `NoteFile`, `VaultNode`, `VaultSnapshot`, `VaultException`.
- `lib/vault/vault_repository.dart`: interface `scan(directoryPath)` và `readNote(note)`.
- `lib/vault/local_vault_repository.dart`: triển khai đọc file local.
- `lib/vault/vault_controller.dart`: trạng thái scan/read và chống kết quả async cũ.
- `lib/vault/vault_picker.dart`: mở hộp chọn thư mục Windows.
- `lib/vault/vault_tree.dart`: cây thư mục tích hợp tối thiểu.
- `lib/main.dart`: thay model/demo bằng dữ liệu Vault thật, nối sự kiện, trạng thái và thông tin file.
- `windows/runner/vault_picker.cpp`, `.h`: picker native; đăng ký trong flutter_window.cpp và thêm vào CMakeLists.txt.

`NoteFile.content == null` nghĩa là mới quét thông tin file, chưa đọc; `content == ''` là file rỗng đã đọc. `modified` là DateTime, `sizeBytes` tính bằng byte. `relativePath` dùng `/`, `path` là đường dẫn local tuyệt đối. `tags` dành cho người 3 bổ sung; `course` hiện suy ra từ thư mục cấp đầu, chưa parse YAML.

Người 3 nhận `NoteFile` đã đọc để render Markdown/YAML. Nội dung giữa màn hình hiện là văn bản thô có thể chọn/copy nhằm kiểm tra dữ liệu thật. AI vẫn là placeholder có sẵn. Bộ lọc theo tên chỉ nối với cây thư mục hiện tại; chưa thực hiện backlinks, tìm toàn văn hay các chức năng khác của Người 4.

## Kiểm thử đã bổ sung (chưa chạy)
- Repository: quét lồng nhau, `.obsidian`, `.MD`, Unicode, BOM, file rỗng, UTF-8 sai, file bị xóa, root mất, đọc lại nội dung mới và bỏ qua link (test link trên Linux/macOS).
- Controller: kết quả đọc chậm không ghi đè lựa chọn mới; đổi Vault hủy tác dụng kết quả đọc cũ.
- Widget: workspace rỗng, Cancel; mock hộp chọn nhưng quét/đọc file thật từ thư mục tạm.

Môi trường sửa code không có Flutter/Dart và không phải Windows. Đã thử `flutter analyze`, `flutter test`, `flutter run -d windows`: cả ba báo `flutter: command not found`. Chưa xác nhận compile Dart/C++ hoặc giao diện Windows; cần chạy các lệnh trên trước khi merge/demo.

## Checklist nghiệm thu trên Windows
1. Tạo một thư mục thử, trong đó có `goc.md`, `Môn học/tiếng Việt.MD`, file rỗng và `.obsidian/bo-qua.md`.
2. Chọn Vault; xác nhận thư mục đứng trước file, `.obsidian` không xuất hiện.
3. Mở thư mục con, chọn file tiếng Việt; so nội dung, bytes và ngày sửa với file thật.
4. Mở file rỗng; app không lỗi. Cancel picker; Vault cũ vẫn còn.
5. Xóa file ngoài Explorer sau khi quét rồi chọn lại; có thông báo lỗi và vẫn mở được file khác.
6. Mở file không phải UTF-8; hiện thông báo rõ ràng. Quét lại sau khi sửa/xóa/thêm file.
7. Đổi Vault, chọn file liên tục; nội dung không nhảy về lựa chọn cũ.
8. Thử thư mục không có quyền truy cập bằng tài khoản Windows phù hợp; kiểm tra cảnh báo và các nhánh còn đọc được.
9. Chạy ở 1100 x 700; kiểm tra đường dẫn/tên dài và cuộn nội dung.

Nhánh đề xuất: `feature/vault-reader`. Gói ZIP không chứa lịch sử Git; chưa commit/push/merge.

Tham khảo API picker: https://learn.microsoft.com/en-us/windows/win32/shell/common-file-dialog
