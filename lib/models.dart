// Homework items: ones you add yourself, and ones Claude finds in Teams.

class Item {
  Item({
    required this.id,
    required this.kind,
    required this.title,
    this.subject = '',
    required this.start,
    DateTime? end,
    this.hasTime = false,
    this.unsure = false,
    this.note = '',
    this.teams = '',
    this.fromTeams = false,
  }) : end = end ?? start;

  final String id;
  final String kind; // 'due' | 'test' | 'event'
  final String title;
  final String subject;
  final DateTime start;
  final DateTime end; // last day (inclusive) for multi-day activities
  final bool hasTime;
  final bool unsure;
  final String note;
  final String teams; // link back to the Teams post, or ''
  final bool fromTeams;

  bool get isDue => kind != 'event';

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'subject': subject,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'hasTime': hasTime,
        'unsure': unsure,
        'note': note,
        'teams': teams,
      };

  static Item? fromJson(Map<String, dynamic> j, {bool fromTeams = false}) {
    final start = _parse(j['start'], j['time']);
    if (start == null) return null;
    final end = _parse(j['end'], null) ?? start;
    final kind = (j['kind'] ?? 'due').toString();
    final time = j['time'];
    return Item(
      id: (j['id'] ?? '${j['title']}_${start.toIso8601String()}').toString(),
      kind: const ['due', 'test', 'event'].contains(kind) ? kind : 'due',
      title: (j['title'] ?? 'Untitled').toString(),
      subject: (j['subject'] ?? '').toString(),
      start: start,
      end: end.isBefore(start) ? start : end,
      hasTime: j['hasTime'] == true || (time is String && time.isNotEmpty),
      unsure: j['unsure'] == true,
      note: (j['note'] ?? '').toString(),
      teams: (j['teams'] ?? '').toString(),
      fromTeams: fromTeams,
    );
  }

  // Accepts "2026-12-02", "2026-12-02T14:00:00", or a date plus a separate "HH:MM" time.
  static DateTime? _parse(dynamic date, dynamic time) {
    if (date is! String || date.isEmpty) return null;
    final d = DateTime.tryParse(date);
    if (d == null) return null;
    final local = d.isUtc ? d.toLocal() : d;
    if (time is String && RegExp(r'^\d{1,2}:\d{2}$').hasMatch(time)) {
      final p = time.split(':');
      return DateTime(local.year, local.month, local.day, int.parse(p[0]), int.parse(p[1]));
    }
    return local;
  }
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
int dayDiff(DateTime a, DateTime b) =>
    dayOnly(a).difference(dayOnly(b)).inHours ~/ 24;
