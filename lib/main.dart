import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';

void main() => runApp(const MyApp());

// Set at build time (kept out of the public code).
const _feedUrl = String.fromEnvironment('FEED_URL');

const _seed = Color(0xFF2347C5);
const _late = Color(0xFFC62828);
const _soon = Color(0xFFB45D00);
const _ok = Color(0xFF1F7A4D);

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December'
];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String fmtDay(DateTime d) =>
    '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1].substring(0, 3)}';

String fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m${d.hour < 12 ? 'am' : 'pm'}';
}

String kindLabel(String k) => k == 'test' ? 'Test' : (k == 'event' ? 'Activity' : 'Homework');

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Homework',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: _seed, useMaterial3: true, brightness: Brightness.dark),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  SharedPreferences? _prefs;
  List<Item> _mine = [];
  List<Item> _teams = [];
  Set<String> _done = {};
  Set<String> _hidden = {}; // Teams items you deleted
  DateTime? _syncedAt;
  bool _syncing = false;
  String? _error;
  int _tab = 0;
  bool _homeworkOnly = false;

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = dayOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final stale = _syncedAt == null ||
          DateTime.now().difference(_syncedAt!) > const Duration(minutes: 10);
      if (stale) _sync();
      setState(() {});
    }
  }

  // ---------- storage ----------
  List<Item> _decodeList(String? raw, {bool fromTeams = false}) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final data = jsonDecode(raw);
      final list = data is Map ? (data['items'] ?? []) : data;
      return (list as List)
          .whereType<Map>()
          .map((m) => Item.fromJson(Map<String, dynamic>.from(m), fromTeams: fromTeams))
          .whereType<Item>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _start() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    _mine = _decodeList(p.getString('mine'));
    _teams = _decodeList(p.getString('teamsFeed'), fromTeams: true);
    _done = (p.getStringList('done') ?? []).toSet();
    _hidden = (p.getStringList('hidden') ?? []).toSet();
    final at = p.getInt('syncedAt');
    if (at != null) _syncedAt = DateTime.fromMillisecondsSinceEpoch(at);
    setState(() {});
    await _sync();
  }

  Future<void> _saveMine() async =>
      _prefs?.setString('mine', jsonEncode(_mine.map((e) => e.toJson()).toList()));

  Future<void> _sync() async {
    if (_feedUrl.isEmpty || _syncing) return;
    setState(() {
      _syncing = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('$_feedUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final items = _decodeList(res.body, fromTeams: true);
        _teams = items;
        _syncedAt = DateTime.now();
        await _prefs?.setString('teamsFeed', res.body);
        await _prefs?.setInt('syncedAt', _syncedAt!.millisecondsSinceEpoch);
      } else {
        _error = "Couldn't get new Teams homework (error ${res.statusCode}).";
      }
    } catch (_) {
      _error = "No internet connection. Showing what's saved on this device.";
    }
    if (mounted) setState(() => _syncing = false);
  }

  List<Item> get _all {
    final list = [
      ..._teams.where((t) => !_hidden.contains(t.id)),
      ..._mine,
    ];
    list.sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  List<Item> get _shown => _all.where((it) => !_homeworkOnly || it.isDue).toList();

  Future<void> _toggle(Item it) async {
    setState(() {
      if (!_done.remove(it.id)) _done.add(it.id);
    });
    await _prefs?.setStringList('done', _done.toList());
  }

  Future<void> _delete(Item it) async {
    setState(() {
      if (it.fromTeams) {
        _hidden.add(it.id);
      } else {
        _mine.removeWhere((m) => m.id == it.id);
      }
      _done.remove(it.id);
    });
    await _prefs?.setStringList('hidden', _hidden.toList());
    await _prefs?.setStringList('done', _done.toList());
    await _saveMine();
  }

  Future<void> _openEditor({Item? existing, DateTime? onDay}) async {
    final result = await Navigator.of(context).push<Item>(
      MaterialPageRoute(builder: (_) => EditorPage(existing: existing, initialDay: onDay)),
    );
    if (result == null) return;
    setState(() {
      if (existing != null && existing.fromTeams) {
        // Editing a Teams item keeps your version and hides the original.
        _hidden.add(existing.id);
        if (_done.remove(existing.id)) _done.add(result.id);
      }
      _mine.removeWhere((m) => m.id == result.id);
      _mine.add(result);
    });
    await _prefs?.setStringList('hidden', _hidden.toList());
    await _prefs?.setStringList('done', _done.toList());
    await _saveMine();
  }

  // ---------- helpers ----------
  ({String label, Color? color, String group}) _status(Item it) {
    final today = DateTime.now();
    if (!it.isDue) {
      if (dayDiff(it.end, today) < 0) return (label: 'Ended', color: null, group: 'past');
      if (dayDiff(it.start, today) <= 0) return (label: 'On now', color: _ok, group: 'today');
    }
    final d = dayDiff(it.start, today);
    if (d < 0) return (label: d == -1 ? '1 day late' : '${-d} days late', color: _late, group: 'late');
    if (d == 0) return (label: 'Today', color: _soon, group: 'today');
    if (d == 1) return (label: 'Tomorrow', color: _soon, group: 'week');
    if (d <= 7) return (label: 'In $d days', color: d <= 3 ? _soon : null, group: 'week');
    return (label: 'In $d days', color: null, group: 'later');
  }

  bool _onDay(Item it, DateTime day) {
    if (it.isDue) return dayDiff(it.start, day) == 0;
    return dayDiff(it.start, day) <= 0 && dayDiff(it.end, day) >= 0;
  }

  String _when(Item it) {
    if (!it.isDue && dayDiff(it.end, it.start) > 0) {
      return '${fmtDay(it.start)} – ${fmtDay(it.end)}';
    }
    return it.hasTime ? '${fmtDay(it.start)}, ${fmtTime(it.start)}' : fmtDay(it.start);
  }

  Color _kindColor(Item it, ColorScheme scheme) =>
      it.kind == 'event' ? scheme.primary : (it.kind == 'test' ? _soon : _late);

  // ---------- build ----------
  @override
  Widget build(BuildContext context) {
    final updated = _feedUrl.isEmpty
        ? 'Teams sync off'
        : (_syncedAt == null
            ? 'Not synced yet'
            : 'Synced ${dayDiff(_syncedAt!, DateTime.now()) == 0 ? fmtTime(_syncedAt!) : fmtDay(_syncedAt!)}');

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Homework', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(updated, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          if (_feedUrl.isNotEmpty)
            IconButton(
              tooltip: 'Get new Teams homework',
              onPressed: _syncing ? null : _sync,
              icon: _syncing
                  ? const SizedBox(
                      width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(onDay: _tab == 1 ? _selected : null),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [TextButton(onPressed: _sync, child: const Text('Try again'))],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                ChoiceChip(
                    label: const Text('All'),
                    selected: !_homeworkOnly,
                    onSelected: (_) => setState(() => _homeworkOnly = false)),
                const SizedBox(width: 8),
                ChoiceChip(
                    label: const Text('Homework & tests'),
                    selected: _homeworkOnly,
                    onSelected: (_) => setState(() => _homeworkOnly = true)),
              ],
            ),
          ),
          Expanded(child: _tab == 0 ? _buildList() : _buildCalendar()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.checklist), label: 'List'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Calendar'),
        ],
      ),
    );
  }

  Widget _buildList() {
    final groups = <String, List<Item>>{'late': [], 'today': [], 'week': [], 'later': []};
    final doneItems = <Item>[];
    for (final it in _shown) {
      final st = _status(it);
      if (st.group == 'past') continue;
      if (_done.contains(it.id)) {
        doneItems.add(it);
      } else {
        groups[st.group]!.add(it);
      }
    }
    const titles = {'late': 'Overdue', 'today': 'Today', 'week': 'Next 7 days', 'later': 'Later'};
    final children = <Widget>[];
    for (final k in titles.keys) {
      final list = groups[k]!;
      if (list.isEmpty) continue;
      children.add(_sectionHeader(titles[k]!, list.length, k == 'late' ? _late : null));
      children.addAll(list.map(_card));
    }
    if (children.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _all.isEmpty
              ? 'Nothing here yet. Tap Add to put in homework, or wait for Claude to add deadlines from Teams.'
              : 'Nothing left to do. Nice.',
          textAlign: TextAlign.center,
        ),
      ));
    }
    if (doneItems.isNotEmpty) {
      children.add(ExpansionTile(
        title: Text('Done (${doneItems.length})'),
        children: doneItems.map(_card).toList(),
      ));
    }
    children.add(const SizedBox(height: 80));
    return RefreshIndicator(
      onRefresh: _sync,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: children,
      ),
    );
  }

  Widget _sectionHeader(String text, int n, Color? color) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text('${text.toUpperCase()}  ·  $n',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: color ?? Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _card(Item it) {
    final st = _status(it);
    final done = _done.contains(it.id);
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      if (it.isDue) 'Due ${_when(it)}' else _when(it),
      if (it.subject.isNotEmpty) it.subject,
      if (it.fromTeams) 'from Teams',
      if (it.unsure) '(?) date unclear',
    ].join('  ·  ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetails(it),
        child: Container(
          decoration: BoxDecoration(
              border: Border(left: BorderSide(color: _kindColor(it, scheme), width: 4))),
          padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
          child: Row(
            children: [
              Checkbox(value: done, onChanged: (_) => _toggle(it)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.title,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration: done ? TextDecoration.lineThrough : null)),
                    const SizedBox(height: 2),
                    Text(meta,
                        style: TextStyle(
                            fontSize: 13, color: it.unsure ? _soon : scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (done ? _ok : (st.color ?? scheme.primary)).withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(done ? 'Done' : st.label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: done ? _ok : (st.color ?? scheme.primary))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(Item it) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.title, style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text([
                  kindLabel(it.kind),
                  it.isDue ? 'Due ${_when(it)}' : _when(it),
                  if (it.subject.isNotEmpty) it.subject,
                ].join('  ·  ')),
                if (it.fromTeams)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Added by Claude from a Teams message.',
                        style: TextStyle(fontSize: 13)),
                  ),
                if (it.unsure)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('The date in the message was unclear. Check it in Teams.',
                        style: TextStyle(color: _soon, fontWeight: FontWeight.w600)),
                  ),
                if (it.note.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  SelectableText(it.note),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (it.teams.isNotEmpty)
                      FilledButton.icon(
                        onPressed: () => launchUrl(Uri.parse(it.teams),
                            mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open in Teams'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _openEditor(existing: it);
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _delete(it);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    final scheme = Theme.of(context).colorScheme;
    final items = _shown;
    final first = DateTime(_month.year, _month.month, 1);
    final daysIn = DateTime(_month.year, _month.month + 1, 0).day;
    final lead = first.weekday - 1; // Monday first
    final cells = <Widget>[];
    for (var i = 0; i < lead; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysIn; d++) {
      final day = DateTime(_month.year, _month.month, d);
      final here = items.where((it) => _onDay(it, day)).toList();
      final sel = dayDiff(day, _selected) == 0;
      final today = dayDiff(day, DateTime.now()) == 0;
      cells.add(InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _selected = day),
        child: Container(
          decoration: BoxDecoration(
            color: sel ? scheme.primary : (here.isNotEmpty ? scheme.surfaceContainerHighest : null),
            borderRadius: BorderRadius.circular(10),
            border: today && !sel ? Border.all(color: scheme.primary, width: 1.5) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$d',
                  style: TextStyle(
                      fontWeight: today ? FontWeight.w800 : FontWeight.w500,
                      color: sel ? scheme.onPrimary : null)),
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: here.take(3).map((it) {
                  final c = _done.contains(it.id)
                      ? scheme.outline
                      : (it.kind == 'event' && sel ? scheme.onPrimary : _kindColor(it, scheme));
                  return Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ));
    }

    final picked = items.where((it) => _onDay(it, _selected)).toList();
    Item? nextUp;
    for (final it in items) {
      if (_done.contains(it.id)) continue;
      if (dayDiff(it.isDue ? it.start : it.end, DateTime.now()) >= 0) {
        nextUp = it;
        break;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${_months[_month.month - 1]} ${_month.year}',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            IconButton(
                tooltip: 'Previous month',
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                icon: const Icon(Icons.chevron_left)),
            TextButton(
                onPressed: () => setState(() {
                      _selected = dayOnly(DateTime.now());
                      _month = DateTime(_selected.year, _selected.month);
                    }),
                child: const Text('Today')),
            IconButton(
                tooltip: 'Next month',
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                icon: const Icon(Icons.chevron_right)),
          ],
        ),
        Row(
          children: _days
              .map((d) => Expanded(
                    child: Center(
                      child: Text(d.toUpperCase(),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant)),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          children: cells,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          children: [
            _legend(_late, 'Homework'),
            _legend(_soon, 'Test'),
            _legend(scheme.primary, 'Activity'),
            _legend(scheme.outline, 'Done'),
          ],
        ),
        _sectionHeader(fmtDay(_selected), picked.length, null),
        if (picked.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nothing on this day. Tap Add to put something here.'),
                if (nextUp != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _selected = dayOnly(nextUp!.start);
                      _month = DateTime(_selected.year, _selected.month);
                    }),
                    child: Text('Next up: ${nextUp.title}, ${fmtDay(nextUp.start)}'),
                  ),
              ],
            ),
          )
        else
          ...picked.map(_card),
      ],
    );
  }

  Widget _legend(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, this.existing, this.initialDay});
  final Item? existing;
  final DateTime? initialDay;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _subject =
      TextEditingController(text: widget.existing?.subject ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.existing?.note ?? '');
  late String _kind = widget.existing?.kind ?? 'due';
  late DateTime _date = dayOnly(widget.existing?.start ??
      widget.initialDay ??
      DateTime.now().add(const Duration(days: 1)));
  late DateTime _endDate = dayOnly(widget.existing?.end ?? _date);
  late TimeOfDay? _time = (widget.existing?.hasTime ?? false)
      ? TimeOfDay.fromDateTime(widget.existing!.start)
      : null;
  String? _titleError;

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate({bool end = false}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: end ? _endDate : _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null) return;
    setState(() {
      if (end) {
        _endDate = picked.isBefore(_date) ? _date : picked;
      } else {
        _date = picked;
        if (_endDate.isBefore(_date)) _endDate = _date;
      }
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
        context: context, initialTime: _time ?? const TimeOfDay(hour: 23, minute: 59));
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Give it a name, e.g. "Maths worksheet 5"');
      return;
    }
    final start = _time == null
        ? _date
        : DateTime(_date.year, _date.month, _date.day, _time!.hour, _time!.minute);
    final ex = widget.existing;
    final keepId = ex != null && !ex.fromTeams;
    Navigator.of(context).pop(Item(
      id: keepId ? ex!.id : 'me-${DateTime.now().microsecondsSinceEpoch}',
      kind: _kind,
      title: title,
      subject: _subject.text.trim(),
      start: start,
      end: _kind == 'event' ? _endDate : start,
      hasTime: _time != null,
      unsure: false,
      note: _note.text.trim(),
      teams: ex?.teams ?? '',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Edit' : 'Add homework'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'due', label: Text('Homework'), icon: Icon(Icons.assignment_outlined)),
              ButtonSegment(value: 'test', label: Text('Test'), icon: Icon(Icons.quiz_outlined)),
              ButtonSegment(value: 'event', label: Text('Activity'), icon: Icon(Icons.event_outlined)),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'What is it?',
              hintText: 'e.g. Physics optics worksheet',
              border: const OutlineInputBorder(),
              errorText: _titleError,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _subject,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Subject (optional)',
              hintText: 'e.g. Physics',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today_outlined),
            title: Text(_kind == 'event' ? 'Starts' : 'Due date'),
            subtitle: Text(fmtDay(_date)),
            onTap: () => _pickDate(),
          ),
          if (_kind == 'event')
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('Ends'),
              subtitle: Text(fmtDay(_endDate)),
              onTap: () => _pickDate(end: true),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('Time (optional)'),
            subtitle: Text(_time == null ? 'No time' : _time!.format(context)),
            onTap: _pickTime,
            trailing: _time == null
                ? null
                : IconButton(
                    tooltip: 'Remove time',
                    onPressed: () => setState(() => _time = null),
                    icon: const Icon(Icons.close)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              hintText: 'e.g. pages 12-15, submit on Google Classroom',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
