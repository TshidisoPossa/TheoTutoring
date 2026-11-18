import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../Pages/notifications_screen.dart' show NotificationItem;
import 'app_navigator.dart';

/// In-app notification pop-ups for students, tutors and admins.
///
/// While someone is signed in, this checks their notifications every
/// [pollInterval] (the same list their bell page loads). Anything new and
/// unread slides in as a banner at the top of the screen, like a WhatsApp
/// message, and goes away by itself after [bannerDuration]. Tapping it
/// opens the Notifications page; swiping it up closes it.
///
/// The first check after signing in only remembers what is already there,
/// so old notifications never pop up. While the Notifications page is open
/// no banners show (the list is already on screen).
///
/// [unreadCount] follows every check, so bells can show the live number.
class InAppNotifications {
  InAppNotifications._();

  static final instance = InAppNotifications._();

  static const pollInterval = Duration(seconds: 15);
  static const bannerDuration = Duration(seconds: 4);

  /// Unread notifications, updated on every check (0 when signed out).
  final unreadCount = ValueNotifier<int>(0);

  Future<Map<String, dynamic>> Function()? _fetch;
  VoidCallback? _openPage;
  Timer? _timer;
  bool _checking = false;
  bool _baselineTaken = false;
  final _seen = <String>{};
  final _queue = Queue<NotificationItem>();
  OverlayEntry? _banner;
  Timer? _bannerTimer;
  int _pageOpen = 0;

  /// Where banners are shown; tests pass their own.
  @visibleForTesting
  OverlayState? Function() overlayFinder = () =>
      appNavigatorKey.currentState?.overlay;

  bool get isRunning => _timer != null;

  /// Starts watching the signed-in user's notifications. [fetch] is their
  /// list (GET .../notifications); [openPage] opens their bell page.
  void start({
    required Future<Map<String, dynamic>> Function() fetch,
    required VoidCallback openPage,
  }) {
    stop();
    _fetch = fetch;
    _openPage = openPage;
    _timer = Timer.periodic(pollInterval, (_) => check());
    check(); // the baseline
  }

  /// Stops watching (signing out) and removes any banner.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _fetch = null;
    _openPage = null;
    _baselineTaken = false;
    _seen.clear();
    _queue.clear();
    _hideBanner();
    unreadCount.value = 0;
  }

  /// The Notifications page calls these while it is open: no banners then.
  void pageOpened() => _pageOpen++;
  void pageClosed() => _pageOpen = _pageOpen > 0 ? _pageOpen - 1 : 0;

  /// One check: remembers every id, queues new unread ones as banners.
  @visibleForTesting
  Future<void> check() async {
    final fetch = _fetch;
    if (fetch == null || _checking) return;
    _checking = true;
    try {
      final body = await fetch();
      if (_fetch != fetch) return; // signed out (or someone else) meanwhile
      final items = [
        for (final n in body['notifications'] as List? ?? const [])
          if (n is Map<String, dynamic>) NotificationItem.fromJson(n),
      ];
      final unread = body['unreadCount'];
      unreadCount.value = unread is num
          ? unread.toInt()
          : items.where((n) => !n.read).length;

      final fresh = [
        for (final n in items)
          if (n.id.isNotEmpty && !_seen.contains(n.id)) n,
      ];
      _seen.addAll(fresh.map((n) => n.id));
      if (!_baselineTaken) {
        _baselineTaken = true; // what was there before: no pop-ups
        return;
      }
      if (_pageOpen > 0) return;
      // Oldest first, so they show in the order they arrived
      for (final n in fresh.reversed) {
        if (!n.read) _queue.add(n);
      }
      _showNext();
    } catch (_) {
      // Quiet: the next check tries again; the bell page shows errors.
    } finally {
      _checking = false;
    }
  }

  void _showNext() {
    if (_banner != null || _queue.isEmpty || _pageOpen > 0) return;
    final overlay = overlayFinder();
    if (overlay == null) return;
    final item = _queue.removeFirst();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => NotificationBanner(
        item: item,
        onTap: () {
          _queue.clear(); // the page lists the rest
          _hideBanner();
          _openPage?.call();
        },
        onDismiss: () {
          _hideBanner();
          _showNext();
        },
      ),
    );
    _banner = entry;
    overlay.insert(entry);
    _bannerTimer = Timer(bannerDuration, () {
      _hideBanner();
      _showNext();
    });
  }

  void _hideBanner() {
    _bannerTimer?.cancel();
    _bannerTimer = null;
    _banner?.remove();
    _banner = null;
  }
}

/// The pop-up itself: a card at the top of the screen with the
/// notification's icon, title and message. It slides down when shown.
class NotificationBanner extends StatefulWidget {
  const NotificationBanner({
    required this.item,
    required this.onTap,
    required this.onDismiss,
    super.key,
  });

  final NotificationItem item;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  State<NotificationBanner> createState() => _NotificationBannerState();
}

class _NotificationBannerState extends State<NotificationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..forward();

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  static IconData iconFor(String type) => switch (type) {
    'NewMessage' => Icons.chat_bubble_outline_rounded,
    'ChatFlagged' ||
    'ChatSuspensionKept' => Icons.speaker_notes_off_outlined,
    'ChatRestored' => Icons.mark_chat_read_outlined,
    'UpcomingSession' => Icons.alarm_rounded,
    'PaymentReceived' || 'PaymentFailed' => Icons.payments_outlined,
    'RefundApproved' || 'RefundDenied' || 'RefundRequested' =>
      Icons.currency_exchange_rounded,
    'NewReview' => Icons.star_outline_rounded,
    'ApplicationSubmitted' ||
    'ApplicationApproved' ||
    'ApplicationRejected' => Icons.assignment_ind_outlined,
    'ReportSubmitted' => Icons.flag_outlined,
    'BookingCancelled' || 'BookingDeclined' => Icons.event_busy_outlined,
    'BookingRescheduled' || 'BookingPostponed' => Icons.event_repeat_rounded,
    _ => Icons.event_available_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF1F2937) : Colors.white;
    final text = dark ? Colors.white : const Color(0xFF17233D);
    final muted = dark ? const Color(0xFFB6BFCC) : const Color(0xFF5B6475);
    const blue = Color(0xFF246BFE);
    final item = widget.item;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, -1.2),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: _slide, curve: Curves.easeOut)),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Dismissible(
                key: ValueKey('banner-${item.id}'),
                direction: DismissDirection.up,
                onDismissed: (_) => widget.onDismiss(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  child: Material(
                    color: surface,
                    elevation: 8,
                    shadowColor: Colors.black38,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      key: const ValueKey('in-app-notification-banner'),
                      borderRadius: BorderRadius.circular(16),
                      onTap: widget.onTap,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: blue.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                iconFor(item.type),
                                color: blue,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.title.isEmpty
                                              ? 'New notification'
                                              : item.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: text,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        'now',
                                        style: TextStyle(
                                          color: muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.body,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: muted,
                                      fontSize: 13,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
