import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/native_bridge.dart';
import '../services/patch_service.dart';
import 'czn_tools_design.dart';

const _body = TextStyle(
  fontFamily: 'CznSans',
  fontSize: 13,
  height: 1.4,
  color: CznToolsColors.muted,
);
const _heading = TextStyle(
  fontFamily: 'CznDisplay',
  fontSize: 20,
  height: 1.12,
  color: CznToolsColors.ivory,
);

/// Presentation only. Native access/install/restore guards remain in the caller.
class CznToolsSetupPage extends StatefulWidget {
  const CznToolsSetupPage({
    super.key,
    required this.status,
    required this.game,
    required this.lastOperation,
    required this.patchVersion,
    required this.installed,
    required this.recovery,
    required this.busy,
    required this.checking,
    required this.downloading,
    required this.progress,
    required this.message,
    required this.onlineMessage,
    this.onAccess,
    this.onCheckGame,
    this.onLaunchGame,
    this.onInstall,
    this.onRestore,
    this.onLocal,
    this.onCopyReport,
    this.onHelp,
    this.onCancelDownload,
    this.onSelectGame,
  });

  final Map<String, dynamic> status, game, lastOperation;
  final String? patchVersion;
  final bool installed, recovery, busy, checking, downloading;
  final double progress;
  final String message, onlineMessage;
  final VoidCallback? onAccess, onCheckGame, onLaunchGame, onInstall, onRestore;
  final VoidCallback? onLocal, onCopyReport, onHelp, onCancelDownload;
  final ValueChanged<String>? onSelectGame;

  @override
  State<CznToolsSetupPage> createState() => _CznToolsSetupPageState();
}

class _CznToolsSetupPageState extends State<CznToolsSetupPage> {
  bool _advanced = false;
  bool get _locked => widget.busy || widget.checking;
  bool get _access => widget.status['accessGranted'] == true;
  bool get _ready => widget.game['success'] == true;
  bool get _isPc => widget.status['package'] == 'smilegate.czn.pc';

  VoidCallback? _guard(VoidCallback? callback) => _locked ? null : callback;

  @override
  Widget build(BuildContext context) {
    final installedVersion = widget.game['installed_version'];
    final newerPatch =
        widget.installed &&
        widget.patchVersion != null &&
        installedVersion != null &&
        widget.patchVersion != installedVersion;
    final installLabel = widget.installed
        ? (newerPatch ? 'Cập nhật bản dịch' : 'Cài lại bản dịch')
        : 'CÀI TIẾNG VIỆT';
    final operation = widget.lastOperation;
    final isPc = widget.status['package'] == 'smilegate.czn.pc';
    return _WorkflowScroll(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SetupProgress(
            access: _access,
            ready: _ready,
            installed: widget.installed,
            isPc: isPc,
          ),
          const SizedBox(height: 12),
          if (widget.recovery) ...[
            _StatePanel(
              heading: 'Cần phục hồi dữ liệu',
              text: 'Lần cài trước chưa hoàn tất. Phục hồi giao dịch trước khi cài tiếp hoặc mở game.',
              error: true,
              child: CznToolsButton(
                label: 'Phục hồi giao dịch',
                onPressed: _guard(widget.onRestore),
                compact: true,
                icon: Icons.restore,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (operation.isNotEmpty && !widget.busy) ...[
            _StatePanel(
              key: const Key('operation-result'),
              heading: operation['phase'] == 'running'
                  ? 'Lần cài trước chưa có kết quả xác minh'
                  : 'Kết quả thao tác gần nhất',
              text: operation['message'] is String
                  ? operation['message'] as String
                  : widget.message,
              error: operation['success'] != true,
              child: operation['success'] == true
                  ? null
                  : _ReportLink(onPressed: widget.onCopyReport),
            ),
            const SizedBox(height: 12),
          ],
          _SetupStep(
            number: '01',
            title: isPc ? 'Thư mục game' : 'Kết nối Local ADB',
            glyph: isPc ? CznToolsGlyph16.folder : CznToolsGlyph16.key,
            helper: isPc
                ? (_ready ? 'Đã nhận diện thư mục game' : 'Chưa tìm thấy game')
                : (_access
                      ? 'Đã kết nối'
                      : 'Chưa kết nối'),
            done: isPc ? _ready : _access,
            actionLabel: isPc
                ? 'Chọn thư mục'
                : (_access
                      ? 'Đã kết nối'
                      : 'Kết nối Local ADB'),
            onPressed: isPc
                ? () async {
                    await NativeBridge.action('chooseGameDir');
                    widget.onCheckGame?.call();
                  }
                : _guard(widget.onAccess),
          ),
          const SizedBox(height: 10),
          _SetupStep(
            number: '02',
            title: isPc ? 'Dữ liệu CZN' : 'Dữ liệu game',
            glyph: CznToolsGlyph16.folder,
            helper: isPc
                ? (_ready
                      ? 'Sẵn sàng cài đặt'
                      : 'Cần tải đủ dữ liệu game qua STOVE.')
                : 'Chọn 日本語 trong game.',
            done: _ready,
            actionLabel: 'Kiểm tra lại dữ liệu',
            onPressed: _guard(widget.onCheckGame),
          ),
          const SizedBox(height: 10),
          _SetupStep(
            number: '03',
            title: 'Cài tiếng Việt',
            glyph: CznToolsGlyph16.install,
            helper: widget.patchVersion == null
                ? 'Đang đọc bản dịch…'
                : 'Gói bản dịch ${widget.patchVersion}',
            done: widget.installed,
            actionLabel: installLabel,
            onPressed: _guard(widget.onInstall),
            primary: true,
            textArt: widget.installed ? null : CznToolsText10.install,
          ),
          if (widget.installed) ...[
            const SizedBox(height: 10),
            Text(
              'Đã cài bản ${installedVersion ?? widget.patchVersion} · Dữ liệu đã kiểm tra',
              textAlign: TextAlign.center,
              style: _body.copyWith(color: const Color(0xFFB0E38B)),
            ),
          ],
          if (installedVersion != null && !widget.installed) ...[
            const SizedBox(height: 10),
            const _StatePanel(
              heading: 'Dữ liệu game đã thay đổi',
              text: 'Hoàn tất cập nhật game trước khi cài lại bản dịch.',
            ),
          ],
          if (widget.game['success'] == false && !widget.busy) ...[
            const SizedBox(height: 10),
            _StatePanel(
              heading: 'Chưa sẵn sàng để cài',
              text: widget.game['message'] is String
                  ? widget.game['message'] as String
                  : 'Mở game, chọn 日本語 và tải đủ dữ liệu trước khi kiểm tra lại.',
              error: true,
              child: _ReportLink(onPressed: widget.onCopyReport),
            ),
          ],
          if (widget.busy || widget.checking) ...[
            const SizedBox(height: 12),
            _StatePanel(
              heading: widget.busy ? 'Đang thực hiện' : 'Đang kiểm tra',
              text: widget.message,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GoldProgress(
                    value: widget.busy ? _progress(widget.progress) : null,
                  ),
                  if (widget.downloading &&
                      widget.onCancelDownload != null) ...[
                    const SizedBox(height: 8),
                    CznToolsButton(
                      label: 'Hủy tải',
                      compact: true,
                      onPressed: widget.onCancelDownload,
                    ),
                  ],
                ],
              ),
            ),
          ] else if (widget.message.isNotEmpty &&
              widget.message != 'Sẵn sàng' &&
              operation.isEmpty) ...[
            const SizedBox(height: 12),
            _StatePanel(
              heading: 'Trạng thái',
              text: widget.message,
              child: _ReportLink(onPressed: widget.onCopyReport),
            ),
          ],
          if (widget.onlineMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                widget.onlineMessage,
                textAlign: TextAlign.center,
                style: _body,
              ),
            ),
          ],
          const SizedBox(height: 14),
          _RestoreLink(onPressed: _guard(widget.onRestore)),
          const SizedBox(height: 8),
          CznToolsPanel(
            variant: 3,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  button: true,
                  expanded: _advanced,
                  label: 'Thao tác và trợ giúp',
                  child: InkWell(
                    onTap: () => setState(() => _advanced = !_advanced),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          const CznToolsIcon(CznToolsGlyph16.layers, size: 21),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('Thao tác và trợ giúp', style: _body),
                          ),
                          Transform.rotate(
                            angle: _advanced ? math.pi / 2 : math.pi,
                            child: const CznToolsIcon(
                              CznToolsGlyph16.back,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_advanced) ...[
                  const CznToolsSeparator(),
                  _advancedControls(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _advancedControls() {
    final rawGames = widget.status['games'];
    final packages = <String>{};
    if (rawGames is List) {
      for (final game in rawGames) {
        if (game is Map && game['package'] is String) {
          final package = game['package'] as String;
          if (package.isNotEmpty) packages.add(package);
        }
      }
    }
    final selected = widget.status['package'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (packages.length > 1) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('setup-package-$selected'),
            initialValue: selected is String && packages.contains(selected)
                ? selected
                : null,
            isExpanded: true,
            dropdownColor: const Color(0xF51D1D2C),
            style: _body.copyWith(color: CznToolsColors.ivory),
            decoration: const InputDecoration(labelText: 'Bản game muốn cài'),
            items: [
              for (final package in packages)
                DropdownMenuItem(
                  value: package,
                  child: Text(package, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _locked || widget.onSelectGame == null
                ? null
                : (package) {
                    if (package != null) widget.onSelectGame!(package);
                  },
          ),
          const SizedBox(height: 12),
        ],
        if (selected is String && selected.isNotEmpty) ...[
          SelectableText(
            'Bản game: $selected',
            style: _body.copyWith(fontSize: 12),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          _isPc
              ? 'Hãy đảm bảo bạn đã đóng game CZN trước khi cài đặt hoặc khôi phục bản dịch. Bộ cài sẽ tự động sao lưu file gốc an toàn.'
              : 'Khởi động Shizuku bằng gỡ lỗi không dây, rồi cấp quyền cho app. Android 8–10 cần máy tính để khởi động Shizuku.',
          style: _body,
        ),
        const SizedBox(height: 10),
        CznToolsButton(
          label: 'Mở CZN',
          compact: true,
          onPressed: _guard(widget.onLaunchGame),
        ),
        const SizedBox(height: 8),
        CznToolsButton(
          label: 'Cài từ gói tải sẵn',
          compact: true,
          icon: Icons.folder_open,
          onPressed: _guard(widget.onLocal),
        ),
        const SizedBox(height: 10),
        Text(
          _isPc
              ? 'Sau khi cài xong, mở game và chọn ngôn ngữ văn bản trong Cài đặt là 日本語 (Tiếng Nhật) để hiển thị toàn bộ Tiếng Việt. Giọng lồng tiếng tùy bạn chọn.'
              : 'Sau khi cài, đặt ngôn ngữ văn bản trong game là 日本語. Bản dịch dùng slot tiếng Nhật; giọng lồng tiếng tùy bạn chọn. Shizuku cần được khởi động lại sau khi điện thoại khởi động.',
          style: _body,
        ),
        const SizedBox(height: 10),
        CznToolsButton(
          label: 'Hướng dẫn và trợ giúp',
          compact: true,
          onPressed: widget.onHelp,
        ),
        const SizedBox(height: 6),
        _ReportLink(onPressed: widget.onCopyReport),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.number,
    required this.title,
    required this.glyph,
    required this.helper,
    required this.done,
    required this.actionLabel,
    required this.onPressed,
    this.primary = false,
    this.textArt,
  });

  final String number, title, helper, actionLabel;
  final CznToolsGlyph16 glyph;
  final bool done, primary;
  final VoidCallback? onPressed;
  final CznToolsText10? textArt;

  @override
  Widget build(BuildContext context) => CznToolsPanel(
    variant: 0,
    padding: const EdgeInsets.fromLTRB(13, 9, 13, 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final wide = constraints.maxWidth >= 315 && scale <= 1.35;
        final action = CznToolsButton(
          label: actionLabel,
          onPressed: onPressed,
          primary: primary,
          compact: true,
          textArt: textArt,
        );
        final helperText = Text(
          helper,
          style: _body.copyWith(color: done ? const Color(0xFFB0E38B) : null),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(number, style: _heading.copyWith(fontSize: 14)),
            const SizedBox(height: 3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CznToolsDecoratedRing(glyph: glyph, size: wide ? 57 : 48),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: _heading.copyWith(fontSize: wide ? 20 : 19),
                      ),
                      const SizedBox(height: 7),
                      if (wide)
                        Row(
                          children: [
                            Expanded(child: helperText),
                            const SizedBox(width: 8),
                            SizedBox(width: primary ? 139 : 122, child: action),
                          ],
                        )
                      else
                        helperText,
                    ],
                  ),
                ),
              ],
            ),
            if (!wide) ...[const SizedBox(height: 10), action],
          ],
        );
      },
    ),
  );
}

class _SetupProgress extends StatelessWidget {
  const _SetupProgress({
    required this.access,
    required this.ready,
    required this.installed,
    this.isPc = false,
  });
  final bool access, ready, installed, isPc;

  @override
  Widget build(BuildContext context) {
    final active = !access ? 0 : (!ready ? 1 : 2);
    final completed = [access, ready, installed];
    final labels = isPc
        ? const ['Thư mục game', 'Dữ liệu CZN', 'Tiếng Việt']
        : const ['Local ADB', 'Dữ liệu game', 'Bản dịch'];
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: CznToolsSideLine(height: 12)),
            const Flexible(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Trạng thái thiết lập', style: _body),
                ),
              ),
            ),
            const Expanded(
              child: CznToolsSideLine(height: 12, pointingRight: false),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Stack(
          alignment: Alignment.center,
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: _SetupConnectorPainter()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var index = 0; index < 3; index++)
                  Semantics(
                    label:
                        '${labels[index]}: ${completed[index] ? "Đã hoàn tất" : "Chưa hoàn tất"}',
                    excludeSemantics: true,
                    child: CznToolsDecoratedRing(
                      selected: index == active,
                      size: 39,
                      child: Text(
                        '0${index + 1}',
                        style: _heading.copyWith(fontSize: 20),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class CznToolsUpdatePage extends StatelessWidget {
  const CznToolsUpdatePage({
    super.key,
    required this.appVersion,
    required this.patchVersion,
    this.update,
    required this.pending,
    required this.checking,
    required this.updating,
    required this.message,
    required this.onlineMessage,
    required this.progress,
    this.onCheck,
    this.onUpdate,
    this.onCancel,
    this.isPc = false,
  });

  final String appVersion, patchVersion, message, onlineMessage;
  final AppUpdateInfo? update;
  final bool pending, checking, updating, isPc;
  final double progress;
  final VoidCallback? onCheck, onUpdate, onCancel;

  @override
  Widget build(BuildContext context) => _WorkflowScroll(
    topFraction: .035,
    child: Column(
      key: const Key('app-update-card'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _UpdateHero(),
        const SizedBox(height: 16),
        _VersionPanel(
          heading: 'Ứng dụng',
          version: appVersion,
          helper: 'Giao diện, icon và chức năng',
          glyph: CznToolsGlyph16.package,
        ),
        const SizedBox(height: 12),
        _VersionPanel(
          heading: 'Bản dịch',
          version: patchVersion,
          helper: 'Gói tiếng Việt đang có',
          glyph: CznToolsGlyph16.translation,
        ),
        const SizedBox(height: 16),
        if (update != null || pending) ...[
          Text(
            pending
                ? 'APK đã tải. Tiếp tục để mở bước cài đặt Android.'
                : 'Có ứng dụng ${update!.version} · ${update!.sizeLabel}',
            textAlign: TextAlign.center,
            style: _body.copyWith(color: CznToolsColors.ivory),
          ),
          const SizedBox(height: 10),
        ],
        if (message.isNotEmpty)
          Semantics(
            liveRegion: true,
            child: SelectableText(
              message,
              style: _body,
              textAlign: TextAlign.center,
            ),
          )
        else
          Text(
            checking
                ? 'Đang kiểm tra phiên bản mới…'
                : 'Kiểm tra để biết có bản mới.',
            textAlign: TextAlign.center,
            style: _body,
          ),
        if (onlineMessage.isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            onlineMessage,
            textAlign: TextAlign.center,
            style: _body.copyWith(fontSize: 12),
          ),
        ],
        if (updating) ...[
          const SizedBox(height: 12),
          _GoldProgress(value: _progress(progress)),
          if (onCancel != null) ...[
            const SizedBox(height: 10),
            CznToolsButton(
              label: 'Hủy tải APK',
              compact: true,
              onPressed: onCancel,
            ),
          ],
        ] else if (update != null || pending) ...[
          const SizedBox(height: 14),
          CznToolsButton(
            key: const Key('app-update-button'),
            label: pending
                ? 'Tiếp tục cập nhật'
                : 'Tải và cập nhật ${update!.version}',
            primary: true,
            onPressed: checking ? null : onUpdate,
            icon: Icons.download,
          ),
        ],
        const SizedBox(height: 14),
        CznToolsButton(
          label: checking ? 'Đang kiểm tra…' : 'KIỂM TRA CẬP NHẬT',
          primary: true,
          textArt: checking ? null : CznToolsText10.checkUpdate,
          onPressed: checking || updating ? null : onCheck,
        ),
        const SizedBox(height: 10),
        Text(
          isPc
              ? 'Bản cập nhật PC sẽ tự động tải và áp dụng trực tiếp vào game.'
              : 'Android sẽ hỏi xác nhận khi cài APK.',
          textAlign: TextAlign.center,
          style: _body,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(child: CznToolsSideLine(height: 14)),
            const SizedBox(width: 8),
            Expanded(
              flex: 8,
              child: Row(
                children: [
                  const CznToolsIcon(CznToolsGlyph16.wifi, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tải nền qua Wi-Fi: APK và bản dịch',
                      textAlign: TextAlign.center,
                      style: _body.copyWith(
                        color: CznToolsColors.ivory,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: CznToolsSideLine(height: 14, pointingRight: false),
            ),
          ],
        ),
        const SizedBox(height: 6),
      ],
    ),
  );
}

class _SetupConnectorPainter extends CustomPainter {
  const _SetupConnectorPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final centers = [size.width / 6, size.width / 2, size.width * 5 / 6];
    final paint = Paint()
      ..color = CznToolsColors.gold
      ..strokeWidth = 1;
    for (var index = 0; index < 2; index++) {
      final left = centers[index] + 19.5;
      final right = centers[index + 1] - 19.5;
      if (right <= left) continue;
      canvas.drawLine(Offset(left, y), Offset(right, y), paint);
      final mid = (left + right) / 2;
      _workflowDiamond(canvas, Offset(mid, y), 2.7);
      _workflowDiamond(canvas, Offset(mid - 5.2, y), 1.15, fill: true);
      _workflowDiamond(canvas, Offset(mid + 5.2, y), 1.15, fill: true);
    }
  }

  @override
  bool shouldRepaint(_SetupConnectorPainter oldDelegate) => false;
}

void _workflowDiamond(
  Canvas canvas,
  Offset center,
  double radius, {
  bool fill = false,
}) {
  final path = Path()
    ..moveTo(center.dx, center.dy - radius)
    ..lineTo(center.dx + radius, center.dy)
    ..lineTo(center.dx, center.dy + radius)
    ..lineTo(center.dx - radius, center.dy)
    ..close();
  final paint = Paint()
    ..color = CznToolsColors.gold
    ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke
    ..strokeWidth = .9;
  canvas.drawPath(path, paint);
}

class _VersionPanel extends StatelessWidget {
  const _VersionPanel({
    required this.heading,
    required this.version,
    required this.helper,
    required this.glyph,
  });
  final String heading, version, helper;
  final CznToolsGlyph16 glyph;

  @override
  Widget build(BuildContext context) => CznToolsPanel(
    variant: 1,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      children: [
        SizedBox.square(
          dimension: 60,
          child: CustomPaint(
            painter: _EmblemFramePainter(),
            child: Center(child: CznToolsIcon(glyph, size: 38)),
          ),
        ),
        const SizedBox(width: 12),
        const SizedBox(
          width: 9,
          height: 64,
          child: RotatedBox(
            quarterTurns: 1,
            child: CznToolsSeparator(height: 9),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                heading,
                style: _body.copyWith(
                  fontSize: 15,
                  color: CznToolsColors.ivory,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                version,
                style: _body.copyWith(
                  fontSize: 26,
                  height: 1.22,
                  color: const Color(0xFFF9F6F1),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(helper, style: _body),
            ],
          ),
        ),
      ],
    ),
  );
}

class _UpdateHero extends StatelessWidget {
  const _UpdateHero();
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 116,
    child: Stack(
      alignment: Alignment.center,
      children: [
        const Positioned.fill(
          child: CustomPaint(painter: _UpdateHeroPainter()),
        ),
        const CznToolsDecoratedRing(
          size: 101,
          child: CznToolsIcon(CznToolsGlyph16.download, size: 43),
        ),
      ],
    ),
  );
}

class _UpdateHeroPainter extends CustomPainter {
  const _UpdateHeroPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 50.0;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .85
      ..color = CznToolsColors.gold;
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(
      center,
      radius + 3.5,
      paint..color = CznToolsColors.gold.withValues(alpha: .76),
    );
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(center.dx - radius - 7, center.dy),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx + radius + 7, center.dy),
      Offset(size.width, center.dy),
      paint,
    );
    for (final delta in const [
      Offset(radius + 3.5, 0),
      Offset(-radius - 3.5, 0),
      Offset(0, radius + 3.5),
      Offset(0, -radius - 3.5),
    ]) {
      _workflowDiamond(canvas, center + delta, 4.4);
      _workflowDiamond(canvas, center + delta, 2.0, fill: true);
    }
  }

  @override
  bool shouldRepaint(_UpdateHeroPainter oldDelegate) => false;
}

class _EmblemFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = CznToolsColors.gold.withValues(alpha: .42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7;
    final p = Path()
      ..moveTo(6, 1)
      ..lineTo(size.width - 6, 1)
      ..lineTo(size.width - 6, 4)
      ..lineTo(size.width - 1, 6)
      ..lineTo(size.width - 1, size.height - 6)
      ..lineTo(size.width - 6, size.height - 4)
      ..lineTo(size.width - 6, size.height - 1)
      ..lineTo(6, size.height - 1)
      ..lineTo(6, size.height - 4)
      ..lineTo(1, size.height - 6)
      ..lineTo(1, 6)
      ..lineTo(6, 4)
      ..close();
    canvas.drawPath(p, paint);
  }

  @override
  bool shouldRepaint(_EmblemFramePainter oldDelegate) => false;
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    super.key,
    required this.heading,
    required this.text,
    this.error = false,
    this.child,
  });
  final String heading, text;
  final bool error;
  final Widget? child;
  @override
  Widget build(BuildContext context) => CznToolsPanel(
    variant: 3,
    accent: error,
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          heading,
          style: _body.copyWith(
            fontWeight: FontWeight.w600,
            color: error ? CznToolsColors.gold : CznToolsColors.ivory,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          liveRegion: true,
          child: SelectableText(
            text,
            style: _body.copyWith(color: CznToolsColors.ivory),
          ),
        ),
        if (child != null) ...[const SizedBox(height: 9), child!],
      ],
    ),
  );
}

class _RestoreLink extends StatelessWidget {
  const _RestoreLink({required this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      button: true,
      enabled: onPressed != null,
      label: 'Khôi phục gốc',
      onTap: onPressed,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(22),
        child: Opacity(
          opacity: onPressed == null ? .45 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CznToolsIcon(CznToolsGlyph16.restore, size: 20),
                const SizedBox(width: 8),
                const SizedBox(
                  width: 117,
                  child: CznToolsLabel(
                    CznToolsText10.restore,
                    semanticsLabel: 'Khôi phục gốc',
                    height: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ReportLink extends StatelessWidget {
  const _ReportLink({required this.onPressed});
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    child: const Text(
      'Sao chép báo cáo lỗi',
      style: TextStyle(
        fontFamily: 'CznSans',
        color: CznToolsColors.gold,
        fontSize: 13,
      ),
    ),
  );
}

class _GoldProgress extends StatelessWidget {
  const _GoldProgress({required this.value});
  final double? value;
  @override
  Widget build(BuildContext context) => LinearProgressIndicator(
    value: value,
    color: CznToolsColors.gold,
    backgroundColor: const Color(0x8055212A),
    minHeight: 4,
    borderRadius: BorderRadius.circular(4),
  );
}

double? _progress(double value) =>
    value.isFinite ? value.clamp(0.0, 1.0).toDouble() : null;

class _WorkflowScroll extends StatelessWidget {
  const _WorkflowScroll({required this.child, this.topFraction = .02});
  final Widget child;
  final double topFraction;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final top = constraints.maxHeight > 440
          ? constraints.maxHeight * topFraction
          : 4.0;
      return SingleChildScrollView(
        padding: EdgeInsets.only(top: top, bottom: 10),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0.0, constraints.maxHeight - top - 10),
          ),
          child: Align(alignment: Alignment.topCenter, child: child),
        ),
      );
    },
  );
}
