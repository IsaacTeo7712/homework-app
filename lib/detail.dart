import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'editor.dart';
import 'models.dart';
import 'reminders.dart';
import 'ui.dart';

class DetailPage extends StatelessWidget {
  const DetailPage({super.key, required this.data, required this.item});
  final AppData data;
  final Item item;

  Item? _current() {
    for (final it in data.all) {
      if (it.id == item.id) return it;
    }
    return null;
  }

  Future<void> _edit(BuildContext context, Item it) async {
    final result = await Navigator.of(context).push<Item>(
      MaterialPageRoute(builder: (_) => EditorPage(existing: it)),
    );
    if (result == null) return;
    await data.upsert(it, result);
    if (context.mounted && result.id != it.id) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => DetailPage(data: data, item: result)),
      );
    }
  }

  Future<void> _delete(BuildContext context, Item it) async {
    if (!it.fromTeams) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete this?'),
          content: Text('"${it.title}" will be removed from this phone. This can\'t be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await data.remove(it);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final it = _current();
        if (it == null) {
          return Scaffold(
            appBar: AppBar(backgroundColor: cBg),
            body: const EmptyNote(text: 'This item was removed.'),
          );
        }
        final done = data.isDone(it);
        final check = data.needsCheck(it);
        final slots = reminderSlots(it);
        final on = data.remindersFor(it);
        final now = DateTime.now();
        final dueLine = it.isDue
            ? 'Due ${longDay(it.start)}${it.hasTime ? ' · ${fmtTime(it.start)}' : ''}'
            : (dayDiff(it.end, it.start) > 0
                ? '${longDay(it.start)} – ${longDay(it.end)}'
                : '${longDay(it.start)}${it.hasTime ? ' · ${fmtTime(it.start)}' : ''}');

        return Scaffold(
          appBar: AppBar(
            backgroundColor: cBg,
            surfaceTintColor: cBg,
            actions: [
              IconButton(tooltip: 'Edit', onPressed: () => _edit(context, it), icon: const Icon(Icons.edit_outlined)),
              IconButton(
                tooltip: it.fromTeams ? 'Remove' : 'Delete',
                onPressed: () => _delete(context, it),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Pill(
                  text: it.subject.isNotEmpty ? it.subject : kindLabel(it.kind),
                  bg: cAccentSoft,
                  fg: cAccentDark,
                ),
              ),
              const SizedBox(height: 8),
              Text(it.title,
                  style: const TextStyle(
                      fontSize: 28, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: cInk)),
              const SizedBox(height: 8),
              Text(dueLine,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: it.isDue ? cUrgent : cActivity)),
              if (it.isDue && !done) ...[
                const SizedBox(height: 12),
                TimeBar(due: dueMoment(it)),
              ],
              if (check) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                  decoration: BoxDecoration(color: cWarnSoft, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'The date wasn\'t clear in the Teams message, so this is Claude\'s best guess. Check it in Teams.',
                        style: TextStyle(fontSize: 14, height: 1.4, color: cWarnInk),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(onPressed: () => data.confirm(it), child: const Text('Date is right')),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('REMINDERS',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: cMuted)),
                    if (!Reminders.supported)
                      const Padding(
                        padding: EdgeInsets.only(top: 6, right: 8),
                        child: Text('Reminders only go off in the installed iPhone app, not this version.',
                            style: TextStyle(fontSize: 13, color: cMuted)),
                      ),
                    if (slots.where((s) => s.when.isAfter(now)).isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No reminder times left before this.',
                            style: TextStyle(fontSize: 14, color: cMuted)),
                      ),
                    ...slots.where((s) => s.when.isAfter(now)).map((s) => SwitchListTile.adaptive(
                          contentPadding: const EdgeInsets.only(right: 4),
                          title: Text(s.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                          subtitle: Text('${fmtDay(s.when)}, ${fmtTime(s.when)}',
                              style: const TextStyle(fontSize: 13, color: cMuted)),
                          value: on.contains(s.key) && !done,
                          onChanged: done ? null : (v) => data.setReminder(it, s.key, v),
                        )),
                  ],
                ),
              ),
              if (it.note.isNotEmpty || it.teams.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(it.fromTeams ? 'ORIGINAL MESSAGE' : 'NOTES',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: cMuted)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (it.note.isNotEmpty)
                        SelectableText(it.note, style: const TextStyle(fontSize: 15, height: 1.5, color: cBody)),
                      if (it.teams.isNotEmpty)
                        TextButton.icon(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(44, 44)),
                          onPressed: () =>
                              launchUrl(Uri.parse(it.teams), mode: LaunchMode.externalApplication),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Open in Teams'),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: done ? const Color(0xFFE3E6EC) : cAccent,
                foregroundColor: done ? cInk : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              onPressed: () => data.toggleDone(it),
              child: Text(done ? 'Done — tap to undo' : 'Mark as done'),
            ),
          ),
        );
      },
    );
  }
}
