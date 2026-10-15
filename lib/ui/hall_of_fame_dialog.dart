import 'package:flutter/material.dart';

import '../services/bug_reporter_service.dart';

class HallOfFameDialog extends StatefulWidget {
  const HallOfFameDialog({super.key});

  @override
  State<HallOfFameDialog> createState() => _HallOfFameDialogState();
}

class _HallOfFameDialogState extends State<HallOfFameDialog> {
  late Future<List<Map<String, dynamic>>> _leaderboardFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _leaderboardFuture = BugReporterService.fetchHallOfFame();
    });
  }

  Widget _buildRankBadge(int rank) {
    if (rank == 1) {
      return Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: Color(0xFFFFD700),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text('🥇', style: TextStyle(fontSize: 18)),
        ),
      );
    } else if (rank == 2) {
      return Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: Color(0xFFC0C0C0),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text('🥈', style: TextStyle(fontSize: 18)),
        ),
      );
    } else if (rank == 3) {
      return Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: Color(0xFFCD7F32),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Text('🥉', style: TextStyle(fontSize: 18)),
        ),
      );
    } else {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFFFFE3DC),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFB03B50), width: 1),
        ),
        child: Center(
          child: Text(
            '$rank',
            style: const TextStyle(
              color: Color(0xFF9E233A),
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440, maxHeight: 600),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8EE),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFB03B50), width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 22,
              offset: Offset(0, 9),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                const Icon(
                  Icons.volunteer_activism_rounded,
                  color: Color(0xFFB03B50),
                  size: 28,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Lời Cám Ơn',
                    style: TextStyle(
                      color: Color(0xFF292332),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Color(0xFF9E233A)),
                  tooltip: 'Làm mới',
                  onPressed: _refresh,
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF292332)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // Khung Lời Cám Ơn Tri Ân
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFFFECE6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5A8B0), width: 1.2),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.favorite_rounded,
                    color: Color(0xFFB03B50),
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TRI ÂN THUYỀN TRƯỞNG',
                          style: TextStyle(
                            color: Color(0xFF9E233A),
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: .5,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Dự án Việt Hóa Chaos Zero Nightmare xin gửi lời cảm ơn và tri ân sâu sắc nhất tới toàn thể các Thuyền Trưởng đã nhiệt tình trải nghiệm, đồng hành và tích cực đóng góp báo lỗi, trau chuốt câu từ để bản dịch ngày một trọn vẹn và hoàn hảo hơn! ♥',
                          style: TextStyle(
                            color: Color(0xFF4A3E4E),
                            fontSize: 12.5,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Tiêu đề Bảng Xếp Hạng
            Row(
              children: [
                const Icon(
                  Icons.emoji_events_rounded,
                  color: Color(0xFFD4AF37),
                  size: 20,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Bảng Xếp Hạng Đóng Góp',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF292332),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF81C784), width: 0.8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Chỉ tính lỗi FIXED',
                        style: TextStyle(
                          color: Color(0xFF1B5E20),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Divider(color: Color(0xFFB03B50), thickness: 1),
            const SizedBox(height: 6),

            // Content List
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _leaderboardFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFB03B50),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Lỗi tải bảng vinh danh: ${snapshot.error}',
                        style: const TextStyle(color: Color(0xFF9E233A)),
                      ),
                    );
                  }

                  final list = snapshot.data ?? const [];
                  if (list.isEmpty) {
                    return const Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.military_tech_outlined,
                              size: 36,
                              color: Color(0xFFD3C0A7),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Chưa có dữ liệu vinh danh.',
                              style: TextStyle(
                                color: Color(0xFF6B6275),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Hãy là Thuyền Trưởng đầu tiên gửi báo lỗi nhé!',
                              style: TextStyle(
                                color: Color(0xFF8A7F92),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (context, index) => const Divider(
                      height: 1,
                      color: Color(0xFFEADBCE),
                    ),
                    itemBuilder: (context, index) {
                      final item = list[index];
                      final sender = item['sender']?.toString() ?? 'Thuyền Trưởng';
                      final count = item['count']?.toString() ?? '1';
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            _buildRankBadge(index + 1),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                sender,
                                style: const TextStyle(
                                  color: Color(0xFF292332),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFE3DC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFB03B50),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                '$count lỗi đã fix',
                                style: const TextStyle(
                                  color: Color(0xFF9E233A),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // Footer
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Đóng',
                  style: TextStyle(
                    color: Color(0xFF9E233A),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
