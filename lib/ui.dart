// Shared colours and building blocks, matching the Homework Inbox design.

import 'package:flutter/material.dart';

import 'data.dart';
import 'models.dart';

const cBg = Color(0xFFF6F7F9);
const cInk = Color(0xFF12151C);
const cBody = Color(0xFF2A2F3A);
const cMuted = Color(0xFF5B6270);
const cAccent = Color(0xFF2346C9);
const cAccentDark = Color(0xFF1A3599);
const cAccentSoft = Color(0xFFE8EDFC);
const cUrgent = Color(0xFFB4410B);
const cAmber = Color(0xFF8F5409);
const cActivity = Color(0xFFC26A12);
const cGood = Color(0xFF17643A);
const cGoodSoft = Color(0xFFE3F4EA);
const cWarnSoft = Color(0xFFFDE7D8);
const cWarnInk = Color(0xFF7A2A05);
const cTrack = Color(0xFFE6E9F0);
const cSoftPanel = Color(0xFFF3F5FA);
const cDoneGrey = Color(0xFF9AA1AE);

Color urgencyColor(Duration left) {
  if (left.isNegative || left.inHours < 48) return cUrgent;
  if (left.inHours < 96) return cAmber;
  return cAccent;
}

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, this.kicker, required this.title, this.subtitle, this.action});
  final String? kicker;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (kicker != null)
                      Text(kicker!,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: cMuted)),
                    Semantics(
                      header: true,
                      child: Text(title,
                          style: const TextStyle(
                              fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: cInk)),
                    ),
                  ],
                ),
              ),
              if (action != null) action!,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: const TextStyle(fontSize: 14, height: 1.4, color: cMuted)),
          ],
        ],
      ),
    );
  }
}

class SyncButton extends StatelessWidget {
  const SyncButton({super.key, required this.syncing, required this.onPressed, this.small = false});
  final bool syncing;
  final Future<void> Function() onPressed;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final icon = syncing
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.refresh);
    return small
        ? IconButton(tooltip: 'Check Teams now', onPressed: syncing ? null : onPressed, icon: icon)
        : IconButton.outlined(tooltip: 'Check Teams now', onPressed: syncing ? null : onPressed, icon: icon);
  }
}

class ErrorNote extends StatelessWidget {
  const ErrorNote({super.key, required this.text, required this.onRetry});
  final String text;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(color: cWarnSoft, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: cWarnInk))),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel({super.key, required this.text, this.color, this.trailing});
  final String text;
  final Color? color;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text.toUpperCase(),
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: color ?? cMuted)),
            ),
          ),
          if (trailing != null) Text(trailing!, style: const TextStyle(fontSize: 13, color: cMuted)),
        ],
      ),
    );
  }
}

class EmptyNote extends StatelessWidget {
  const EmptyNote({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4, color: cMuted)),
    );
  }
}

class Dot extends StatelessWidget {
  const Dot({super.key, required this.color, this.size = 6, this.square = false});
  final Color color;
  final double size;
  final bool square;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(size / 6) : null,
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.text, required this.bg, required this.fg, this.icon});
  final String text;
  final Color bg;
  final Color fg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 3)],
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}

class CardShell extends StatelessWidget {
  const CardShell({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Material(
        color: Colors.white,
        elevation: 0.5,
        shadowColor: const Color(0x33000000),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }
}

/// A bar showing how long is left until a deadline. A full bar means a week or more.
class TimeBar extends StatelessWidget {
  const TimeBar({super.key, required this.due});
  final DateTime due;

  @override
  Widget build(BuildContext context) {
    final left = due.difference(DateTime.now());
    final color = urgencyColor(left);
    final frac = left.isNegative ? 1.0 : (left.inMinutes / (7 * 24 * 60)).clamp(0.03, 1.0).toDouble();
    final label = timeLeftLabel(left);
    return Semantics(
      label: left.isNegative ? label : '$label until due',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 5),
            LayoutBuilder(
              builder: (context, box) => Container(
                height: 8,
                width: box.maxWidth,
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(color: cTrack, borderRadius: BorderRadius.circular(4)),
                child: Container(
                  width: box.maxWidth * frac,
                  height: 8,
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ItemCard extends StatelessWidget {
  const ItemCard({super.key, required this.data, required this.item, required this.onOpen});
  final AppData data;
  final Item item;
  final void Function(Item) onOpen;

  @override
  Widget build(BuildContext context) {
    final it = item;
    final done = data.isDone(it);
    final check = data.needsCheck(it);
    final meta = [
      if (it.subject.isNotEmpty) it.subject else kindLabel(it.kind),
      it.isDue ? 'Due ${whenText(it)}' : whenText(it),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Material(
        color: Colors.white,
        elevation: 0.5,
        shadowColor: const Color(0x33000000),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onOpen(it),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  tooltip: done ? 'Mark as not done' : 'Mark as done',
                  onPressed: () => data.toggleDone(it),
                  icon: done
                      ? const Icon(Icons.check_circle, color: cAccent, size: 26)
                      : const Icon(Icons.radio_button_unchecked, color: cDoneGrey, size: 26),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(it.title,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: done ? const Color(0xFF6B7280) : cInk,
                              decoration: done ? TextDecoration.lineThrough : null,
                            )),
                        const SizedBox(height: 4),
                        Text(meta, style: const TextStyle(fontSize: 13, color: cMuted)),
                        if (it.fromTeams) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.chat_bubble_outline, size: 12, color: cMuted),
                              const SizedBox(width: 5),
                              Text(check ? 'From Teams · check the date' : 'From Teams',
                                  style: TextStyle(fontSize: 12, color: check ? cWarnInk : cMuted)),
                            ],
                          ),
                        ],
                        if (it.isDue && !done) ...[
                          const SizedBox(height: 10),
                          TimeBar(due: dueMoment(it)),
                        ],
                      ],
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
