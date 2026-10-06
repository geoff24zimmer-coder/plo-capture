import 'package:flutter/material.dart';

const homeEmerald = Color(0xFF10B981);
const homeGold = Color(0xFFC9A536);
const homeBlue = Color(0xFF378ADD);
const homeViolet = Color(0xFF8B7CF6);

/// A home-screen feature button: accent icon chip, title, one-line subtitle,
/// chevron. [filled] makes it the primary call to action (solid accent).
class HomeAction extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final bool filled;
  final VoidCallback onTap;
  const HomeAction({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : Colors.white.withValues(alpha: 0.92);
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: filled ? accent : const Color(0xFF16181B),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: filled
                    ? Colors.white.withValues(alpha: 0.18)
                    : accent.withValues(alpha: 0.45),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? Colors.white.withValues(alpha: 0.18)
                        : accent.withValues(alpha: 0.16),
                  ),
                  child: Icon(icon,
                      size: 24, color: filled ? Colors.white : accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: fg)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5,
                              color:
                                  fg.withValues(alpha: filled ? 0.85 : 0.6))),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    color: fg.withValues(alpha: filled ? 0.9 : 0.45)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Log played hands" sub-menu: cash game or tournament. Returns `cash`,
/// `mtt`, or null if dismissed.
Future<String?> pickGameType(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF0E100F),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('What are you playing?',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              HomeAction(
                title: 'Cash game',
                subtitle: 'Blinds & straddles, in dollars',
                icon: Icons.payments_outlined,
                accent: homeEmerald,
                filled: true,
                onTap: () => Navigator.pop(ctx, 'cash'),
              ),
              const SizedBox(height: 12),
              HomeAction(
                title: 'Tournament',
                subtitle: 'Levels, antes & chip stacks',
                icon: Icons.emoji_events_outlined,
                accent: homeGold,
                filled: true,
                onTap: () => Navigator.pop(ctx, 'mtt'),
              ),
            ],
          ),
        ),
      ),
    );
