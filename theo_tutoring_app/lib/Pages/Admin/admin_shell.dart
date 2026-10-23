//This page holds the frame around every admin page.
// It draws the parts of the design that never change, so each page only supplies the middle content.
///Remember this page is shared with every page in the admin

import 'package:flutter/material.dart';

class AdminColors {
  static const primary = Color(0xFF0A3FA6);
  static const accent = Color(0xFF0052D4);
  static const background = Color(0xFFF7F8FA);
  static const border = Color(0xFFE5E7EB);
  static const textDark = Color(0xFF111827);
  static const textMuted = Color(0xFF6B7280);
  static const selected = Color(0xFFE3ECF8);
}

class AdminRoutes {
  static const dashboard = '/admin/dashboard';
  static const students = '/admin/students';
  static const users = '/admin/users';
  static const tutors = '/admin/tutors';
  static const applications = '/admin/applications';
  static const subjects = '/admin/subjects';
  static const reviews = '/admin/reviews';
  static const payouts = '/admin/payouts';
  static const refunds = '/admin/refunds';
  static const reports = '/admin/reports';
  static const monitor = '/admin/monitor';
  static const settings = '/admin/settings';
  static const activity = '/admin/activity';
  static const applicationReview = '/admin/applications/review';
  static const transactions = '/admin/transactions';
  static const transactionDetail = '/admin/transactions/detail';
}

class _NavItem {
  final String label;
  final String route;
  const _NavItem(this.label, this.route);
}

class _NavSection {
  final String title;
  final List<_NavItem> items;
  const _NavSection(this.title, this.items);
}

const _sections = [
  _NavSection('OVERVIEW', [_NavItem('Dashboard', AdminRoutes.dashboard)]),
  _NavSection('USERS', [
    _NavItem('Students', AdminRoutes.students),
    _NavItem('Tutors', AdminRoutes.tutors),
    _NavItem('Applications', AdminRoutes.applications),
    _NavItem('Users', AdminRoutes.users),
  ]),
  _NavSection('CONTENT', [
    _NavItem('Subjects', AdminRoutes.subjects),
    _NavItem('Reviews', AdminRoutes.reviews),
  ]),
  _NavSection('FINANCIALS', [
    _NavItem('Payouts', AdminRoutes.payouts),
    _NavItem('Refunds & Issues', AdminRoutes.refunds),
  ]),
  _NavSection('ANALYTICS', [_NavItem('Reports', AdminRoutes.reports)]),
  _NavSection('SYSTEM', [
    _NavItem('Monitor Platform', AdminRoutes.monitor),
    _NavItem('Settings', AdminRoutes.settings),
  ]),
];

class AdminShell extends StatelessWidget {
  const AdminShell({
    super.key,
    required this.currentRoute,
    required this.child,
    this.adminName,
  });

  final String currentRoute;
  final Widget child;
  final String? adminName;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: AdminColors.background,
      drawer: wide ? null : Drawer(child: _Sidebar(currentRoute: currentRoute)),
      body: Row(
        children: [
          if (wide)
            SizedBox(width: 240, child: _Sidebar(currentRoute: currentRoute)),
          Expanded(
            child: Column(
              children: [
                _TopBar(adminName: adminName, showMenu: !wide),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.currentRoute});
  final String currentRoute;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AdminColors.border)),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const SizedBox(
              height: 64,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.school_outlined, color: AdminColors.primary),
                    SizedBox(width: 8),
                    Text(
                      'Theo Admin',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            for (final section in _sections) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: AdminColors.textMuted,
                  ),
                ),
              ),
              for (final item in section.items)
                _SidebarItem(item: item, selected: item.route == currentRoute),
            ],
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.item, required this.selected});
  final _NavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        if (selected) {
          if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
            Navigator.pop(context);
          }
          return;
        }
        Navigator.pushReplacementNamed(context, item.route);
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: selected ? AdminColors.selected : null,
          border: Border(
            left: BorderSide(
              color: selected ? AdminColors.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          item.label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AdminColors.primary : AdminColors.textDark,
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.adminName, required this.showMenu});
  final String? adminName;
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final showName = MediaQuery.of(context).size.width >= 700;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AdminColors.border)),
      ),
      child: Row(
        children: [
          if (showMenu)
            IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search academic records...',
                    hintStyle: const TextStyle(fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    filled: true,
                    fillColor: const Color(0xFFF3F4F6),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AdminColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AdminColors.border),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 32, color: AdminColors.border),
          const SizedBox(width: 12),
          if (showName)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    adminName ?? '',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AdminColors.textDark,
                    ),
                  ),
                  const Text(
                    'Administrator',
                    style: TextStyle(
                      fontSize: 11,
                      color: AdminColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AdminColors.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.person_outline,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}
