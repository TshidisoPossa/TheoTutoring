import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF1457D9);
  static const primaryDark = Color(0xFF084CC8);
  static const background = Color(0xFFF8F7FF);
  static const surface = Colors.white;
  static const text = Color(0xFF242638);
  static const secondaryText = Color(0xFF666978);
  static const muted = Color(0xFF9295A3);
  static const border = Color(0xFFE6E7EF);
  static const iconBackground = Color(0xFFF0F3FA);
  static const danger = Color(0xFFD62828);
  static const green = Color(0xFF28C76F);
}

class SideNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onNavigationChanged;

  const SideNavigation({
    super.key,
    required this.selectedIndex,
    required this.onNavigationChanged,
  });

  @override
  Widget build(BuildContext context) {
    final navigationItems = [
      NavigationItem(
        icon: Icons.home_rounded,
        label: 'Home',
        selected: selectedIndex == 0,
        onTap: () => onNavigationChanged(0),
      ),
      NavigationItem(
        icon: Icons.menu_book_rounded,
        label: 'Subjects',
        selected: selectedIndex == 1,
        onTap: () => onNavigationChanged(1),
      ),
    ];

    final secondaryItems = [
      NavigationItem(
        icon: Icons.history_rounded,
        label: 'Session History',
        selected: selectedIndex == 4,
        onTap: () => onNavigationChanged(4),
      ),
      NavigationItem(
        icon: Icons.settings_outlined,
        label: 'Settings',
        selected: selectedIndex == 5,
        onTap: () => onNavigationChanged(5),
      ),
    ];

    return Container(
      width: 290,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Theo Tutoring',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ),
                const Icon(Icons.close_rounded, color: AppColors.secondaryText),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(children: navigationItems),
          ),
          const SizedBox(height: 18),
          const Divider(indent: 22, endIndent: 22, color: AppColors.border),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(children: secondaryItems),
          ),
          const Spacer(),
          const Divider(color: AppColors.border),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                const Icon(Icons.logout_rounded, color: AppColors.danger),
                const SizedBox(width: 14),
                const Text(
                  'Log Out',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.danger,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardContent extends StatelessWidget {
  final bool isDesktop;
  final int selectedIndex;
  final ValueChanged<int> onNavigationChanged;

  const DashboardContent({
    super.key,
    required this.isDesktop,
    required this.selectedIndex,
    required this.onNavigationChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 34 : 18,
          vertical: 18,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopBar(context),
                const SizedBox(height: 28),
                const WelcomeSection(),
                const SizedBox(height: 28),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 750) {
                      return const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              children: [
                                QuickActions(),
                                SizedBox(height: 25),
                                UpcomingSession(),
                                SizedBox(height: 25),
                                TutorSection(),
                              ],
                            ),
                          ),
                          SizedBox(width: 24),
                          Expanded(flex: 2, child: CalendarCard()),
                        ],
                      );
                    }
                    return const Column(
                      children: [
                        QuickActions(),
                        SizedBox(height: 25),
                        UpcomingSession(),
                        SizedBox(height: 25),
                        CalendarCard(),
                        SizedBox(height: 25),
                        TutorSection(),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      children: [
        if (!isDesktop)
          IconButton(onPressed: () {}, icon: const Icon(Icons.menu_rounded)),
        if (!isDesktop) const Spacer(),
        if (!isDesktop) const UserAvatar(size: 38),
      ],
    );
  }
}

class MobileBottomNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const MobileBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: BottomNavItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  selected: selectedIndex == 0,
                  onTap: () => onChanged(0),
                ),
              ),
              Expanded(
                child: BottomNavItem(
                  icon: Icons.menu_book_rounded,
                  label: 'Lessons',
                  selected: selectedIndex == 1,
                  onTap: () => onChanged(1),
                ),
              ),
              Expanded(
                child: BottomNavItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Chat',
                  selected: selectedIndex == 2,
                  onTap: () => onChanged(2),
                ),
              ),
              Expanded(
                child: BottomNavItem(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  selected: selectedIndex == 3,
                  onTap: () => onChanged(3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;
          if (isDesktop) {
            return Row(
              children: [
                SideNavigation(
                  selectedIndex: selectedIndex,
                  onNavigationChanged: (index) {
                    setState(() => selectedIndex = index);
                  },
                ),
                Expanded(
                  child: DashboardContent(
                    isDesktop: true,
                    selectedIndex: selectedIndex,
                    onNavigationChanged: (index) {
                      setState(() => selectedIndex = index);
                    },
                  ),
                ),
              ],
            );
          }
          return DashboardContent(
            isDesktop: false,
            selectedIndex: selectedIndex,
            onNavigationChanged: (index) {
              setState(() => selectedIndex = index);
            },
          );
        },
      ),
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return const SizedBox.shrink();
          }
          return MobileBottomNavigation(
            selectedIndex: selectedIndex,
            onChanged: (index) {
              setState(() => selectedIndex = index);
            },
          );
        },
      ),
    );
  }
}

void main() {
  runApp(const MaterialApp(home: DashboardPage()));
}

class NavigationItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const NavigationItem({
    super.key,
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        height: 50,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            const SizedBox(width: 18),
            Icon(
              icon,
              size: 22,
              color: selected ? Colors.white : AppColors.secondaryText,
            ),
            const SizedBox(width: 15),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.secondaryText,
                fontSize: 16,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WelcomeSection extends StatelessWidget {
  const WelcomeSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const UserAvatar(size: 82, showBorder: true),
          const SizedBox(height: 16),
          const Text(
            'Welcome back,',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w400,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Username!',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w500,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class UserAvatar extends StatelessWidget {
  final double size;
  final bool showBorder;

  const UserAvatar({super.key, required this.size, this.showBorder = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: showBorder ? const EdgeInsets.all(4) : EdgeInsets.zero,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: showBorder ? Border.all(color: Colors.white, width: 2) : null,
        boxShadow: showBorder
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                ),
              ]
            : null,
      ),
      child: CircleAvatar(
        backgroundColor: const Color(0xFFE5E8F0),
        child: Icon(
          Icons.person_rounded,
          size: size * .46,
          color: AppColors.secondaryText,
        ),
      ),
    );
  }
}

class QuickActions extends StatelessWidget {
  const QuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;

        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: compact ? 1.25 : 1.45,
          children: const [
            QuickActionCard(
              icon: Icons.search_rounded,
              title: 'Find a Tutor',
              iconColor: AppColors.primary,
              iconBackground: Color(0xFFEAF1FF),
            ),
            QuickActionCard(
              icon: Icons.calendar_month_rounded,
              title: 'Schedule',
              iconColor: Color(0xFFB95726),
              iconBackground: Color(0xFFFFEFE5),
            ),
            QuickActionCard(
              icon: Icons.forum_outlined,
              title: 'Messages',
              iconColor: AppColors.secondaryText,
              iconBackground: Color(0xFFF1F3F8),
              showNotification: true,
            ),
            QuickActionCard(
              icon: Icons.menu_book_rounded,
              title: 'Subjects',
              iconColor: Color(0xFF49D68A),
              iconBackground: Color(0xFFEFFFF5),
            ),
          ],
        );
      },
    );
  }
}

class QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color iconColor;
  final Color iconBackground;
  final bool showNotification;

  const QuickActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.iconColor,
    required this.iconBackground,
    this.showNotification = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 27),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (showNotification)
            Positioned(
              right: 14,
              top: 14,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class UpcomingSession extends StatelessWidget {
  const UpcomingSession({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Up Next', action: 'See all'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.15),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'ACCOUNTING 101',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              letterSpacing: .4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        const Text(
                          'Exam Prep Session',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Column(
                      children: [
                        Text(
                          'Today',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '14:00',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Divider(color: Colors.white.withValues(alpha: 0.25), height: 1),
              const SizedBox(height: 15),
              Row(
                children: [
                  const TutorAvatar(initials: 'JM', color: Color(0xFFBFC8D8)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'with Joseph Mungula',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Online Meeting',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 43,
                    height: 43,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.videocam_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class CalendarCard extends StatelessWidget {
  const CalendarCard({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class TutorSection extends StatelessWidget {
  const TutorSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Top Tutors for You', action: 'Explore'),
        const SizedBox(height: 14),
        const TutorCard(
          initials: 'TN',
          name: 'Theophilus Nkhahu',
          subjects: 'Engineering, Mathematics',
          tags: ['BSc Eng', 'Statistics'],
          rating: '5.0',
          online: true,
        ),
        const SizedBox(height: 12),
        const TutorCard(
          initials: 'WS',
          name: 'Welcome Shiruri',
          subjects: 'Actuarial Science',
          tags: ['Mathematics'],
          rating: '4.9',
          online: false,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: Color(0xFFBFC7DB)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            child: const Text(
              'View All Mentors',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }
}

class TutorCard extends StatelessWidget {
  final String initials;
  final String name;
  final String subjects;
  final List<String> tags;
  final String rating;
  final bool online;

  const TutorCard({
    super.key,
    required this.initials,
    required this.name,
    required this.subjects,
    required this.tags,
    required this.rating,
    required this.online,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          TutorAvatar(
            initials: initials,
            color: online ? const Color(0xFFD6DDE8) : const Color(0xFFC8D2D1),
            size: 95,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  online ? 'Available Now' : 'Offline',
                  style: TextStyle(
                    color: online ? const Color(0xFF3AC86D) : AppColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFC400),
                      size: 16,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      rating,
                      style: const TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subjects,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: tags
                      .map(
                        (tag) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F1F7),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                              color: AppColors.secondaryText,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TutorAvatar extends StatelessWidget {
  final String initials;
  final Color color;
  final double size;

  const TutorAvatar({
    super.key,
    required this.initials,
    required this.color,
    this.size = 42,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: AppColors.text,
          fontSize: size * .25,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String action;

  const SectionHeader({super.key, required this.title, required this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          action,
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const BottomNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: selected ? AppColors.primary : AppColors.secondaryText,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected ? AppColors.primary : AppColors.secondaryText,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
