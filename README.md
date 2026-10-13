# CZN Việt Hóa — Android

Cài bản dịch tiếng Việt cho **Chaos Zero Nightmare** bằng Shizuku.

## [⬇ Tải APK mới nhất](https://github.com/doubleD1302/CZN-VH/releases/latest)

Bản **1.6.10** có nền toàn màn hình, logo game kèm cờ Việt Nam và chữ **VI**, nút/icon riêng và màn hình công cụ làm mờ nền. Gói bản dịch đi kèm là **1.6.9**.

## Cài tiếng Việt trong 3 bước

1. [Cài và khởi động Shizuku](https://shizuku.rikka.app/guide/setup/), rồi cấp quyền cho app. Android 11 trở lên dùng gỡ lỗi không dây; Android 8–10 cần máy tính. Khởi động lại Shizuku sau khi khởi động lại điện thoại.
2. Mở CZN, chọn ngôn ngữ văn bản **日本語 (tiếng Nhật)** và chờ tải đủ dữ liệu. Trong **Thiết lập**, bấm **Kiểm tra lại dữ liệu game** đến khi dữ liệu sẵn sàng.
3. Bấm **Cài tiếng Việt** và chờ kết quả. App đóng game trước khi cài. Khi báo thành công, mở game và giữ ngôn ngữ văn bản **日本語**.

## Cập nhật và trợ giúp

Bấm **Cập nhật** trên màn hình chính để mở tab riêng. Khi có APK mới, tải và xác nhận cài trên màn hình Android. Nếu được yêu cầu, bật **Cho phép từ nguồn này** và quay lại app. Cập nhật APK không cần Shizuku.

Bật cập nhật nền trong cài đặt để app kiểm tra và tải APK cùng bản dịch qua Wi-Fi. Các đợt sau đi kèm APK mới để cập nhật giao diện, icon, tài nguyên và chức năng. Android vẫn yêu cầu xác nhận cài APK; bản dịch đã tải cần bấm cài tiếng Việt.

**Thiết lập** và **Cập nhật** là hai tab riêng trên nền làm mờ. Bấm nhân vật động hoặc **Trợ giúp** để mở hộp thoại: chạm **copy mã lỗi** để sao chép báo cáo; chạm **gửi cho Dev** để mở [Facebook nhà phát triển](https://www.facebook.com/datnguyen.kei/).

Trong **Thiết lập**, chọn **Khôi phục gốc** để bỏ bản dịch. Nếu app yêu cầu **Phục hồi giao dịch**, hoàn tất trước khi mở game. Game và app cần nằm cùng hồ sơ Android chính.

Bản này đã có analyzer sạch, 33 kiểm thử Flutter và ảnh chạy trên giả lập trước khi chốt. Điện thoại thật và gameplay vẫn chờ người chơi kiểm chứng. Lần push này bỏ qua CI theo yêu cầu dừng test.

<details>
<summary>Dành cho người phát hành từ PC</summary>

Chọn **Đồng bộ Android / GitHub** trong bộ cài PC để dựng và phát hành. Công cụ dựng APK mới cùng phiên bản với bản dịch, lưu snapshot nguồn và đối chiếu chữ ký/hash trước phát hành. Khóa ký chỉ giữ trên máy phát hành.

Thông báo nêu nội dung theo bản đồ, chế độ, nhân vật, thẻ/kỹ năng khi có liên kết nguồn xác định. **Xem chi tiết / tìm nội dung** cho phép lọc và xem trước/sau với gói thực tế. Xem [lưu dấu vết](docs/translation-history.md) và [cập nhật toàn bộ APK](docs/full-app-updates.md).

Đợt chỉ đổi ứng dụng dùng `tools/publish_android_release.py --app-only`: giữ nguyên metadata bản dịch đã ký, yêu cầu APK mới và bằng chứng đúng hash. `--prepare-only` chỉ chuẩn bị cục bộ.

</details>

Giấy phép thư viện/font được giữ trong `assets/THIRD_PARTY_LICENSES.txt` và `assets/fonts/*_OFL.txt`. Tài nguyên và logo game không được mặc nhiên cấp lại giấy phép của mã ứng dụng.
