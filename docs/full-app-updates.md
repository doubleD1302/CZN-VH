# Cập nhật toàn bộ ứng dụng

Mỗi đợt đồng bộ bản dịch mới phải dựng APK từ mã hiện hành. APK và bản dịch mang cùng phiên bản/code; APK chứa đúng gói đã ký. Giao diện, ảnh nền, icon, font và mã native được đưa tới người dùng cùng APK.

`tools/app_package.py` lưu `APP_BUILD_EVIDENCE.json`: snapshot/hash nguồn, package, phiên bản/code, chứng thư cộng đồng, hash APK và gói nhúng. Công cụ phát hành đối chiếu nguồn trước upload; nguồn hoặc APK đã đổi thì dừng. Khóa ký được giữ trên máy phát hành.

Tải nền qua Wi-Fi lấy cả APK mới và gói dịch. Android yêu cầu xác nhận cài APK; cài bản dịch vào game giữ quy trình quyền Shizuku và thao tác chủ động.

Đợt chỉ thay ứng dụng dùng `publish_android_release.py --app-only`: xác thực kênh hiện hành, giữ nguyên `patch_*`, cập nhật `app_*` và ký kênh mới. Đối chiếu lại bản nền trước phát hành để tránh đưa kênh về bản cũ.

`--prepare-only` chuẩn bị trên máy. `--publish` tạo bản nháp, upload tài sản, đối chiếu digest GitHub rồi công khai. Bằng chứng cuối phải khớp APK/bản nền. Không thay thế release hoặc tài sản đã tồn tại.

Ứng dụng 1.6.10 nhúng bản dịch công khai 1.6.9. Source gồm ảnh UI và font; APK nằm trên GitHub Releases. Lần push dùng `[skip ci]` theo yêu cầu dừng test; kết quả đã chạy trước đó được giữ.
