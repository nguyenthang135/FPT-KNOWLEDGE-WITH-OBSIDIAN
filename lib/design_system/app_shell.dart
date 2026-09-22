import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'fpt_logo.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.child,
    this.title,
    this.actions = const [],
    this.selectedIndex = 1,
    this.onLogout,
    this.isLoggingOut = false,
  });
  final Widget child;
  final String? title;
  final List<Widget> actions;
  final int selectedIndex;
  final VoidCallback? onLogout;
  final bool isLoggingOut;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _collapsed = false;
  static const _items = <(IconData, String)>[
    (Icons.dashboard_outlined, 'Overview'),
    (Icons.school_outlined, 'Curriculum'),
    (Icons.hub_outlined, 'Knowledge'),
    (Icons.search, 'Search'),
    (Icons.note_alt_outlined, 'Notes'),
    (Icons.auto_awesome_mosaic_outlined, 'Obsidian'),
    (Icons.sync_outlined, 'Sync'),
    (Icons.settings_outlined, 'Settings'),
  ];
  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    if (!desktop) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title ?? 'FPT Knowledge'),
          actions: widget.actions,
        ),
        drawer: Drawer(
          backgroundColor: AppColors.surface,
          child: SafeArea(child: _nav(false)),
        ),
        body: widget.child,
      );
    }
    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: _collapsed ? 76 : 236,
            color: AppColors.surface,
            child: SafeArea(child: _nav(_collapsed)),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: 64,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        if (widget.title != null)
                          Text(
                            widget.title!,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        const Spacer(),
                        ...widget.actions,
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _nav(bool collapsed) => Column(
    children: [
      SizedBox(
        height: 64,
        child: collapsed
            ? Center(
                child: IconButton(
                  tooltip: 'Expand sidebar',
                  onPressed: () => setState(() => _collapsed = !_collapsed),
                  icon: const Icon(
                    Icons.keyboard_double_arrow_right,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  splashRadius: 20,
                ),
              )
            : Padding(
                padding: const EdgeInsets.only(left: 18, right: 8),
                child: Row(
                  children: [
                    const Expanded(child: FptBrand(logoHeight: 30)),
                    IconButton(
                      tooltip: 'Collapse sidebar',
                      onPressed: () => setState(() => _collapsed = !_collapsed),
                      icon: const Icon(
                        Icons.keyboard_double_arrow_left,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      splashRadius: 20,
                    ),
                  ],
                ),
              ),
      ),
      const Divider(height: 1),
      const SizedBox(height: 12),
      for (var i = 0; i < _items.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Tooltip(
            message: collapsed ? _items[i].$2 : '',
            child: Material(
              color: i == widget.selectedIndex
                  ? AppColors.hover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {},
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 54,
                        child: Icon(
                          _items[i].$1,
                          color: i == widget.selectedIndex
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                      if (!collapsed)
                        Expanded(
                          child: Text(
                            _items[i].$2,
                            style: TextStyle(
                              color: i == widget.selectedIndex
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontWeight: i == widget.selectedIndex
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      const Spacer(),
      if (widget.onLogout != null || widget.isLoggingOut) ...[
        const Divider(height: 1),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          child: Tooltip(
            message: collapsed ? 'Logout' : '',
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: widget.isLoggingOut ? null : widget.onLogout,
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 54,
                        child: widget.isLoggingOut
                            ? const Center(
                                child: SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.logout,
                                color: AppColors.textSecondary,
                              ),
                      ),
                      if (!collapsed)
                        const Expanded(
                          child: Text(
                            'Logout',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
      const SizedBox(height: 12),
    ],
  );
}
