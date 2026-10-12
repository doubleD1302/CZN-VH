class CommunityNotice {
  final String id, title, body;
  const CommunityNotice(this.id, this.title, this.body);
  static CommunityNotice? fromChannel(Map<String, dynamic> channel) {
    final value = channel['notice'];
    if (value is! Map || value['enabled'] != true) return null;
    final id = value['id'], title = value['title'], body = value['body'];
    if (id is! String ||
        title is! String ||
        body is! String ||
        id.isEmpty ||
        id.length > 160 ||
        title.trim().isEmpty ||
        title.length > 200 ||
        body.trim().isEmpty ||
        body.length > 12000) {
      return null;
    }
    return CommunityNotice(id, title, body);
  }

  bool isSnoozed(Map<String, dynamic> status, DateTime now) =>
      status['noticeSnoozeId'] == id &&
      (status['noticeSnoozeUntil'] as num? ?? 0) > now.millisecondsSinceEpoch;
}
