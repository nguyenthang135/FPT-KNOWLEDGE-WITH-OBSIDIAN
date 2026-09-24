import 'package:flutter/material.dart';

enum WorkspaceSection { curriculum, notes, askFlm }

class WorkspaceSidebar extends StatelessWidget {
  final WorkspaceSection selectedSection;
  final ValueChanged<WorkspaceSection> onSelected;
  final double width;

  const WorkspaceSidebar({
    super.key,
    required this.selectedSection,
    required this.onSelected,
    this.width = 240,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        border: Border(left: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        left: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
                child: Text(
                  'Workspace',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _SidebarItem(
                icon: Icons.school_outlined,
                label: 'My Curriculum',
                selected: selectedSection == WorkspaceSection.curriculum,
                onTap: () => onSelected(WorkspaceSection.curriculum),
              ),
              _SidebarItem(
                icon: Icons.note_alt_outlined,
                label: 'My Notes',
                selected: selectedSection == WorkspaceSection.notes,
                onTap: () => onSelected(WorkspaceSection.notes),
              ),
              _SidebarItem(
                icon: Icons.auto_awesome_outlined,
                label: 'Ask FLM',
                selected: selectedSection == WorkspaceSection.askFlm,
                onTap: () => onSelected(WorkspaceSection.askFlm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? colorScheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: selected
                      ? colorScheme.onSecondaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? colorScheme.onSecondaryContainer
                          : colorScheme.onSurface,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
}
