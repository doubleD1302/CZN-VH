import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Shared, offline donation details. QR images are exact crops of the owner's
/// supplied images; a masked MoMo wallet must never be inferred as a phone.
abstract final class DonationDetails {
  static const project = 'Chaos Zero Nightmare';
  static const signature = 'DoubleD1302';
  static const holder = 'NGUYEN DUC DAT';
  static const bank = 'Techcombank';
  static const account = '19075904603016';
  static const formattedAccount = '1907 5904 6030 16';
  static const maskedWallet = '•••••••015';
  static const bankQr = 'assets/donate_bank_qr.png';
  static const momoQr = 'assets/donate_momo_qr.png';

  static String transferNote(String name) =>
      '$project - ${name.trim().replaceAll(RegExp(r'\s+'), ' ')}';
}

class DonationSupporter {
  const DonationSupporter(this.name, this.message);
  final String name;
  final String message;

  static List<DonationSupporter> decode(String source) {
    final data = jsonDecode(source);
    if (data is! Map || data['schema'] != 1 || data['supporters'] is! List) {
      throw const FormatException('Danh sách cảm ơn không đúng định dạng.');
    }
    return (data['supporters'] as List)
        .map((entry) {
          if (entry is! Map || entry['display_name'] is! String) {
            throw const FormatException('Thiếu tên hiển thị đã được đồng ý.');
          }
          final name = (entry['display_name'] as String).trim();
          if (name.isEmpty || name.length > 120) {
            throw const FormatException('Tên hiển thị không hợp lệ.');
          }
          final message = entry['message'];
          if (message != null && (message is! String || message.length > 400)) {
            throw const FormatException('Lời cảm ơn không hợp lệ.');
          }
          return DonationSupporter(
            name,
            message is String && message.trim().isNotEmpty
                ? message.trim()
                : 'Cảm ơn bạn đã cùng đồng hành.',
          );
        })
        .toList(growable: false);
  }
}

enum DonationStatus {
  loading,
  online,
  cached,
  empty,
  error,
}

class DonationResult {
  const DonationResult({
    required this.status,
    this.supporters = const <DonationSupporter>[],
    this.errorMessage,
    this.cachedAt,
  });

  final DonationStatus status;
  final List<DonationSupporter> supporters;
  final String? errorMessage;
  final DateTime? cachedAt;

  bool get hasSupporters => supporters.isNotEmpty;
  bool get isCached => status == DonationStatus.cached;
  bool get isOnline => status == DonationStatus.online;
  bool get isEmpty => status == DonationStatus.empty;
  bool get isError => status == DonationStatus.error;
}

/// Service tải danh sách người ủng hộ trực tuyến từ Google Sheets / Apps Script,
/// quản lý 5 trạng thái (loading, online, cached, empty, error), timeout 25s,
/// retry với backoff và lưu bộ nhớ đệm SharedPreferences bền vững.
abstract final class DonationService {
  static const String endpoint =
      'https://script.google.com/macros/s/AKfycbxjOzLxoLuA5HMLmPsQEdbOs0o52w1GFa97wmV4ET4ZCuyyGs-PMAlYsZqv3esMgH0u/exec?mode=donate';

  static const String cacheKeyData = 'czn_donation_supporters_json';
  static const String cacheKeyTime = 'czn_donation_supporters_time';

  /// Đọc dữ liệu cache từ SharedPreferences an toàn.
  static Future<List<DonationSupporter>?> loadCachedSupporters({
    SharedPreferences? prefs,
  }) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final jsonStr = p.getString(cacheKeyData);
      if (jsonStr == null || jsonStr.trim().isEmpty) return null;
      return DonationSupporter.decode(jsonStr);
    } catch (_) {
      // Dữ liệu cache hỏng: bỏ qua an toàn, không làm sập ứng dụng
      return null;
    }
  }

  /// Lấy mốc thời gian đã lưu cache.
  static Future<DateTime?> getCacheTimestamp({
    SharedPreferences? prefs,
  }) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      final millis = p.getInt(cacheKeyTime);
      if (millis != null && millis > 0) {
        return DateTime.fromMillisecondsSinceEpoch(millis);
      }
    } catch (_) {}
    return null;
  }

  /// Lưu chuỗi JSON hợp lệ và timestamp vào SharedPreferences.
  static Future<void> saveCache(
    String jsonStr, {
    SharedPreferences? prefs,
  }) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      await p.setString(cacheKeyData, jsonStr);
      await p.setInt(cacheKeyTime, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Xóa cache nếu cần.
  static Future<void> clearCache({SharedPreferences? prefs}) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      await p.remove(cacheKeyData);
      await p.remove(cacheKeyTime);
    } catch (_) {}
  }

  /// Thực hiện GET có hỗ trợ follow redirect thủ công tối đa 4 bước
  /// (phòng trường hợp client hoặc mock không tự theo redirect 302).
  static Future<http.Response> _executeWithRedirects(
    http.Client client,
    Uri uri,
    Duration timeout,
  ) async {
    var target = uri;
    for (var i = 0; i < 4; i++) {
      final response = await client.get(target).timeout(timeout);
      if ((response.statusCode == 301 ||
              response.statusCode == 302 ||
              response.statusCode == 303 ||
              response.statusCode == 307 ||
              response.statusCode == 308) &&
          response.headers.containsKey('location')) {
        target = Uri.parse(response.headers['location']!);
        continue;
      }
      return response;
    }
    throw Exception('Quá nhiều lần chuyển hướng máy chủ.');
  }

  /// Tải danh sách với tổng ngân sách 25 giây, tối đa 2 lần thử,
  /// xử lý 5 trạng thái logic rõ rệt và fallback về cache nếu có.
  static Future<DonationResult> fetch({
    http.Client? client,
    SharedPreferences? prefs,
    Duration totalBudget = const Duration(seconds: 25),
    Duration retryDelay = const Duration(milliseconds: 1000),
    String targetEndpoint = endpoint,
  }) async {
    final httpClient = client ?? http.Client();
    final stopwatch = Stopwatch()..start();
    String? lastErrorMessage;

    try {
      for (var attempt = 1; attempt <= 2; attempt++) {
        final elapsed = stopwatch.elapsed;
        final remaining = totalBudget - elapsed;
        if (remaining.inMilliseconds <= 400) {
          lastErrorMessage = 'Hết thời gian chờ phản hồi (timeout).';
          break;
        }

        // Attempt 1: tối đa 14s (hoặc phần còn lại); Attempt 2: dùng toàn bộ thời gian còn lại
        final attemptTimeout = attempt == 1
            ? (remaining > const Duration(seconds: 14)
                ? const Duration(seconds: 14)
                : remaining)
            : remaining;

        try {
          final response = await _executeWithRedirects(
            httpClient,
            Uri.parse(targetEndpoint),
            attemptTimeout,
          );

          if (response.statusCode >= 200 && response.statusCode < 300) {
            final supporters = DonationSupporter.decode(response.body);
            // Ghi đè cache (kể cả khi rỗng, để cập nhật việc gỡ tên)
            await saveCache(response.body, prefs: prefs);

            if (supporters.isEmpty) {
              return const DonationResult(
                status: DonationStatus.empty,
                supporters: [],
              );
            }
            return DonationResult(
              status: DonationStatus.online,
              supporters: supporters,
            );
          } else if (response.statusCode >= 400 && response.statusCode < 500) {
            // Lỗi 4xx (client error): KHÔNG retry
            lastErrorMessage =
                'Yêu cầu không hợp lệ (HTTP ${response.statusCode}).';
            break;
          } else {
            // Lỗi 5xx: được phép thử lại ở lượt 2
            lastErrorMessage =
                'Máy chủ tạm thời bận (HTTP ${response.statusCode}).';
          }
        } on FormatException {
          // Lỗi dữ liệu không đúng cấu trúc (HTML thay vì JSON): KHÔNG retry
          lastErrorMessage = 'Dữ liệu nhận từ máy chủ không đúng định dạng.';
          break;
        } catch (_) {
          lastErrorMessage = 'Không thể kết nối máy chủ.';
        }

        // Nghỉ 1s trước khi thử lại nếu ngân sách còn dư > 1.5s
        if (attempt < 2) {
          final postElapsed = stopwatch.elapsed;
          final postRemaining = totalBudget - postElapsed;
          if (postRemaining.inMilliseconds > 1500) {
            await Future.delayed(retryDelay);
          } else {
            break;
          }
        }
      }
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }

    // Khi kết nối thất bại: kiểm tra bộ nhớ đệm
    final cached = await loadCachedSupporters(prefs: prefs);
    final cachedTime = await getCacheTimestamp(prefs: prefs);

    if (cached != null) {
      if (cached.isEmpty) {
        return const DonationResult(
          status: DonationStatus.empty,
          supporters: [],
        );
      }
      return DonationResult(
        status: DonationStatus.cached,
        supporters: cached,
        cachedAt: cachedTime,
        errorMessage: lastErrorMessage ??
            'Không thể kết nối máy chủ. Đang hiển thị danh sách đã lưu.',
      );
    }

    // Không có cache: hiển thị trạng thái error (tuyệt đối không giả lập empty)
    return DonationResult(
      status: DonationStatus.error,
      errorMessage: lastErrorMessage ??
          'Không thể tải danh sách người ủng hộ. Vui lòng kiểm tra kết nối mạng.',
    );
  }

  /// Giữ tương thích ngược với mã cũ.
  static Future<List<DonationSupporter>> fetchSupporters({
    http.Client? client,
    SharedPreferences? prefs,
    Duration totalBudget = const Duration(seconds: 25),
  }) async {
    final result = await fetch(
      client: client,
      prefs: prefs,
      totalBudget: totalBudget,
    );
    if (result.status == DonationStatus.error) {
      throw Exception(result.errorMessage ?? 'Không thể kết nối máy chủ.');
    }
    return result.supporters;
  }
}

const _ivory = Color(0xFFFFE9CD);
const _gold = Color(0xFFEDC593);
const _muted = Color(0xFFCAC0BA);
const _line = Color(0x559A7855);
const _panel = Color(0xFF1C1B25);

/// This screen has no installer, payment submission, network or public-name
/// registration side effects. The name field only prepares a clipboard note.
class DonateScreen extends StatefulWidget {
  const DonateScreen({
    super.key,
    this.client,
    this.prefs,
    this.retryDelay = const Duration(milliseconds: 1000),
  });

  final http.Client? client;
  final SharedPreferences? prefs;
  final Duration retryDelay;

  @override
  State<DonateScreen> createState() => _DonateScreenState();
}

class _DonateScreenState extends State<DonateScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    initialIndex: 1,
    vsync: this,
  )..addListener(_tabChanged);
  final _name = TextEditingController();
  final _nameFocus = FocusNode();
  String? _nameError;

  DonationResult? _result;
  bool _isLoading = true;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final cached =
        await DonationService.loadCachedSupporters(prefs: widget.prefs);
    if (!mounted) return;
    if (cached != null) {
      final cachedTime =
          await DonationService.getCacheTimestamp(prefs: widget.prefs);
      if (!mounted) return;
      setState(() {
        if (cached.isEmpty) {
          _result = const DonationResult(
            status: DonationStatus.empty,
            supporters: [],
          );
        } else {
          _result = DonationResult(
            status: DonationStatus.cached,
            supporters: cached,
            cachedAt: cachedTime,
          );
        }
        _isLoading = false;
      });
    }

    await _fetch(isUserRefresh: false);
  }

  Future<void> _fetch({required bool isUserRefresh}) async {
    if (_isRefreshing) return;

    if (mounted) {
      setState(() {
        if (_result == null) {
          _isLoading = true;
        }
        if (isUserRefresh) {
          _isRefreshing = true;
        }
      });
    }

    final res = await DonationService.fetch(
      client: widget.client,
      prefs: widget.prefs,
      retryDelay: widget.retryDelay,
    );

    if (!mounted) return;

    if (isUserRefresh && res.status == DonationStatus.cached) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Không thể kết nối máy chủ. Đang hiển thị danh sách đã lưu.',
            ),
          ),
        );
    }

    setState(() {
      _result = res;
      _isLoading = false;
      _isRefreshing = false;
    });
  }

  void _refreshSupporters() {
    _fetch(isUserRefresh: true);
  }

  void _tabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_tabChanged);
    _tabs.dispose();
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _copy(String value, String confirmation) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(confirmation)));
    } on PlatformException {
      if (mounted) await _manualCopy(value);
    } on MissingPluginException {
      if (mounted) await _manualCopy(value);
    }
  }

  Future<void> _manualCopy(String value) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sao chép thủ công'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chưa thể sao chép tự động. Bạn có thể chọn và chép nội dung bên dưới:',
            ),
            const SizedBox(height: 16),
            SelectableText(value, key: const Key('donate-copy-fallback')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );

  void _copyNote() {
    if (_name.text.trim().isEmpty) {
      setState(
        () => _nameError = 'Nhập tên / biệt danh, hoặc ghi “Ẩn danh” nhé.',
      );
      _nameFocus.requestFocus();
      return;
    }
    _copy(
      DonationDetails.transferNote(_name.text),
      'Đã sao chép lời nhắn. Bạn có thể dán vào nội dung chuyển khoản.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(
          fontFamily: 'CznSans',
          bodyColor: _ivory,
          displayColor: _ivory,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF432B30),
          contentTextStyle: TextStyle(fontFamily: 'CznSans', color: _ivory),
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF11121B),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF261720), Color(0xFF11121B), Color(0xFF151D28)],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: SingleChildScrollView(
                    key: const Key('donate-scroll'),
                    padding: const EdgeInsets.fromLTRB(18, 26, 18, 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1040),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _kicker('ỦNG HỘ DỰ ÁN'),
                            const SizedBox(height: 9),
                            _heading('Mỗi tấm lòng, một lời cảm ơn.', 28),
                            const SizedBox(height: 12),
                            const Text(
                              'Sự đồng hành của bạn giúp bản Việt hóa tiếp tục được chăm chút.',
                              style: TextStyle(color: _muted, height: 1.7),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Hoàn toàn tự nguyện · Bản Việt hóa luôn miễn phí.',
                              style: TextStyle(
                                color: _gold,
                                fontSize: 12,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 26),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final wide =
                                    constraints.maxWidth >= 900 &&
                                    MediaQuery.textScalerOf(context)
                                            .scale(14) <=
                                        20;
                                if (!wide) {
                                  return Column(
                                    children: [
                                      _payment(),
                                      const SizedBox(height: 28),
                                      _thanks(),
                                    ],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 14, child: _payment()),
                                    const SizedBox(width: 24),
                                    Expanded(flex: 10, child: _thanks()),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 28),
                            const Divider(color: _line),
                            const SizedBox(height: 8),
                            const Text(
                              'Cảm ơn bạn, theo cách riêng của mình.',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Container(
    decoration: const BoxDecoration(
      color: Color(0xFF14131D),
      border: Border(bottom: BorderSide(color: _line)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    child: Row(
      children: [
        IconButton(
          key: const Key('donate-back'),
          tooltip: 'Về trang chính',
          color: _gold,
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            children: [
              const Text(
                DonationDetails.project,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'CznSerif',
                  color: _ivory,
                  fontSize: 17,
                  height: 1.4,
                ),
              ),
              const Text(
                'VIỆT HÓA',
                style: TextStyle(
                  color: _gold,
                  letterSpacing: 2,
                  fontSize: 11,
                  height: 1.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 56),
      ],
    ),
  );

  Widget _payment() => _frame(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _kicker('GỬI MỘT CHÚT ĐỘNG VIÊN')),
            const Icon(Icons.favorite_border, color: _gold, size: 18),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF11121A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _line),
          ),
          padding: const EdgeInsets.all(4),
          child: TabBar(
            key: const Key('donate-methods'),
            controller: _tabs,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF782232), Color(0xFF4E1927)],
              ),
              border: Border.all(color: const Color(0x99C39767)),
              borderRadius: BorderRadius.circular(5),
            ),
            dividerColor: Colors.transparent,
            labelColor: _ivory,
            unselectedLabelColor: _muted,
            labelStyle: const TextStyle(
              fontFamily: 'CznSans',
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            tabs: const [
              Tab(text: 'MoMo'),
              Tab(text: 'Bank'),
            ],
          ),
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final bank = _tabs.index == 1;
            final qr = _qr(bank);
            final info = _account(bank);
            if (constraints.maxWidth < 485 ||
                MediaQuery.textScalerOf(context).scale(14) > 20) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: qr),
                  const SizedBox(height: 22),
                  info,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                qr,
                const SizedBox(width: 22),
                Expanded(child: info),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        const Divider(color: _line),
        const SizedBox(height: 14),
        const Row(
          children: [
            Icon(Icons.favorite_border, size: 18, color: _gold),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'Để mình biết tên bạn nhé',
                style: TextStyle(
                  color: _gold,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Bạn có thể ghi tên hoặc biệt danh trong lời nhắn chuyển khoản, để mình gửi lời cảm ơn và lưu lại sự đồng hành này trên Bảng vàng. Muốn giữ riêng tư, bạn cứ ghi “Ẩn danh” nhé.',
          style: TextStyle(color: _muted, fontSize: 13, height: 1.8),
        ),
        const SizedBox(height: 18),
        TextField(
          key: const Key('donate-name'),
          controller: _name,
          focusNode: _nameFocus,
          maxLength: 48,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(
            fontFamily: 'CznSans',
            fontSize: 16,
            color: _ivory,
          ),
          decoration: InputDecoration(
            labelText: 'Tên / biệt danh (không bắt buộc)',
            hintText: 'Tên bạn muốn mình nhớ',
            errorText: _nameError,
            errorMaxLines: 3,
            counterText: '',
            filled: true,
            fillColor: const Color(0xFF12131B),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: _line),
            ),
          ),
          onChanged: (_) => setState(() => _nameError = null),
          onSubmitted: (_) => _copyNote(),
        ),
        const SizedBox(height: 12),
        _copyButton(
          'Sao chép lời nhắn',
          _copyNote,
          const Key('donate-copy-note'),
        ),
        const SizedBox(height: 10),
        const Text(
          'Lời nhắn gợi ý',
          style: TextStyle(fontSize: 11, color: _muted),
        ),
        const SizedBox(height: 4),
        SelectableText(
          _name.text.trim().isEmpty
              ? '${DonationDetails.project} - [Tên của bạn]'
              : DonationDetails.transferNote(_name.text),
          key: const Key('donate-note-preview'),
          style: const TextStyle(color: _gold, fontSize: 12, height: 1.7),
        ),
      ],
    ),
  );

  Widget _qr(bool bank) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 248),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: Image.asset(
            bank ? DonationDetails.bankQr : DonationDetails.momoQr,
            key: Key(bank ? 'donate-bank-qr' : 'donate-momo-qr'),
            width: 248,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.none,
            semanticLabel: bank
                ? 'Mã QR Techcombank, NGUYEN DUC DAT, tài khoản 19075904603016'
                : 'Mã QR MoMo, NGUYEN DUC DAT, ví kết thúc 015',
          ),
        ),
        const SizedBox(height: 9),
        Text(
          bank ? 'Quét bằng ứng dụng ngân hàng' : 'Mở MoMo và quét mã để gửi',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 11, height: 1.6),
        ),
      ],
    ),
  );

  Widget _account(bool bank) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        bank ? 'TECHCOMBANK' : 'MoMo',
        style: TextStyle(
          fontSize: bank ? 16 : 25,
          fontWeight: FontWeight.w700,
          color: bank ? const Color(0xFFFF8688) : const Color(0xFFF4C3E0),
        ),
      ),
      const SizedBox(height: 18),
      const Text('Người nhận', style: TextStyle(color: _muted, fontSize: 12)),
      const SizedBox(height: 4),
      const SelectableText(
        DonationDetails.holder,
        style: TextStyle(
          color: _ivory,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        bank ? 'Số tài khoản' : 'Ví MoMo',
        style: const TextStyle(color: _muted, fontSize: 12),
      ),
      const SizedBox(height: 4),
      SelectableText(
        bank ? DonationDetails.formattedAccount : DonationDetails.maskedWallet,
        key: Key(bank ? 'donate-account' : 'donate-wallet'),
        style: const TextStyle(
          fontFamily: 'CznSans',
          color: _ivory,
          fontSize: 23,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 14),
      if (bank)
        _copyButton(
          'Sao chép số tài khoản',
          () => _copy(
            DonationDetails.account,
            'Đã sao chép số tài khoản Techcombank.',
          ),
          const Key('donate-copy-account'),
        )
      else
        const Text(
          'Dùng mã QR để chuyển đến đúng ví.',
          style: TextStyle(color: _muted, fontSize: 12, height: 1.7),
        ),
    ],
  );

  Widget _thanks() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kicker('GỬI BẠN'),
                const SizedBox(height: 10),
                _heading('Có bạn đồng hành,\nmình có thêm động lực.', 23),
                const SizedBox(height: 12),
                const Text(
                  'Dù là một lời góp ý hay một chút ủng hộ, mình đều trân trọng. Cảm ơn bạn đã dành tình cảm cho bản Việt hóa.',
                  style: TextStyle(color: _muted, fontSize: 13, height: 1.8),
                ),
                const SizedBox(height: 12),
                const Text(
                  DonationDetails.signature,
                  style: TextStyle(
                    fontFamily: 'CznSerif',
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                    color: _gold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          ExcludeSemantics(
            child: Image.asset('assets/companion_still.png', width: 94),
          ),
        ],
      ),
      const SizedBox(height: 26),
      _frame(
        gold: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kicker('NHỮNG NGƯỜI BẠN ĐỒNG HÀNH'),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(child: _heading('Bảng vàng cảm ơn', 24)),
                IconButton(
                  key: const Key('donate-refresh-supporters'),
                  icon: _isRefreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _gold,
                          ),
                        )
                      : const Icon(Icons.refresh, color: _gold, size: 20),
                  tooltip: 'Làm mới danh sách',
                  onPressed: _isRefreshing || _isLoading
                      ? null
                      : _refreshSupporters,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Một góc nhỏ để ghi nhớ những tấm lòng đã tiếp sức cho hành trình này.',
              style: TextStyle(color: _muted, fontSize: 13, height: 1.8),
            ),
            const SizedBox(height: 22),
            _buildSupportersSection(),
            const SizedBox(height: 18),
            const Divider(color: _line),
            const SizedBox(height: 9),
            const Text(
              'Chỉ ghi tên khi bạn đồng ý. Mỗi sự đồng hành đều đáng quý như nhau.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.8),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildSupportersSection() {
    if (_isLoading) {
      return const Text(
        'Đang đọc danh sách cảm ơn…',
        style: TextStyle(color: _muted),
      );
    }

    final res = _result;
    if (res == null || res.status == DonationStatus.error) {
      return Padding(
        key: const Key('donate-error-view'),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.wifi_off_outlined, color: _gold, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Không thể tải danh sách người ủng hộ',
                    style: TextStyle(
                      color: _gold,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              res?.errorMessage ??
                  'Vui lòng kiểm tra kết nối mạng và thử lại.',
              style: const TextStyle(color: _muted, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const Key('donate-retry-button'),
              onPressed:
                  _isRefreshing ? null : () => _fetch(isUserRefresh: true),
              icon: const Icon(Icons.refresh, size: 16, color: _gold),
              label: const Text('Thử lại', style: TextStyle(color: _gold)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _gold),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (res.status == DonationStatus.empty || res.supporters.isEmpty) {
      return const Padding(
        key: Key('donate-empty-thanks'),
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.favorite_border, size: 26, color: _gold),
            SizedBox(height: 14),
            Text(
              'Những tấm lòng sẽ được ghi nhớ ở đây.',
              style: TextStyle(
                color: _gold,
                fontSize: 16,
                height: 1.6,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Chưa có tên nào được công bố.',
              style: TextStyle(
                color: _muted,
                fontSize: 12,
                height: 1.7,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (res.status == DonationStatus.cached)
          Container(
            key: const Key('donate-cached-banner'),
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0x22EDC593),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0x44EDC593)),
            ),
            child: const Row(
              children: [
                Icon(Icons.cloud_off_outlined, size: 16, color: _gold),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đang hiển thị danh sách đã lưu ngoại tuyến.',
                    style: TextStyle(color: _gold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        for (final supporter in res.supporters) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.favorite_border,
                  color: _gold,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        supporter.name,
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        supporter.message,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12,
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: _line),
        ],
      ],
    );
  }

  Widget _copyButton(String label, VoidCallback onPressed, Key key) =>
      TextButton.icon(
        key: key,
        onPressed: onPressed,
        icon: const Icon(Icons.copy_outlined, size: 17),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: _gold,
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          textStyle: const TextStyle(fontFamily: 'CznSans', fontSize: 13),
        ),
      );

  Widget _frame({required Widget child, bool gold = false}) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: gold ? const Color(0xFFB99567) : _line,
        width: gold ? 1.2 : 1,
      ),
    ),
    child: child,
  );

  Widget _heading(String text, double size) => Text(
    text,
    style: TextStyle(
      fontFamily: 'CznSerif',
      fontSize: size,
      height: 1.45,
      color: _ivory,
    ),
  );
  Widget _kicker(String text) => Text(
    text,
    style: const TextStyle(
      fontFamily: 'CznSans',
      fontSize: 11,
      color: _gold,
      letterSpacing: 1.3,
      height: 1.7,
    ),
  );
}
