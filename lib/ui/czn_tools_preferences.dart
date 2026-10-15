import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../services/notice_policy.dart';
import 'czn_tools_design.dart';

const _cream = CznToolsColors.ivory;
const _white = Color(0xFFF4F2EF);
const _muted = CznToolsColors.muted;
const _gold = CznToolsColors.gold;
const _bodyStyle = TextStyle(
  fontFamily: 'CznSans',
  fontSize: 14,
  height: 1.5,
  color: _white,
);

class CznToolsNoticePage extends StatelessWidget {
  const CznToolsNoticePage({
    super.key,
    this.notice,
    required this.appVersion,
    required this.busy,
    required this.onDismiss,
  });

  final CommunityNotice? notice;
  final String appVersion;
  final bool busy;
  final ValueChanged<bool> onDismiss;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // The card stays bounded even if a caller supplies an outer scroll view.
      // Only its text scrolls; dismiss actions remain next to the reading area.
      final height = constraints.hasBoundedHeight
          ? constraints.maxHeight
          : MediaQuery.sizeOf(context).height * .6;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final compact = height < 240;
      final topGap = height < 400 || scale > 1.3
          ? 0.0
          : (height * .14).clamp(16.0, 98.0);
      final showHelper = height >= 280;
      final footerHeight = scale > 1.3 ? 64.0 : 44.0;
      return SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: topGap),
            Flexible(
              fit: FlexFit.loose,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: compact ? 10 : 18),
                    child: CznToolsPanel(
                      variant: 2,
                      padding: compact
                          ? const EdgeInsets.fromLTRB(12, 8, 12, 8)
                          : const EdgeInsets.fromLTRB(20, 20, 20, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Flexible(
                            fit: FlexFit.loose,
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 26,
                                      bottom: 9,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: _NoticeBadge(active: notice != null),
                                    ),
                                  ),
                                  Text(
                                    notice?.title ?? 'Chưa có thông báo',
                                    style: TextStyle(
                                      fontFamily: 'CznDisplay',
                                      fontSize: compact ? 21 : 25,
                                      fontWeight: FontWeight.w600,
                                      height: 1.22,
                                      color: _white,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    'Ứng dụng $appVersion',
                                    style: _bodyStyle.copyWith(
                                      fontSize: 12,
                                      color: _muted,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const CznToolsSeparator(),
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    notice?.body ??
                                        'Bản tin cộng đồng mới sẽ xuất hiện tại đây khi có thông báo từ kênh cập nhật.',
                                    style: _bodyStyle,
                                  ),
                                  const SizedBox(height: 4),
                                ],
                              ),
                            ),
                          ),
                          if (notice != null) ...[
                            CznToolsSeparator(height: compact ? 7 : 15),
                            SizedBox(height: compact ? 3 : 9),
                            _ActionPair(
                              first: CznToolsButton(
                                label: 'Tắt',
                                textArt: CznToolsText10.dismiss,
                                onPressed: busy ? null : () => onDismiss(false),
                                compact: true,
                              ),
                              second: CznToolsButton(
                                label: 'Tắt trong 24 giờ',
                                textArt: CznToolsText10.snooze,
                                onPressed: busy ? null : () => onDismiss(true),
                                primary: true,
                                compact: true,
                              ),
                              firstFlex: 3,
                              secondFlex: 5,
                              forceHorizontal: compact,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    child: ExcludeSemantics(
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CznToolsDecoratedRing(
                            glyph: CznToolsGlyph16.bell,
                            size: compact ? 36 : 50,
                          ),
                          if (notice != null)
                            Positioned(
                              top: 3,
                              right: 2,
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF6B65),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0xBBFF554F),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (showHelper)
              SizedBox(
                height: footerHeight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: const SingleChildScrollView(
                    child: _InformationLine(
                      text: 'Có thể xem lại bản tin từ biểu tượng thông báo.',
                      centered: true,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class CznToolsSettingsPage extends StatefulWidget {
  const CznToolsSettingsPage({
    super.key,
    required this.companionVisible,
    required this.autoDownload,
    required this.channel,
    required this.appVersion,
    required this.patchVersion,
    required this.busy,
    required this.onSave,
    required this.onCancel,
    this.companionOverlayVisible = false,
    this.overlayActive,
  });

  final bool companionVisible;
  final bool autoDownload;
  final String channel;
  final String appVersion;
  final String patchVersion;
  final bool busy;
  final bool companionOverlayVisible;
  final bool? overlayActive;
  final Function onSave;
  final VoidCallback onCancel;

  @override
  State<CznToolsSettingsPage> createState() => _CznToolsSettingsPageState();
}

class _CznToolsSettingsPageState extends State<CznToolsSettingsPage> {
  late bool _companion;
  late bool _auto;
  late final TextEditingController _channel;
  bool _advanced = false;
  bool _saving = false;
  String? _saveError;
  bool _overlay = false;

  bool get _blocked => widget.busy || _saving;

  @override
  void initState() {
    super.initState();
    _companion = widget.companionVisible;
    _auto = widget.autoDownload;
    _channel = TextEditingController(text: widget.channel);
    _overlay = widget.overlayActive ?? widget.companionOverlayVisible;
    unawaited(_refreshOverlayState());
  }

  Future<void> _refreshOverlayState() async {
    try {
      final running = await NativeBridge.isChibiOverlayRunning();
      if (mounted) setState(() => _overlay = running);
    } catch (_) {}
  }

  Future<void> _toggleOverlay(bool value) async {
    if (_blocked) return;
    try {
      if (value) {
        final canDraw = await NativeBridge.canDrawOverlays();
        if (!canDraw) {
          if (!mounted) return;
          final proceed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF161D2B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xCCDBB486), width: 1),
              ),
              title: const Text(
                'Cấp quyền hiển thị Chibi',
                style: TextStyle(
                  fontFamily: 'CznDisplay',
                  color: Color(0xFFF4F2EF),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: const Text(
                'Để nhân vật Chibi hiển thị nổi ngoài màn hình điện thoại và trên các ứng dụng khác, vui lòng bật quyền "Hiển thị trên các ứng dụng khác" trong Cài đặt Android.',
                style: TextStyle(
                  fontFamily: 'CznSans',
                  color: Color(0xFFD3C0A7),
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Hủy', style: TextStyle(color: Color(0xFFA3B0C2))),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text(
                    'MỞ CÀI ĐẶT',
                    style: TextStyle(
                      color: Color(0xFFFFB1A8),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
          if (proceed == true) {
            await NativeBridge.requestOverlayPermission();
          }
          return;
        }
        await NativeBridge.startChibiOverlay();
        if (mounted) setState(() => _overlay = true);
      } else {
        await NativeBridge.stopChibiOverlay();
        if (mounted) setState(() => _overlay = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể điều khiển Chibi ngoài màn hình: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _channel.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_blocked) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final dynamic func = widget.onSave;
      bool saved;
      try {
        saved = await (func as dynamic)(_companion, _auto, _channel.text.trim(), _overlay);
      } catch (_) {
        saved = await (func as dynamic)(_companion, _auto, _channel.text.trim());
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (!saved) {
          _saveError = 'Chưa lưu được cài đặt. Hãy thử lại.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'Chưa lưu được cài đặt: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) => _PreferencesScroll(
    topFraction: .16,
    builder: (context) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CznToolsPanel(
          variant: 3,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          child: _PreferenceSwitchRow(
            glyph: CznToolsGlyph16.heart,
            title: 'Hiện nhân vật đồng hành',
            subtitle: 'Chibi xuất hiện trên trang chính.',
            value: _companion,
            onChanged: _blocked
                ? null
                : (value) => setState(() => _companion = value),
          ),
        ),
        const SizedBox(height: 10),
        CznToolsPanel(
          variant: 3,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PreferenceSwitchRow(
                glyph: CznToolsGlyph16.layers,
                title: 'Lớp phủ trên ứng dụng khác',
                subtitle: 'Hiện nhân vật nổi khi mở game hoặc ứng dụng khác.',
                value: _overlay,
                onChanged: _blocked ? null : (v) => unawaited(_toggleOverlay(v)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 9),
                child: Divider(
                  height: 1,
                  thickness: .8,
                  color: Color(0xA3D3C0A7),
                ),
              ),
              const _InformationLine(
                text: 'Chạm Chibi để mở app, kéo thả tự do ngoài màn hình.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        CznToolsPanel(
          variant: 3,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PreferenceSwitchRow(
                glyph: CznToolsGlyph16.wifi,
                title: 'Tự tải qua Wi-Fi',
                subtitle: 'Tải cả APK và bản dịch.',
                value: _auto,
                onChanged: _blocked
                    ? null
                    : (value) => setState(() => _auto = value),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 9),
                child: Divider(
                  height: 1,
                  thickness: .8,
                  color: Color(0xA3D3C0A7),
                ),
              ),
              const _InformationLine(
                text: 'Android vẫn hỏi xác nhận cài APK.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        CznToolsPanel(
          variant: 3,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                enabled: !_blocked,
                expanded: _advanced,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _blocked
                        ? null
                        : () => setState(() => _advanced = !_advanced),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          const ExcludeSemantics(
                            child: CznToolsDecoratedRing(
                              glyph: CznToolsGlyph16.layers,
                              size: 46,
                            ),
                          ),
                          const SizedBox(width: 13),
                          const Expanded(
                            child: _PreferenceDescription(
                              title: 'Tùy chọn nâng cao',
                              subtitle: 'Kênh cập nhật đã ký',
                            ),
                          ),
                          const SizedBox(width: 9),
                          ExcludeSemantics(
                            child: Transform.rotate(
                              angle: _advanced ? -math.pi / 2 : math.pi,
                              child: const CznToolsIcon(
                                CznToolsGlyph16.back,
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_advanced) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _channel,
                  enabled: !_blocked,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: _bodyStyle,
                  maxLines: null,
                  decoration: InputDecoration(
                    labelText: 'Địa chỉ kênh cập nhật',
                    helperText: 'Chỉ nhận bản được dự án ký xác thực.',
                    helperMaxLines: 3,
                    labelStyle: _bodyStyle.copyWith(color: _cream),
                    helperStyle: _bodyStyle.copyWith(
                      color: _muted,
                      fontSize: 12,
                    ),
                    filled: true,
                    fillColor: const Color(0x66101723),
                    border: const OutlineInputBorder(
                      borderSide: BorderSide(color: _gold),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0x88D6B890)),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _VersionLine(
          text:
              'Ứng dụng ${widget.appVersion} · Bản dịch ${widget.patchVersion}',
        ),
        const SizedBox(height: 30),
        if (_saveError != null) ...[
          Semantics(
            liveRegion: true,
            child: SelectableText(
              _saveError!,
              style: _bodyStyle.copyWith(color: const Color(0xFFFFB1A8)),
            ),
          ),
          const SizedBox(height: 14),
        ],
        _ActionPair(
          first: CznToolsButton(
            label: 'Hủy',
            onPressed: _blocked ? null : widget.onCancel,
          ),
          second: CznToolsButton(
            label: _saving ? 'Đang lưu…' : 'LƯU CÀI ĐẶT',
            textArt: _saving ? null : CznToolsText10.saveSettings,
            primary: true,
            onPressed: _blocked ? null : _save,
          ),
          firstFlex: 4,
          secondFlex: 5,
        ),
      ],
    ),
  );
}

class _PreferencesScroll extends StatelessWidget {
  const _PreferencesScroll({
    required this.builder,
    required this.topFraction,
  });

  final WidgetBuilder builder;
  final double topFraction;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final gap = height < 400 || scale > 1.3
          ? 12.0
          : (height * topFraction).clamp(16.0, 98.0);
      return SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(top: gap, bottom: 22),
        child: builder(context),
      );
    },
  );
}

class _PreferenceSwitchRow extends StatelessWidget {
  const _PreferenceSwitchRow({
    required this.glyph,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final CznToolsGlyph16 glyph;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final stackSwitch = constraints.maxWidth < 248 || scale > 1.3;
      final control = CznToolsSwitch(
        value: value,
        onChanged: onChanged,
        label: title,
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: CznToolsDecoratedRing(glyph: glyph, size: 46),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: _PreferenceDescription(
                  title: title,
                  subtitle: subtitle,
                ),
              ),
              if (!stackSwitch) ...[
                const SizedBox(width: 12),
                control,
              ],
            ],
          ),
          if (stackSwitch)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Align(alignment: Alignment.centerRight, child: control),
            ),
        ],
      );
    },
  );
}

class _PreferenceDescription extends StatelessWidget {
  const _PreferenceDescription({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: _bodyStyle.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 3),
      Text(subtitle, style: _bodyStyle.copyWith(fontSize: 13, color: _muted)),
    ],
  );
}

class _ActionPair extends StatelessWidget {
  const _ActionPair({
    required this.first,
    required this.second,
    this.firstFlex = 1,
    this.secondFlex = 1,
    this.forceHorizontal = false,
  });

  final Widget first;
  final Widget second;
  final int firstFlex;
  final int secondFlex;
  final bool forceHorizontal;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (!forceHorizontal && (constraints.maxWidth < 240 || scale > 1.3)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [first, const SizedBox(height: 10), second],
        );
      }
      return Row(
        children: [
          Expanded(flex: firstFlex, child: first),
          const SizedBox(width: 12),
          Expanded(flex: secondFlex, child: second),
        ],
      );
    },
  );
}

class _NoticeBadge extends StatelessWidget {
  const _NoticeBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: active ? const Color(0xBB7D2026) : const Color(0x991B2330),
      border: Border.all(color: const Color(0xCCDBB486), width: .8),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(
        active ? '✦  BẢN TIN MỚI' : 'BẢN TIN CỘNG ĐỒNG',
        style: _bodyStyle.copyWith(fontSize: 11, color: _cream),
      ),
    ),
  );
}

class _InformationLine extends StatelessWidget {
  const _InformationLine({required this.text, this.centered = false});

  final String text;
  final bool centered;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: centered
        ? MainAxisAlignment.center
        : MainAxisAlignment.start,
    children: [
      const ExcludeSemantics(
        child: Icon(Icons.info_outline, color: _muted, size: 19),
      ),
      const SizedBox(width: 9),
      Flexible(
        child: Text(
          text,
          style: _bodyStyle.copyWith(fontSize: 12, color: _muted),
        ),
      ),
    ],
  );
}

class _VersionLine extends StatelessWidget {
  const _VersionLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox(
        width: 26,
        child: CznToolsSideLine(height: 14),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: _bodyStyle.copyWith(fontSize: 11, color: _muted),
        ),
      ),
      const SizedBox(width: 9),
      const SizedBox(
        width: 26,
        child: CznToolsSideLine(height: 14, pointingRight: false),
      ),
    ],
  );
}
