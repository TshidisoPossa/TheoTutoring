import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/in_app_notifications.dart';
import 'Tutor/tutor_format.dart'; // notificationTime
import 'Tutor/tutor_theme.dart';

// The bell page. Students and tutors see the same layout (documentation
// 9.4); Tutor/tutor_notifications.dart and
// Student/student_notifications.dart fill in what differs.

// ── Model ─────────────────────────────────────────────────────────────────────

/// One card, from GET /TutorLandingpage/notifications or
/// GET /students/notifications.
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.read,
    required this.section,
    required this.minutesAgo,
    this.bookingId,
    this.tutorId,
    this.subjectId,
    this.createdAt,
  });

  final String id;
  final String type;       // e.g. UpcomingSession, PaymentReceived, NewReview
  final String title;      // label above the message, e.g. "Upcoming lesson"
  final String body;
  final bool read;
  final String section;    // today | yesterday | earlier
  final int minutesAgo;
  final int? bookingId;    // the lesson the card is about, if any
  final int? tutorId;      // "Book a new time" with this tutor...
  final int? subjectId;    // ...for this subject (rescheduled lessons)
  final String? createdAt; // ISO time

  factory NotificationItem.fromJson(Map<String, dynamic> j) {
    return NotificationItem(
      id: j['id']?.toString() ?? '',
      type: j['type']?.toString() ?? '',
      title: j['title']?.toString() ?? '',
      body: j['body']?.toString() ?? '',
      read: j['read'] == true,
      section: j['section']?.toString() ?? 'earlier',
      minutesAgo: (j['minutesAgo'] as num?)?.toInt() ?? 0,
      bookingId: (j['bookingId'] as num?)?.toInt(),
      tutorId: (j['tutorId'] as num?)?.toInt(),
      subjectId: (j['subjectId'] as num?)?.toInt(),
      createdAt: j['createdAt']?.toString(),
    );
  }

  NotificationItem copyWith({required bool read}) => NotificationItem(
        id: id,
        type: type,
        title: title,
        body: body,
        read: read,
        section: section,
        minutesAgo: minutesAgo,
        bookingId: bookingId,
        tutorId: tutorId,
        subjectId: subjectId,
        createdAt: createdAt,
      );
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// The bell page. Tapping a bottom-bar tab pops it with that tab's index, so
/// the dashboard underneath can open the tab.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({
    super.key,
    this.roleLabel,
    required this.loadNotifications,
    required this.markRead,
    required this.markAllRead,
    this.bottomNav,
    required this.emptyMessage,
    this.accent = const Color(0xFF246BFE),
    this.linkLabel,
    this.onLink,
  });

  /// The chip next to the title, e.g. "Tutor". No chip when null (the
  /// student page has none).
  final String? roleLabel;

  /// Loads the page: `unreadCount` and `notifications`.
  final Future<Map<String, dynamic>> Function() loadNotifications;

  /// Marks one card read; returns the new unread count.
  final Future<int> Function(String id) markRead;

  /// "Mark all as read"; returns the new unread count.
  final Future<int> Function() markAllRead;

  /// The role's bottom bar, with no tab highlighted. Call [goToTab] on a tap.
  /// Null for admins, who have no bottom bar.
  final Widget Function(ValueChanged<int> goToTab)? bottomNav;

  /// Shown when there are no notifications yet.
  final String emptyMessage;

  /// Blue used for unread labels, dots and links.
  final Color accent;

  /// The link under a card, e.g. "View scheduled lesson", or null for none.
  final String? Function(NotificationItem n)? linkLabel;

  /// Opens what the link points to (the card is already marked read).
  final Future<void> Function(BuildContext context, NotificationItem n)? onLink;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationItem> _items = [];
  int _unread = 0;
  bool _loading = true;
  bool _markingAll = false;
  String? _error;

  // Light colours, or the dark ones while dark mode is on
  bool get _dk => context.tutorDark;
  Color get _bg => _dk ? TutorDark.background : const Color(0xFFF2F4F8);
  Color get _surface => _dk ? TutorDark.card : Colors.white;
  Color get _dark => _dk ? TutorDark.text : const Color(0xFF1A1A2E);
  Color get _muted => _dk ? TutorDark.textFaint : const Color(0xFF9CA3AF);
  Color get _grey => _dk ? TutorDark.textMuted : const Color(0xFF6B7280);
  Color get _greyBg => _dk ? TutorDark.cardAlt : const Color(0xFFF1F3F6);
  Color get _border => _dk ? TutorDark.border : const Color(0xFFE5E7EB);

  Color get _accent => widget.accent;
  Color get _accentBg => widget.accent.withValues(alpha: 0.1);

  static const _sections = {
    'today': 'Today',
    'yesterday': 'Yesterday',
    'earlier': 'Earlier',
  };

  final _live = InAppNotifications.instance;

  @override
  void initState() {
    super.initState();
    // No pop-ups over this page; new ones are added to the list instead
    _live.pageOpened();
    _live.unreadCount.addListener(_onLiveCount);
    _load();
  }

  @override
  void dispose() {
    _live.unreadCount.removeListener(_onLiveCount);
    _live.pageClosed();
    super.dispose();
  }

  // The in-app check saw more unread than this page shows: reload it
  void _onLiveCount() {
    if (!_loading && _live.unreadCount.value > _unread) _load();
  }

  // Keeps the bells' live number in step with this page
  void _syncLive() => _live.unreadCount.value = _unread;

  Future<void> _load() async {
    setState(() { _loading = _items.isEmpty; _error = null; });
    try {
      final data = await widget.loadNotifications();
      final items = (data['notifications'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map(NotificationItem.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _items = items;
        _unread = (data['unreadCount'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
      _syncLive();
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // Shows the card as read straight away; puts it back if the server
  // could not save it.
  Future<void> _markRead(NotificationItem n) async {
    if (n.read) return;
    void replace(NotificationItem card) => setState(() {
          _items = [for (final i in _items) i.id == n.id ? card : i];
        });

    replace(n.copyWith(read: true));
    setState(() => _unread = _unread > 0 ? _unread - 1 : 0);
    try {
      final unread = await widget.markRead(n.id);
      if (mounted) setState(() => _unread = unread);
      if (mounted) _syncLive();
    } catch (e) {
      if (!mounted) return;
      replace(n);
      setState(() => _unread++);
      _showMessage(e.toString());
    }
  }

  Future<void> _markAllRead() async {
    setState(() => _markingAll = true);
    try {
      final unread = await widget.markAllRead();
      if (!mounted) return;
      setState(() {
        _items = [for (final i in _items) i.copyWith(read: true)];
        _unread = unread;
      });
      _syncLive();
    } catch (e) {
      if (mounted) _showMessage(e.toString());
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _openLink(NotificationItem n) async {
    _markRead(n);
    await widget.onLink?.call(context, n);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: _accent))
                  : _error != null
                      ? _buildError()
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: _accent,
                          child: _items.isEmpty
                              ? _buildEmpty()
                              : _buildList(),
                        ),
            ),
          ],
        ),
      ),
      // Admins have no bottom bar
      bottomNavigationBar: widget.bottomNav?.call(
        (index) => Navigator.pop(context, index),
      ),
    );
  }

  // ── HEADER ───────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      color: _surface,
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_rounded, color: _dark),
            tooltip: 'Back',
          ),
          Expanded(
            child: Text(
              'Notifications',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _dark,
              ),
            ),
          ),
          if (widget.roleLabel case final label?)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _accentBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── LIST ─────────────────────────────────────────────────────────────────────

  Widget _buildList() {
    final children = <Widget>[];
    var first = true;
    for (final entry in _sections.entries) {
      final items = _items.where((n) => n.section == entry.key).toList();
      if (items.isEmpty) continue;
      children.add(_buildSectionHeader(entry.value, showUnread: first));
      for (final n in items) {
        children.add(_buildCard(n));
      }
      first = false;
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: children,
    );
  }

  // "Today  3 unread                    Mark all as read"
  Widget _buildSectionHeader(String label, {required bool showUnread}) {
    final unread = showUnread && _unread > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 10),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _dark,
                  ),
                ),
                if (unread) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '$_unread unread',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 12, color: _muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (unread)
            GestureDetector(
              onTap: _markingAll ? null : _markAllRead,
              child: Text(
                _markingAll ? 'Marking…' : 'Mark all as read',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _markingAll ? _muted : _accent,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static IconData _iconFor(String type) => switch (type) {
        'UpcomingSession' => Icons.calendar_month_outlined,
        'BookingConfirmed' => Icons.event_available_outlined,
        'BookingCancelled' => Icons.event_busy_outlined,
        'BookingPostponed' => Icons.update_rounded,
        'BookingRescheduled' => Icons.event_repeat_rounded,
        'PaymentReceived' => Icons.check_circle_outline_rounded,
        'PaymentFailed' => Icons.error_outline_rounded,
        'RefundApproved' => Icons.currency_exchange_rounded,
        'RefundDenied' => Icons.money_off_rounded,
        'NewReview' => Icons.star_outline_rounded,
        'NewMessage' => Icons.chat_bubble_outline_rounded,
        'AccountSuspended' => Icons.block_rounded,
        'AppealApproved' => Icons.verified_user_outlined,
        'AppealRejected' => Icons.gpp_bad_outlined,
        // Admin notifications
        'ApplicationSubmitted' => Icons.assignment_ind_outlined,
        'ReportSubmitted' => Icons.flag_outlined,
        'RefundRequested' => Icons.currency_exchange_rounded,
        _ => Icons.notifications_none_rounded,
      };

  Widget _buildCard(NotificationItem n) {
    final unread = !n.read;
    final link = widget.onLink == null ? null : widget.linkLabel?.call(n);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _markRead(n),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: unread ? _accentBg : _greyBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_iconFor(n.type),
                          size: 20, color: unread ? _accent : _grey),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            n.title,
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: unread ? _accent : _grey,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            n.body,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _dark,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            notificationTime(
                                n.section, n.minutesAgo, n.createdAt),
                            style:
                                GoogleFonts.inter(fontSize: 11.5, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    if (unread)
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(left: 8, top: 4),
                        decoration: BoxDecoration(
                          color: _accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                if (link != null) ...[
                  const SizedBox(height: 12),
                  Divider(height: 1, color: _border),
                  InkWell(
                    onTap: () => _openLink(n),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              link,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: _accent,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              size: 20, color: _accent),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── EMPTY / ERROR ────────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    // A ListView so pull-to-refresh still works with nothing in it
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 96, 32, 24),
      children: [
        Icon(Icons.notifications_none_rounded, size: 56, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text(
          'No notifications yet',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: _dark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.emptyMessage,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 13, color: _grey, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: _dk ? TutorDark.textMuted : Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _loading = true);
                _load();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: Text('Retry',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
