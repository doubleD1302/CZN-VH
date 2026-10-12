# Lưu dấu vết bản dịch và thông báo cập nhật

Bộ cài PC 1.3.2 tự theo dõi thay đổi khi nhập hai catalog `data/translations.json`
và `data/story_translations.json`. Lịch sử trong `data/change_history/history.sqlite3`
giữ ID, hàng trước/sau, SHA-256 và thời điểm quan sát. Lần kiểm kê đầu chỉ ghi
hiện trạng; không suy ngày hoàn tất hoặc kết quả review của bản dịch cũ.

Nếu agent sửa catalog bằng script riêng, chạy capture trước khi sửa và ngay
sau mỗi mục/nhóm hoàn tất. Gắn đúng audit/review thực tế bằng đường dẫn tệp:

```powershell
python tools/change_history.py --summary "Trước khi biên tập nhóm ..."
python tools/change_history.py --summary "Hoàn tất nhóm ..." --evidence audit.json --evidence review.json
```

Khi mở Đồng bộ Android, công cụ lấy kênh có chữ ký và gói dịch công khai để
đối chiếu. Phần tự điền nêu các thay đổi còn chờ; phần ghi chú là ô riêng.
Khi dựng, kiểm tra lại từng ID với payload thực tế: mục không được áp dụng
sẽ không được ghi là đã có trong bản cập nhật. Snapshot và chênh lệch được
đóng băng bằng hash, giữ riêng trên máy và không thuộc asset phát hành.

Chỉ ghi nhận sau khi release công khai, kênh đã ký và hash/kích thước mọi
asset được xác thực. Upload lỗi/draft vẫn giữ hàng chờ. Sửa sau khi dựng vẫn
chờ bản kế tiếp. Cập nhật chỉ APK (`--app-only`) và push mã nguồn giữ hàng chờ.
Nếu xác thực bị gián đoạn sau khi release đã công khai, dialog kiểm tra tiếp
cùng release khi bấm Phát hành lại, không tạo hoặc tải lên lần thứ hai.

Lịch sử kỹ thuật không thay review nghĩa JP hoặc kiểm chứng gameplay.
Giữ lịch sử, backup, khóa ký riêng trên máy; không commit/tải chúng lên GitHub.
