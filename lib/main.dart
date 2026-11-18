import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ics.dart';

void main() => runApp(const MyApp());

const _seed = Color(0xFF2347C5);
const _late = Color(0xFFC62828);
const _soon = Color(0xFFB45D00);
const _ok = Color(0xFF1F7A4D);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Homework',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: _seed,
          useMaterial3: true,
          brightness: Brightness.dark),
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
  String _url = '';
  List<Item> _items = [];
  Set<String> _done = {};
  DateTime? _fetchedAt;
  bool _loading = false;
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
      final stale = _fetchedAt == null ||
          DateTime.now().difference(_fetchedAt!) > const Duration(minutes: 10);
      if (stale) _refresh();
      setState(() {});
    }
  }

  Future<void> _start() async {
    final p = await SharedPreferences.getInstance();
    _prefs = p;
    _url = p.getString('icsUrl') ?? '';
    _done = (p.getStringList('done') ?? []).toSet();
    final cached = p.getString('icsCache');
    final at = p.getInt('fetchedAt');
    if (at != null) _fetchedAt = DateTime.fromMillisecondsSinceEpoch(at);
    if (cached != null) _items = parseIcs(cached);
    setState(() {});
    if (_url.isNotEmpty) await _refresh();
  }

  Future<void> _refresh() async {
    if (_url.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200 || !res.body.contains('BEGIN:VCALENDAR')) {
        _error = res.statusCode == 404
            ? 'The calendar link no longer works. Paste the secret address again in Settings.'
            : 'The calendar link gave an unexpected reply (${res.statusCode}).';
      } else {
        _items = parseIcs(res.body);
        _fetchedAt = DateTime.now();
        await _prefs?.setString('icsCache', res.body);
        await _prefs?.setInt('fetchedAt', _fetchedAt!.millisecondsSinceEpoch);
      }
    } catch (_) {
      _error = "Couldn't reach Google Calendar. Showing the last saved copy.";
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(Item it) async {
    setState(() {
      if (!_done.remove(it.id)) _done.add(it.id);
    });
    await _prefs?.setStringList('done', _done.toList());
  }

  Future<void> _openSettings() async {
    final saved = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => SettingsPage(initial: _url)),
    );
    if (saved != null) {
      _url = saved.trim();
      await _prefs?.setString('icsUrl', _url);
      await _refresh();
    }
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

  List<Item> get _shown =>
      _items.where((it) => !_homeworkOnly || it.isDue).toList();

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'
  ];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _fmtDay(DateTime d) =>
      '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1].substring(0, 3)}';

  String _fmtTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m${d.hour < 12 ? 'am' : 'pm'}';
  }

  String _when(Item it) {
    if (!it.isDue && dayDiff(it.end, it.start) > 0) {
      return '${_fmtDay(it.start)} – ${_fmtDay(it.end)}';
    }
    return it.allDay ? _fmtDay(it.start) : '${_fmtDay(it.start)}, ${_fmtTime(it.start)}';
  }

  // ---------- build ----------
  @override
  Widget build(BuildContext context) {
    if (_prefs != null && _url.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Homework')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Connect your School calendar',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              const Text(
                  'Paste the "Secret address in iCal format" of your School (auto) calendar. '
                  'It stays on this phone.'),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: _openSettings,
                  child: const Text('Paste calendar link')),
            ],
          ),
        ),
      );
    }

    final updated = _fetchedAt == null
        ? 'Not loaded yet'
        : 'Updated ${dayDiff(_fetchedAt!, DateTime.now()) == 0 ? _fmtTime(_fetchedAt!) : _fmtDay(_fetchedAt!)}';

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
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: _loading
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
          IconButton(
              tooltip: 'Settings',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined)),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [TextButton(onPressed: _refresh, child: const Text('Try again'))],
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
                    label: const Text('Homework only'),
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
          _items.isEmpty
              ? "Nothing on your School calendar yet. New homework appears here once teachers post it."
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
    return RefreshIndicator(
      onRefresh: _refresh,
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
    final stripe = !it.isDue ? scheme.primary : (st.color ?? scheme.outlineVariant);
    final meta = [
      if (it.isDue) 'Due ${_when(it)}' else _when(it),
      if (it.subject.isNotEmpty) it.subject,
      if (it.unsure) '(?) date unclear',
    ].join('  ·  ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showDetails(it),
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: stripe, width: 4))),
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
                            fontSize: 13,
                            color: it.unsure ? _soon : scheme.onSurfaceVariant)),
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
                Text([it.isDue ? 'Due ${_when(it)}' : _when(it), if (it.subject.isNotEmpty) it.subject]
                    .join('  ·  ')),
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
                if (it.teams.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => launchUrl(Uri.parse(it.teams),
                        mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open in Teams'),
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
                      : (it.isDue ? _late : (sel ? scheme.onPrimary : scheme.primary));
                  return Container(
                    width: 6, height: 6,
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
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
            _legend(_late, 'Homework due'),
            _legend(scheme.primary, 'Activity'),
            _legend(scheme.outline, 'Done'),
          ],
        ),
        _sectionHeader(_fmtDay(_selected), picked.length, null),
        if (picked.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Nothing on this day.'),
                if (nextUp != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _selected = dayOnly(nextUp!.start);
                      _month = DateTime(_selected.year, _selected.month);
                    }),
                    child: Text('Next up: ${nextUp.title}, ${_fmtDay(nextUp.start)}'),
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

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.initial});
  final String initial;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    final v = _c.text.trim();
    if (!v.startsWith('https://calendar.google.com/') || !v.endsWith('.ics')) {
      setState(() => _err =
          "That doesn't look like a Google Calendar iCal link. It starts with https://calendar.google.com/ and ends in .ics");
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('School calendar link',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
              'In Google Calendar on a computer: Settings → School (auto) → Integrate calendar → '
              '"Secret address in iCal format". Copy it and paste it here. Keep it private: anyone with it can read this calendar.'),
          const SizedBox(height: 16),
          TextField(
            controller: _c,
            minLines: 2,
            maxLines: 4,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'https://calendar.google.com/calendar/ical/.../basic.ics',
              errorText: _err,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(height: 28),
          const Text(
              'Claude checks your Teams chats and class channels every hour from 7am to 10pm and adds what it finds to this calendar. '
              'A (?) means the date in the message was unclear.',
              style: TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
