# CZN Việt Hóa — Android

Cài bản dịch tiếng Việt cho **Chaos Zero Nightmare** bằng Shizuku.

## [⬇ Tải APK mới nhất](https://github.com/doubleD1302/CZN-VH/releases/latest)

Liên kết trên dành cho lần cài đầu tiên. Nếu đã có app, bấm **Kiểm tra cập nhật → Cập nhật ứng dụng** ngay trong app để lên bản mới, không cần mở GitHub tải thủ công.

## Cài tiếng Việt trong 3 bước

1. **Shizuku:** [cài và khởi động Shizuku](https://shizuku.rikka.app/guide/setup/), rồi cấp quyền cho CZN Việt Hóa. Android 11 trở lên dùng gỡ lỗi không dây; Android 8–10 cần máy tính. Khởi động lại Shizuku sau khi khởi động lại điện thoại.
2. **Chuẩn bị game:** mở CZN, chọn ngôn ngữ văn bản **日本語 (tiếng Nhật)** và chờ tải đủ dữ liệu. Quay lại app, bấm **Kiểm tra lại dữ liệu game** đến khi bước 2 có tick xanh.
3. **Cài tiếng Việt:** bấm nút và chờ hộp thoại kết quả. App đóng game trước khi cài. Khi hiện **Cài Việt hóa thành công** và tick xác nhận, mở game, giữ ngôn ngữ văn bản **日本語**.

Bản **1.5.1** có giao diện tận thế đỏ–đen, nhân vật động kéo được và mục cập nhật APK ở đầu app. Gói bản dịch đi kèm vẫn là **1.4.2**, giữ bản sửa lỗi cache và xác minh kết quả cài.

## Cập nhật và thông báo

Mục **Cập nhật ứng dụng** ở đầu app tự kiểm tra khi mở. Khi có bản mới, bấm **Tải và cập nhật**, rồi xác nhận trên màn hình Android. Nếu máy yêu cầu, bật **Cho phép từ nguồn này** và quay lại app; app dùng lại APK đã tải. Cập nhật APK không cần Shizuku hoặc dữ liệu game đã sẵn sàng.

Bật cập nhật nền để nhận thông báo APK mới và tự tải bản dịch qua Wi-Fi. Bản dịch tải xong vẫn cần bấm cài. Nhân vật đồng hành có thể kéo đổi vị trí; nhấn giữ để ẩn và bật lại trong **Cài đặt**.

Thông báo khi mở app có nút **Tắt** và **Tắt trong 24 giờ**. Bấm biểu tượng loa để xem lại. Bản tin mới vẫn có thể hiện trong thời gian ẩn bản tin cũ.

## Nếu gặp lỗi

- Bấm **Sao chép lỗi** trong hộp thoại, hoặc **Hướng dẫn và trợ giúp → Sao chép báo cáo**, rồi gửi nội dung để được hỗ trợ.
- Muốn bỏ bản dịch: chọn **Khôi phục gốc**. Nếu app yêu cầu **Phục hồi giao dịch**, thực hiện bước đó trước khi mở game.
- Xiaomi: nếu Shizuku thiếu quyền, làm theo [hướng dẫn Shizuku](https://shizuku.rikka.app/guide/setup/). Game và app cần ở cùng hồ sơ Android chính.

Bản 1.5.1 đã qua analyzer, 22 kiểm thử Flutter và 29 kiểm thử native. Không chạy giả lập trong đợt này theo yêu cầu; thao tác và gameplay trên điện thoại thật vẫn chờ người chơi kiểm chứng.

<details>
<summary>Dành cho người phát hành từ PC 1.3.1</summary>

Trong bộ cài PC hiện có, chọn **Đồng bộ Android / GitHub** để dựng, kiểm tra và phát hành bản dịch kèm thông báo. Xem [hướng dẫn đầy đủ](https://github.com/doubleD1302/CZN-VH/releases/latest/download/HUONG_DAN_ANDROID.txt). Tệp EXE thay thế cần thư mục dự án PC có sẵn dữ liệu bản dịch.

Đợt chỉ đổi APK dùng `tools/publish_android_release.py --app-only`: xác thực kênh cũ, giữ mọi metadata bản dịch, ký kênh APK mới và chỉ phát hành khi có bằng chứng đúng hash. Người chơi nhận cập nhật từ app.

</details>

Giấy phép thư viện được giữ trong app. Bản dịch và tài nguyên game không được mặc nhiên cấp lại giấy phép của mã ứng dụng.
