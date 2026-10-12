# CZN Việt Hóa — Android

Ứng dụng cộng đồng để cài bản dịch CZN vào slot tiếng Nhật, dùng Shizuku.

## Dành cho người chơi

1. Cài APK từ [GitHub Releases](https://github.com/doubleD1302/CZN-VH/releases).
2. Cài và khởi động [Shizuku](https://shizuku.rikka.app/guide/setup/), rồi cấp quyền cho CZN Việt Hóa. Android 11+ dùng gỡ lỗi không dây; Android 8–10 cần máy tính để khởi động Shizuku.
3. Mở CZN, tải đầy đủ dữ liệu và ngôn ngữ văn bản 日本語. Quay lại app, bấm **Cài tiếng Việt**. App đóng game, kiểm tra nguồn, sao lưu, cài và đọc lại hash.
4. Trong game, đặt ngôn ngữ văn bản là **日本語**; lồng tiếng tùy chọn.

Bản dịch đi kèm có thể cài khi offline. Bản mới tự được kiểm tra/tải trên mạng không tính phí mỗi 12 giờ; app kiểm tra thêm khi mở. Bật thông báo để biết khi tải xong. Bước ghi tài nguyên cần bấm cài; cập nhật APK cần xác nhận của Android. Shizuku cần khởi động lại sau khi điện thoại khởi động.

App tự tìm thư mục dữ liệu và chỉ hỗ trợ nguồn JP có hash khớp gói đã ký. Nguồn game mới hoặc thiết bị không cho Shizuku truy cập sẽ được báo rõ và không bị ghi đè. Không có tuyên bố đã kiểm chứng mọi ROM hoặc đảm bảo an toàn tài khoản. Cài/khôi phục trên fixture emulator không phải bằng chứng gameplay.

Bản cộng đồng dùng ID `vn.czn.viethoa.community` và khóa ký mới, có thể cài cạnh APK beta cũ; không dùng file backup `.bak` của beta. Nếu đã dùng beta để vá game, dùng chức năng kiểm tra/tải lại dữ liệu của game trước khi chuyển sang bản cộng đồng để có nguồn sạch.

## Thiết kế

- Gói `.cznpatch` chỉ chứa hai payload JP nén và descriptor RSA/SHA-256. Không copy toàn manifest/chunk Windows sang Android.
- Parser SSRA v4 lấy offset, chunk và checksum từ manifest trên thiết bị. Kiểm tra slot nguồn theo SHA-256, kích thước và XXH64; giữ nguyên mọi byte ngoài slot JP và trường manifest ngoài checksum/kích thước liên quan.
- Staging, backup đúng baseline, hash đọc lại, rename nguyên tử và journal phục hồi. Restore đòi hỏi mọi backup/file live hợp lệ. Game cập nhật hoàn chỉnh có thể tạo baseline mới; dữ liệu cập nhật dở hoặc còn chunk vá cũ bị từ chối.
- I/O qua Shizuku UserService trên worker thread; chuyển file bằng ParcelFileDescriptor, không gửi chunk 192 MiB qua MethodChannel.
- Kênh `releases/latest/download/channel.json` được ký bằng khóa cập nhật riêng; APK ký bằng khóa community cố định.

## Phát triển và kiểm thử

Yêu cầu Flutter 3.44+, Android SDK 36, JDK 17+ và Kotlin/AGP theo Gradle wrapper.

```powershell
flutter pub get
flutter analyze
flutter test
cd android
./gradlew.bat :app:testDebugUnitTest
```

Khóa release nằm trong `.signing/`, không đưa vào Git hoặc gói công khai. `release.properties` có `storeFile`, `storePassword`, `keyAlias`, `keyPassword`. `assembleRelease` từ chối khi thiếu cấu hình ký.

Để đóng gói bản dịch mới từ project Việt hóa đã kiểm chứng:

```powershell
python CZN_VietHoa_Project/tools/package_android_patch.py --version 1.4.1 --code 10401
```

Chỉ dùng `--embed` khi chủ ý đổi bản đi kèm trong APK. Giữ tăng `version_code`, `min_patcher` phù hợp và cùng khóa ký cập nhật. Không ghi đè release đã phát hành. Sau khi có APK và bundle mới, tạo `channel.json` có chữ ký bằng công cụ phát hành, tải đủ APK/bundle/channel/SHA256SUMS lên cùng release GitHub.

## Giấy phép và nguồn

Các phụ thuộc vẫn giữ giấy phép của tác giả. API Shizuku: Apache-2.0; lz4-java: Apache-2.0; AndroidX: Apache-2.0; Flutter/Dart và plugin theo giấy phép tương ứng. Định dạng SSRA tham khảo reader MIT của [cznrip](https://github.com/cznrip/Chaos-Zero-Nightmare-ASSet-Ripper). Bản dịch và tài nguyên game không được mặc nhiên cấp lại giấy phép của mã app.


## Bản 1.4.1 và đồng bộ từ PC 1.3.1

Bước 2 có nút kiểm tra lại và lỗi cụ thể; chỉ xác nhận khi đọc được manifest, JP và story. Quét lại khi trở về từ game dù kiểm tra mạng trước đó đang chạy. Tìm vùng dữ liệu/media/obb của đúng package trên bộ nhớ ngoài; không nới whitelist SSRA hay đọc/ghi vùng riêng /data/user. Xiaomi cần theo hướng dẫn Shizuku, cùng hồ sơ Android chính. Game từ TapTap được nhận theo mã package, không theo tên cửa hàng.

Thông báo cộng đồng nằm trong trường `notice` của kênh đã ký: `{enabled, id, title, body}`. Khi mở app có Tắt và Tắt trong 24 giờ; ẩn theo ID nên bản tin mới vẫn hiện. Bản tin ký được lưu cho offline; bản đi kèm có hướng dẫn khởi đầu. Biểu tượng loa mở lại thông báo. Các nút Kiểm tra cập nhật, cập nhật bản dịch và APK hiện rõ trong màn hình.

EXE CZN_VietHoa_v1_3_1.exe của đợt này dùng để thay trong **thư mục PC cũ có catalog**, không phải gói PC độc lập có sẵn bản dịch. Chọn Đồng bộ Android / GitHub → Kiểm tra cập nhật → phiên bản cao hơn → tiêu đề/nội dung thông báo → khóa update-private.pk8 → Dựng & kiểm tra gói → xem trước → Phát hành lên GitHub. Có thể để trống nội dung nếu không phát thông báo. Cần PowerShell 7 và Git Credential Manager hoặc token Contents: Read and write cho kho này. Token chỉ tồn tại trong phiên; khóa riêng không vào APK/EXE/GitHub.

Công cụ PC dựng từ catalog được chấp nhận và nguồn JP gốc bằng Installer.build; không cần cài vào tài nguyên PC trước. Kiểm tra đọc lại native, token, cấu trúc story và byte ngoài hai slot trước ký. Kênh data update giữ thông tin APK đã được ký của release trước. Tải tài sản vào draft, chỉ công khai khi đủ; lỗi mạng giữ draft để thử Phát hành lại cùng preview. Không ghi đè release cũ.

Để dựng EXE từ source cần project PC đầy đủ (catalog/nguồn game không nằm trong Git), Python và tools/requirements.txt. Chạy tools/build.ps1 với OutputName CZN_VietHoa_v1_3_1. Mã APK ở gốc repo; các công cụ cũng hỗ trợ layout project có czn_android_patcher. Kiểm thử PC ký số cần khóa riêng ở máy quản trị; không đưa khóa vào CI công khai.

Kiểm chứng runtime dùng fixture SSRA trong giả lập, không phải phiên gameplay CZN thật. Xiaomi Android 11 của người dùng vẫn cần kiểm chứng bằng Sao chép báo cáo lỗi bước 2 nếu chưa nhận được dữ liệu.
