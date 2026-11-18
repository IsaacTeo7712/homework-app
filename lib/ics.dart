// Reads a Google Calendar iCal (.ics) feed into homework items.

class Item {
  Item({
    required this.id,
    required this.title,
    required this.subject,
    required this.isDue,
    required this.unsure,
    required this.allDay,
    required this.start,
    required this.end,
    required this.note,
    required this.teams,
  });

  final String id;
  final String title;
  final String subject;
  final bool isDue; // true = homework deadline, false = activity
  final bool unsure; // title ended in (?)
  final bool allDay;
  final DateTime start;
  final DateTime end; // last day for all-day events (inclusive)
  final String note;
  final String teams; // link back to the Teams post, or ''
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
int dayDiff(DateTime a, DateTime b) =>
    dayOnly(a).difference(dayOnly(b)).inHours ~/ 24;

String _unescape(String s) {
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '\\' && i + 1 < s.length) {
      final n = s[i + 1];
      if (n == 'n' || n == 'N') {
        out.write('\n');
      } else {
        out.write(n);
      }
      i++;
    } else {
      out.write(c);
    }
  }
  return out.toString();
}

DateTime? _parseDate(String? value) {
  if (value == null) return null;
  final s = value.trim();
  if (s.length < 8) return null;
  final y = int.tryParse(s.substring(0, 4));
  final m = int.tryParse(s.substring(4, 6));
  final d = int.tryParse(s.substring(6, 8));
  if (y == null || m == null || d == null) return null;
  if (s.length < 15) return DateTime(y, m, d);
  final h = int.tryParse(s.substring(9, 11)) ?? 0;
  final mi = int.tryParse(s.substring(11, 13)) ?? 0;
  final se = int.tryParse(s.substring(13, 15)) ?? 0;
  if (s.endsWith('Z')) return DateTime.utc(y, m, d, h, mi, se).toLocal();
  // Times with a TZID are Asia/Singapore for this calendar, the same as the phone.
  return DateTime(y, m, d, h, mi, se);
}

Item? _toItem(Map<String, String> ev) {
  if ((ev['STATUS'] ?? '').toUpperCase() == 'CANCELLED') return null;
  final start = _parseDate(ev['DTSTART']);
  if (start == null) return null;
  final allDay = (ev['DTSTART'] ?? '').trim().length < 15;
  var end = _parseDate(ev['DTEND']) ?? start;
  if (allDay && end.isAfter(start)) {
    end = end.subtract(const Duration(days: 1)); // iCal all-day end is exclusive
  }

  var title = _unescape(ev['SUMMARY'] ?? 'Untitled').trim();
  final unsure = RegExp(r'\(\?\)\s*$').hasMatch(title);
  title = title.replaceAll(RegExp(r'\s*\(\?\)\s*$'), '');
  final isDue = RegExp(r'^due\s*:', caseSensitive: false).hasMatch(title);
  var subject = '';
  if (isDue) {
    title = title.replaceFirst(RegExp(r'^due\s*:\s*', caseSensitive: false), '');
    final m = RegExp(r'\(([^()]+)\)\s*$').firstMatch(title);
    if (m != null) {
      subject = m.group(1)!;
      title = title.substring(0, m.start).trim();
    }
  }

  final desc = _unescape(ev['DESCRIPTION'] ?? '');
  final teams = RegExp(r'https://teams\.[^\s)]+').firstMatch(desc)?.group(0) ?? '';
  final note = desc
      .replaceAll(RegExp(r'\n*Teams:\s*https://\S+'), '')
      .replaceAll(RegExp(r'https://teams\.\S+'), '')
      .trim();

  return Item(
    id: ev['UID'] ?? '${title}_${start.toIso8601String()}',
    title: title,
    subject: subject,
    isDue: isDue,
    unsure: unsure,
    allDay: allDay,
    start: start,
    end: end,
    note: note,
    teams: teams,
  );
}

List<Item> parseIcs(String text) {
  final raw = text.replaceAll('\r\n', '\n').split('\n');
  final lines = <String>[];
  for (final l in raw) {
    if ((l.startsWith(' ') || l.startsWith('\t')) && lines.isNotEmpty) {
      lines[lines.length - 1] = lines.last + l.substring(1);
    } else {
      lines.add(l);
    }
  }
  final items = <Item>[];
  Map<String, String>? ev;
  for (final line in lines) {
    if (line == 'BEGIN:VEVENT') {
      ev = {};
      continue;
    }
    if (line == 'END:VEVENT') {
      if (ev != null) {
        final it = _toItem(ev);
        if (it != null) items.add(it);
      }
      ev = null;
      continue;
    }
    if (ev == null) continue;
    final colon = line.indexOf(':');
    if (colon < 0) continue;
    final name = line.substring(0, colon).split(';').first.toUpperCase();
    ev[name] = line.substring(colon + 1);
  }
  items.sort((a, b) => a.start.compareTo(b.start));
  return items;
}
