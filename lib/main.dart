import 'dart:async';

import 'package:flutter/material.dart';

import 'data.dart';
import 'detail.dart';
import 'editor.dart';
import 'models.dart';
import 'ui.dart';

void main() => runApp(const HomeworkApp());

class HomeworkApp extends StatelessWidget {
  const HomeworkApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: cAccent).copyWith(
      primary: cAccent,
      surface: cBg,
      onSurface: cInk,
    );
    return MaterialApp(
      title: 'Homework',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: cBg,
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: cAccentSoft,
        ),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  final AppData data = AppData();
  int _tab = 0;
  Timer? _ticker;
  DateTime _calendarDay = dayOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    data.load();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => data.tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final stale = data.syncedAt == null ||
          DateTime.now().difference(data.syncedAt!) > const Duration(minutes: 10);
      if (stale) data.sync();
      data.tick();
    }
  }

  void _open(Item it) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DetailPage(data: data, item: it),
    ));
  }

  Future<void> _add() async {
    final result = await Navigator.of(context).push<Item>(MaterialPageRoute(
      builder: (_) => EditorPage(initialDay: _tab == 1 ? _calendarDay : null),
    ));
    if (result != null) await data.upsert(null, result);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        final checks = data.checkCount;
        return Scaffold(
          body: IndexedStack(
            index: _tab,
            children: [
              TodayPage(data: data, onOpen: _open, onGoFound: () => setState(() => _tab = 2)),
              CalendarPage(
                data: data,
                onOpen: _open,
                onDayChanged: (d) => _calendarDay = d,
              ),
              FoundPage(data: data, onOpen: _open),
            ],
          ),
          floatingActionButton: _tab == 2
              ? null
              : FloatingActionButton.extended(
                  onPressed: _add,
                  backgroundColor: cAccent,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.check_box_outlined),
                selectedIcon: Icon(Icons.check_box),
                label: 'Today',
              ),
              const NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Calendar',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: checks > 0,
                  backgroundColor: cUrgent,
                  label: Text('$checks'),
                  child: const Icon(Icons.mark_chat_unread_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: checks > 0,
                  backgroundColor: cUrgent,
                  label: Text('$checks'),
                  child: const Icon(Icons.mark_chat_unread),
                ),
                label: 'Found',
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Today

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.data, required this.onOpen, required this.onGoFound});
  final AppData data;
  final void Function(Item) onOpen;
  final VoidCallback onGoFound;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final groups = <String, List<Item>>{
      'late': [],
      'today': [],
      'tomorrow': [],
      'week': [],
      'later': [],
    };
    final doneItems = <Item>[];
    for (final it in data.all) {
      if (data.isPast(it)) continue;
      if (data.isDone(it)) {
        doneItems.add(it);
        continue;
      }
      if (it.isDue && dueMoment(it).isBefore(now)) {
        groups['late']!.add(it);
        continue;
      }
      final d = it.isDue ? dayDiff(it.start, now) : (dayDiff(it.start, now) < 0 ? 0 : dayDiff(it.start, now));
      if (d <= 0) {
        groups['today']!.add(it);
      } else if (d == 1) {
        groups['tomorrow']!.add(it);
      } else if (d <= 7) {
        groups['week']!.add(it);
      } else {
        groups['later']!.add(it);
      }
    }
    const titles = {
      'late': 'Overdue',
      'today': 'Due today',
      'tomorrow': 'Due tomorrow',
      'week': 'This week',
      'later': 'Later',
    };

    final children = <Widget>[
      PageHeader(
        kicker: longDay(now),
        title: 'Today',
        action: data.feedUrlSet
            ? SyncButton(syncing: data.syncing, onPressed: data.sync)
            : null,
      ),
      if (data.error != null) ErrorNote(text: data.error!, onRetry: data.sync),
      if (data.checkCount > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Material(
            color: cAccentSoft,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onGoFound,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  children: [
                    const Icon(Icons.mark_chat_unread_outlined, size: 20, color: cAccentDark),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        data.checkCount == 1
                            ? '1 date from Teams to check'
                            : '${data.checkCount} dates from Teams to check',
                        style: const TextStyle(color: cAccentDark, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: cAccentDark),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];

    var any = false;
    for (final k in titles.keys) {
      final list = groups[k]!;
      if (list.isEmpty) continue;
      any = true;
      children.add(SectionLabel(
        text: titles[k]!,
        color: (k == 'late' || k == 'today') ? cUrgent : null,
        trailing: '${list.length} left',
      ));
      for (final it in list) {
        children.add(ItemCard(data: data, item: it, onOpen: onOpen));
      }
    }
    if (!any) {
      children.add(EmptyNote(
        text: data.all.isEmpty
            ? 'Nothing here yet. Tap Add to put in homework, or wait for Claude to add deadlines from Teams.'
            : 'Nothing left to do. Nice.',
      ));
    }
    if (doneItems.isNotEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text('Done (${doneItems.length})',
                style: const TextStyle(fontWeight: FontWeight.w600, color: cMuted)),
            children: doneItems.map((it) => ItemCard(data: data, item: it, onOpen: onOpen)).toList(),
          ),
        ),
      ));
    }
    children.add(const SizedBox(height: 96));

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: data.sync,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: children),
      ),
    );
  }
}

// ---------------------------------------------------------------- Calendar

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.data, required this.onOpen, required this.onDayChanged});
  final AppData data;
  final void Function(Item) onOpen;
  final void Function(DateTime) onDayChanged;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = dayOnly(DateTime.now());

  bool _onDay(Item it, DateTime day) {
    if (it.isDue) return dayDiff(it.start, day) == 0;
    return dayDiff(it.start, day) <= 0 && dayDiff(it.end, day) >= 0;
  }

  void _pick(DateTime d) {
    setState(() => _selected = d);
    widget.onDayChanged(d);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final items = data.all;
    final now = DateTime.now();
    final first = DateTime(_month.year, _month.month, 1);
    final daysIn = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday % 7; // Sunday first
    final cells = <Widget>[];
    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var n = 1; n <= daysIn; n++) {
      final day = DateTime(_month.year, _month.month, n);
      final here = items.where((it) => _onDay(it, day)).toList();
      final open = here.where((it) => !data.isDone(it)).toList();
      final hw = open.any((it) => it.isDue);
      final act = open.any((it) => !it.isDue);
      final allDone = here.isNotEmpty && open.isEmpty;
      final sel = dayDiff(day, _selected) == 0;
      final today = dayDiff(day, now) == 0;
      cells.add(Semantics(
        button: true,
        selected: sel,
        label: '${longDay(day)}${here.isEmpty ? '' : ', ${here.length} item${here.length == 1 ? '' : 's'}'}',
        child: ExcludeSemantics(
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _pick(day),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel ? cAccent : null,
                    shape: BoxShape.circle,
                    border: today && !sel ? Border.all(color: cAccent, width: 2) : null,
                  ),
                  child: Text('$n',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: sel || today ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? Colors.white : (today ? cAccent : cInk),
                      )),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 6,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (hw) const Dot(color: cAccent),
                      if (hw && act) const SizedBox(width: 3),
                      if (act) const Dot(color: cActivity, square: true),
                      if (allDone) const Dot(color: cDoneGrey),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
    }

    final picked = items.where((it) => _onDay(it, _selected)).toList();
    final isThisYear = _month.year == now.year;

    return SafeArea(
      bottom: false,
      child: ListView(
        children: [
          PageHeader(
            title: isThisYear ? monthName(_month.month) : '${monthName(_month.month)} ${_month.year}',
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.outlined(
                  tooltip: 'Previous month',
                  onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                  icon: const Icon(Icons.chevron_left),
                ),
                const SizedBox(width: 4),
                IconButton.outlined(
                  tooltip: 'Next month',
                  onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              children: [
                Row(
                  children: const ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                      .map((d) => Expanded(
                            child: Center(
                              child: Text(d,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cMuted)),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 4),
                GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.92,
                  children: cells,
                ),
                const SizedBox(height: 6),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Dot(color: cAccent, size: 8),
                    SizedBox(width: 6),
                    Text('Homework due', style: TextStyle(fontSize: 12, color: cMuted)),
                    SizedBox(width: 16),
                    Dot(color: cActivity, size: 8, square: true),
                    SizedBox(width: 6),
                    Text('School activity', style: TextStyle(fontSize: 12, color: cMuted)),
                  ],
                ),
              ],
            ),
          ),
          SectionLabel(
            text: '${longDay(_selected)}${dayDiff(_selected, now) == 0 ? ' · Today' : ''}',
          ),
          if (picked.isEmpty)
            const EmptyNote(text: 'Nothing due. Enjoy the free day.')
          else
            ...picked.map((it) => ItemCard(data: data, item: it, onOpen: widget.onOpen)),
          const SizedBox(height: 96),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Found

class FoundPage extends StatelessWidget {
  const FoundPage({super.key, required this.data, required this.onOpen});
  final AppData data;
  final void Function(Item) onOpen;

  @override
  Widget build(BuildContext context) {
    final found = data.foundTeams;
    final removed = data.removedTeams;
    final synced = data.syncedAt;
    final fresh = synced != null && DateTime.now().difference(synced) < const Duration(hours: 2);
    final status = !data.feedUrlSet
        ? 'Teams sync is off in this build'
        : synced == null
            ? 'Not checked yet'
            : 'Teams checked ${dayDiff(synced, DateTime.now()) == 0 ? fmtTime(synced) : fmtDay(synced)}';

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: data.sync,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const PageHeader(
              title: 'Found',
              subtitle:
                  'Deadlines Claude finds in your Teams messages are added for you. Anything with an unclear date is marked so you can check it.',
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Dot(color: fresh ? cGood : cActivity, size: 8),
                  const SizedBox(width: 10),
                  Expanded(child: Text(status, style: const TextStyle(fontSize: 13, color: cInk))),
                  if (data.feedUrlSet) SyncButton(syncing: data.syncing, onPressed: data.sync, small: true),
                ],
              ),
            ),
            if (data.error != null) ErrorNote(text: data.error!, onRetry: data.sync),
            if (found.isEmpty)
              const EmptyNote(
                text:
                    'Nothing from Teams yet. New deadlines show up here after Claude\'s hourly check (7am to 10pm).',
              ),
            ...found.map((it) => _FoundCard(data: data, item: it, onOpen: onOpen)),
            if (removed.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: Text('Removed (${removed.length})',
                        style: const TextStyle(fontWeight: FontWeight.w600, color: cMuted)),
                    children: removed
                        .map((it) => ListTile(
                              title: Text(it.title),
                              subtitle: Text(whenText(it)),
                              trailing: TextButton(
                                onPressed: () => data.restore(it),
                                child: const Text('Restore'),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class _FoundCard extends StatelessWidget {
  const _FoundCard({required this.data, required this.item, required this.onOpen});
  final AppData data;
  final Item item;
  final void Function(Item) onOpen;

  @override
  Widget build(BuildContext context) {
    final it = item;
    final check = data.needsCheck(it);
    final label = it.subject.isNotEmpty ? it.subject : kindLabel(it.kind);
    return CardShell(
      onTap: () => onOpen(it),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cMuted)),
              ),
              check
                  ? const Pill(text: 'Check the date', bg: cWarnSoft, fg: cWarnInk)
                  : const Pill(text: 'Date found', bg: cGoodSoft, fg: cGood, icon: Icons.check),
            ],
          ),
          if (it.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('“${it.note}”',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, height: 1.45, color: cBody)),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(color: cSoftPanel, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cInk)),
                const SizedBox(height: 2),
                Text('${it.isDue ? 'Due ' : ''}${whenText(it)}${check ? ' (guessed)' : ''}',
                    style: const TextStyle(fontSize: 13, color: cMuted)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (check)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    onPressed: () => data.remove(it),
                    child: const Text('Remove'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44), backgroundColor: cAccent),
                    onPressed: () => data.confirm(it),
                    child: const Text('Date is right'),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                const Expanded(
                  child: Text('Added with reminders',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cGood)),
                ),
                TextButton(onPressed: () => data.remove(it), child: const Text('Undo')),
              ],
            ),
        ],
      ),
    );
  }
}
