# Giao diện bốn trang công cụ

Triển khai bản thảo đã được người dùng duyệt ngày 14/10/2026 cho **Thiết lập, Cập nhật, Thông báo và Cài đặt**. Bốn trang dùng chung nền game toàn màn hình với lớp làm mờ nhẹ, màu navy/burgundy, chữ ivory, nét vàng champagne và thanh điều hướng bốn mục.

## Thành phần và tài nguyên

- `lib/ui/czn_tools_design.dart`: khung trang, thanh điều hướng, atlas ảnh, nút, panel, vòng icon và các nét trang trí.
- `lib/ui/czn_tools_workflow.dart`: ba bước thiết lập và trang cập nhật ứng dụng/bản dịch.
- `lib/ui/czn_tools_preferences.dart`: bản tin hiện hành, hai tùy chọn chibi/Wi-Fi, kênh cập nhật nâng cao và thao tác lưu/hủy.
- `assets/tools_*.png` và `assets/tools_atlas.json`: ảnh chữ, icon, panel, nút và vòng trang trí; atlas giữ nguyên byte ảnh được tạo, tọa độ chọn từng thành phần nằm trong JSON.
- Tinos (`CznDisplay`) và Noto Sans (`CznSans`): font chữ động thống nhất. Các tiêu đề và nhãn chính dùng ảnh chữ từ atlas, kèm nhãn ngữ nghĩa cho trình đọc màn hình.

Các line được bổ sung gồm nét dưới tiêu đề, đường nối 01–02–03, hai nét bên icon cập nhật, separator nội dung/thao tác, hai nét cạnh phiên bản và viền đôi có điểm kim cương. Các nét này được vẽ thêm bằng code để vẫn hiện rõ khi atlas chứa viền alpha mỏng.

## Nội dung và hành vi

Phiên bản, trạng thái quyền Shizuku, dữ liệu game và bản tin lấy từ dữ liệu thật. Chữ “BẢN THẢO” và trạng thái minh họa trong ảnh duyệt được thay bằng phiên bản/trạng thái hiện hành. Nội dung thông báo cuộn trong panel, nút tắt vẫn nằm cạnh vùng đọc; đây là một bản tin hiện hành, không phải hộp thư lưu lịch sử.

Cài đặt chỉ có hai tùy chọn đã tồn tại: hiện chibi và tải cập nhật qua Wi-Fi. Chibi tiếp tục tuân theo chế độ giảm chuyển động của Android. Kênh cập nhật nằm trong mục nâng cao. Các thao tác cài, phục hồi, sao chép báo cáo, cập nhật toàn bộ APK và xác nhận cài của Android dùng các callback hiện hành.

## Nguồn thiết kế

Bản thảo được duyệt nằm trong [ui-four-pages/approved](ui-four-pages/approved). Prompt tạo ảnh và metadata/hash tài nguyên nằm trong [ui-four-pages/assets.json](ui-four-pages/assets.json). Ảnh/logo game giữ quyền của chủ sở hữu; không suy rằng chúng có cùng giấy phép với mã nguồn. Giấy phép font đi kèm trong `assets/fonts/*_LICENSE.txt`.

## Trạng thái bàn giao

Đây là cập nhật **source**, chưa phát hành APK hoặc kênh OTA mới. Người dùng yêu cầu chỉ phát triển và push GitHub; không chạy lại test, analyzer, render hoặc build sau lượt sửa cuối. QA subagent được người dùng miễn cho riêng tác vụ này. Commit dùng `[skip ci]` để bỏ qua workflow test tự động.
