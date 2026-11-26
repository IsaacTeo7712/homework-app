// All the app's data in one place: your own items, Teams items from the feed,
// ticks, removed items, confirmed dates and reminder choices.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'reminders.dart';

// Set at build time for the iPhone app (kept out of the public code).
// The web version has none built in: it's connected once with a personal link.
const builtInFeedUrl = String.fromEnvironment('FEED_URL');

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December'
];
const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String monthName(int m) => _months[m - 1];
String weekdayName(DateTime d) => _weekdays[d.weekday - 1];
String fmtDay(DateTime d) => '${weekdayName(d).substring(0, 3)} ${d.day} ${monthName(d.month).substring(0, 3)}';
String longDay(DateTime d) => '${weekdayName(d)}, ${d.day} ${monthName(d.month)}';

String fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'am' : 'pm'}';
}

String kindLabel(String k) => k == 'test' ? 'Test' : (k == 'event' ? 'Activity' : 'Homework');

/// The moment something is due. With no time given, the end of that day.
DateTime dueMoment(Item it) =>
    it.hasTime ? it.start : DateTime(it.start.year, it.start.month, it.start.day, 23, 59);

String whenText(Item it) {
  if (!it.isDue && dayDiff(it.end, it.start) > 0) return '${fmtDay(it.start)} – ${fmtDay(it.end)}';
  return it.hasTime ? '${fmtDay(it.start)}, ${fmtTime(it.start)}' : fmtDay(it.start);
}

String timeLeftLabel(Duration left) {
  if (left.isNegative) {
    final late = -left;
    if (late.inHours < 24) return '${late.inHours < 1 ? 1 : late.inHours} hr overdue';
    final days = late.inHours ~/ 24;
    return days == 1 ? '1 day overdue' : '$days days overdue';
  }
  if (left.inMinutes < 60) return '${left.inMinutes} min left';
  if (left.inHours < 24) return '${left.inHours} hr left';
  final days = left.inHours ~/ 24;
  final hrs = left.inHours - days * 24;
  return '$days ${days == 1 ? 'day' : 'days'}${hrs > 0 ? ' $hrs hr' : ''} left';
}

class ReminderSlot {
  const ReminderSlot(this.key, this.label, this.when);
  final String key;
  final String label;
  final DateTime when;
}

const defaultReminders = ['before', 'morning'];

List<ReminderSlot> reminderSlots(Item it) {
  final d = it.start;
  final due = it.isDue ? dueMoment(it) : it.start;
  final list = [
    ReminderSlot('start', 'Nudge to start', DateTime(d.year, d.month, d.day - 2, 16)),
    ReminderSlot('before', 'Day before', DateTime(d.year, d.month, d.day - 1, 19)),
    ReminderSlot('morning', 'Morning of', DateTime(d.year, d.month, d.day, 7)),
  ];
  return list.where((s) => s.when.isBefore(due)).toList();
}

class AppData extends ChangeNotifier {
  SharedPreferences? _p;
  List<Item> mine = [];
  List<Item> teams = [];
  Set<String> done = {};
  Set<String> hidden = {}; // Teams items you removed
  Set<String> confirmed = {}; // Teams items whose unclear date you said is right
  Map<String, List<String>> reminderChoices = {};
  DateTime? syncedAt;
  bool syncing = false;
  String? error;

  String _feedUrl = builtInFeedUrl;
  bool get feedUrlSet => _feedUrl.isNotEmpty;

  Future<void> setFeedUrl(String url) async {
    _feedUrl = url.trim();
    await _p?.setString('feedUrl', _feedUrl);
    teams = [];
    syncedAt = null;
    notifyListeners();
    await sync();
  }

  List<Item> _decode(String? raw, {bool fromTeams = false}) {
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

  Future<void> load() async {
    await Reminders.init();
    final p = await SharedPreferences.getInstance();
    _p = p;
    if (_feedUrl.isEmpty) _feedUrl = p.getString('feedUrl') ?? '';
    if (kIsWeb) {
      final link = Uri.base.queryParameters['feed'];
      if (link != null && link.startsWith('https://')) {
        _feedUrl = link;
        await p.setString('feedUrl', link);
      }
    }
    mine = _decode(p.getString('mine'));
    teams = _decode(p.getString('teamsFeed'), fromTeams: true);
    done = (p.getStringList('done') ?? []).toSet();
    hidden = (p.getStringList('hidden') ?? []).toSet();
    confirmed = (p.getStringList('confirmed') ?? []).toSet();
    try {
      final raw = p.getString('reminders');
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        reminderChoices = m.map((k, v) => MapEntry(k, (v as List).map((e) => e.toString()).toList()));
      }
    } catch (_) {}
    final at = p.getInt('syncedAt');
    if (at != null) syncedAt = DateTime.fromMillisecondsSinceEpoch(at);
    _changed();
    await sync();
  }

  Future<void> sync() async {
    if (_feedUrl.isEmpty || syncing) return;
    syncing = true;
    error = null;
    notifyListeners();
    try {
      final sep = _feedUrl.contains('?') ? '&' : '?';
      final uri = Uri.parse('$_feedUrl${sep}t=${DateTime.now().millisecondsSinceEpoch}');
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        teams = _decode(res.body, fromTeams: true);
        syncedAt = DateTime.now();
        await _p?.setString('teamsFeed', res.body);
        await _p?.setInt('syncedAt', syncedAt!.millisecondsSinceEpoch);
      } else {
        error = "Couldn't get new Teams homework (error ${res.statusCode}).";
      }
    } catch (_) {
      error = "No internet connection. Showing what's saved on this phone.";
    }
    syncing = false;
    _changed();
  }

  /// Called every minute so the time-left bars stay current.
  void tick() => notifyListeners();

  List<Item> get all {
    final list = [...teams.where((t) => !hidden.contains(t.id)), ...mine];
    list.sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  bool isDone(Item it) => done.contains(it.id);
  bool needsCheck(Item it) => it.fromTeams && it.unsure && !confirmed.contains(it.id);

  bool isPast(Item it) {
    final today = DateTime.now();
    return it.isDue ? false : dayDiff(it.end, today) < 0;
  }

  List<Item> get removedTeams {
    final today = DateTime.now();
    return teams
        .where((t) => hidden.contains(t.id) && dayDiff(t.end, today) >= 0)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  List<Item> get foundTeams {
    final today = DateTime.now();
    final list = teams.where((t) => !hidden.contains(t.id) && dayDiff(t.end, today) >= 0).toList();
    list.sort((a, b) {
      final ca = needsCheck(a) ? 0 : 1;
      final cb = needsCheck(b) ? 0 : 1;
      if (ca != cb) return ca - cb;
      return a.start.compareTo(b.start);
    });
    return list;
  }

  int get checkCount => foundTeams.where(needsCheck).length;

  Future<void> toggleDone(Item it) async {
    if (!done.remove(it.id)) done.add(it.id);
    await _p?.setStringList('done', done.toList());
    _changed();
  }

  Future<void> remove(Item it) async {
    if (it.fromTeams) {
      hidden.add(it.id);
    } else {
      mine.removeWhere((m) => m.id == it.id);
    }
    done.remove(it.id);
    await _saveAll();
  }

  Future<void> restore(Item it) async {
    hidden.remove(it.id);
    await _saveAll();
  }

  Future<void> confirm(Item it) async {
    confirmed.add(it.id);
    await _p?.setStringList('confirmed', confirmed.toList());
    _changed();
  }

  /// Saves the editor's result. Editing a Teams item keeps your version and hides the original.
  Future<void> upsert(Item? existing, Item result) async {
    if (existing != null && existing.fromTeams) {
      hidden.add(existing.id);
      if (done.remove(existing.id)) done.add(result.id);
      final r = reminderChoices.remove(existing.id);
      if (r != null) reminderChoices[result.id] = r;
    }
    mine.removeWhere((m) => m.id == result.id);
    mine.add(result);
    await _saveAll();
  }

  List<String> remindersFor(Item it) => reminderChoices[it.id] ?? defaultReminders;

  Future<void> setReminder(Item it, String key, bool on) async {
    final list = [...remindersFor(it)];
    list.remove(key);
    if (on) list.add(key);
    reminderChoices[it.id] = list;
    await _p?.setString('reminders', jsonEncode(reminderChoices));
    _changed();
  }

  Future<void> _saveAll() async {
    await _p?.setString('mine', jsonEncode(mine.map((e) => e.toJson()).toList()));
    await _p?.setStringList('hidden', hidden.toList());
    await _p?.setStringList('done', done.toList());
    await _p?.setString('reminders', jsonEncode(reminderChoices));
    _changed();
  }

  void _changed() {
    notifyListeners();
    _scheduleReminders();
  }

  void _scheduleReminders() {
    if (!Reminders.supported) return;
    final now = DateTime.now();
    final out = <PlannedReminder>[];
    var id = 1;
    for (final it in all) {
      if (done.contains(it.id)) continue;
      final on = remindersFor(it);
      for (final s in reminderSlots(it)) {
        if (!on.contains(s.key) || s.when.isBefore(now)) continue;
        final subject = it.subject.isNotEmpty ? '${it.subject} · ' : '';
        final body = it.isDue ? '${subject}Due ${whenText(it)}' : '$subject${whenText(it)}';
        out.add((id: id++, title: it.title, body: body, when: s.when));
      }
    }
    out.sort((a, b) => a.when.compareTo(b.when));
    Reminders.replaceAll(out);
  }
}
