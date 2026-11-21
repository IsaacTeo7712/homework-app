import 'package:flutter/material.dart';

import 'data.dart';
import 'models.dart';
import 'ui.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, this.existing, this.initialDay});
  final Item? existing;
  final DateTime? initialDay;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final TextEditingController _title = TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _subject = TextEditingController(text: widget.existing?.subject ?? '');
  late final TextEditingController _note = TextEditingController(text: widget.existing?.note ?? '');
  late String _kind = widget.existing?.kind ?? 'due';
  late DateTime _date =
      dayOnly(widget.existing?.start ?? widget.initialDay ?? DateTime.now().add(const Duration(days: 1)));
  late DateTime _endDate = dayOnly(widget.existing?.end ?? _date);
  late TimeOfDay? _time =
      (widget.existing?.hasTime ?? false) ? TimeOfDay.fromDateTime(widget.existing!.start) : null;
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
    final picked =
        await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 23, minute: 59));
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Give it a name, e.g. "Maths worksheet 5"');
      return;
    }
    final start =
        _time == null ? _date : DateTime(_date.year, _date.month, _date.day, _time!.hour, _time!.minute);
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
        backgroundColor: cBg,
        surfaceTintColor: cBg,
        title: Text(editing ? 'Edit' : 'Add'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'due', label: Text('Homework')),
              ButtonSegment(value: 'test', label: Text('Test')),
              ButtonSegment(value: 'event', label: Text('Activity')),
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
              filled: true,
              fillColor: Colors.white,
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
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: Text(_kind == 'event' ? 'Starts' : 'Due date'),
                  subtitle: Text(fmtDay(_date)),
                  onTap: () => _pickDate(),
                ),
                if (_kind == 'event')
                  ListTile(
                    leading: const Icon(Icons.event_available_outlined),
                    title: const Text('Ends'),
                    subtitle: Text(fmtDay(_endDate)),
                    onTap: () => _pickDate(end: true),
                  ),
                ListTile(
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
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              hintText: 'e.g. pages 12-15, submit on Google Classroom',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: cAccent),
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
