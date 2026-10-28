import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exception.dart';
import '../../core/auth/session.dart';
import '../../core/download.dart';
import '../../core/csv_parse.dart';
import '../../core/json.dart';
import '../../core/ui/controls.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/overlays.dart';
import '../../core/ui/primitives.dart';
import '../users/users_screen.dart';
import 'academies_screen.dart';

const _basicHeader = 'name,mobile,email,course,batch';
const _basicTemplate = '$_basicHeader\nAnanya Rao,9845012345,ananya.rao@example.in,Bharatnatyam,Batch A';
const _basicSample = '$_basicTemplate\nKabir Shah,9900011122,kabir.shah@example.in,Guitar Beginner,Batch B\nMeera Pillai,98450,meera@example.in,Kathak,Batch A\nDev Menon,9811122233,not-an-email,Hip-hop,Batch C';

/// Every column of the full template, in order. A * marks the ones the file must fill.
const _fullHeader = 'name,mobile,email,gender,date_of_birth,blood_group,alt_phone,guardian_name,guardian_mobile,address_line1,address_line2,landmark,city,district,state,country,pin_code,course,batch,joining_date';
const _fullTemplate = '$_fullHeader\nAnanya Rao,9845012345,ananya.rao@example.in,Female,14-05-2010,O+,9845012399,Suresh Rao,9845012346,12 MG Road,Indiranagar,Near the park,Bengaluru,Bengaluru Urban,Karnataka,India,560038,Bharatnatyam,Batch A,01-06-2026';
const _fullSample = '$_fullTemplate\nKabir Shah,99000,kabir.shah@example,Boy,31-02-2012,Z+,,,,,,,Mysuru,,Karnataka,India,05700,Guitar Begginer,Batch Z,tomorrow\nMeera Pillai,9811122233,meera@example.in,Female,03-03-1990,B+,,,,,,,Chennai,,Tamil Nadu,India,600001,Kathak,Batch A,15-01-2026';

const _fullRules = [
  ('name *', 'Letters and spaces only, 2 to 60 characters. Example: Ananya Rao.'),
  ('mobile *', '10 digits starting with 6, 7, 8 or 9 (+91 is fine). Must not already be on Owleo or repeat in the file.'),
  ('email', 'name@example.com. Optional, but must be unique if given.'),
  ('gender', 'Male, Female or Other.'),
  ('date_of_birth', 'DD-MM-YYYY, a real date, age 2 to 100. Example: 14-05-2010.'),
  ('blood_group', 'A+, A-, B+, B-, AB+, AB-, O+ or O-.'),
  ('alt_phone', 'A valid phone number.'),
  ('guardian_name, guardian_mobile', 'Required when the student is under 18 (needs the date of birth).'),
  ('address_line1, address_line2, landmark', 'Up to 160, 160 and 80 characters.'),
  ('city, district, state, country', 'Letters and spaces only, up to 100 characters.'),
  ('pin_code', 'Six digits not starting with 0 (India). Other countries: 3 to 10 letters or digits.'),
  ('course *', 'Exactly a course of this academy (capitals do not matter). Use "Course and batch list".'),
  ('batch *', 'One of that course\'s batches. Left empty only when the course has no batches.'),
  ('joining_date', 'DD-MM-YYYY, not in the future. Empty means today.'),
];

Future<void> showBulkImport(BuildContext context, List<Map<String, dynamic>> academies) => showHqModal<void>(context, width: 640, builder: (_) => _BulkImport(academies: academies));

class _BulkImport extends ConsumerStatefulWidget {
  const _BulkImport({required this.academies});
  final List<Map<String, dynamic>> academies;

  @override
  ConsumerState<_BulkImport> createState() => _BulkImportState();
}

class _BulkImportState extends ConsumerState<_BulkImport> {
  String? _academy;
  String _template = 'full';
  List<String> _headers = const [];
  List<List<String>> _cells = const [];
  Map<String, dynamic>? _result;
  String? _fatal;
  bool _busy = false, _rules = false;

  String get _file => _template == 'full' ? 'owleo-student-import-full-template.csv' : 'owleo-student-import-template.csv';

  static String _norm(String h) => h.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');

  Future<void> _check(String text) async {
    final rows = parseCsv(text);
    if (_academy == null) return setState(() => _fatal = 'Choose the academy first.');
    if (rows.length < 2) {
      return setState(() {
        _fatal = 'The file has no student rows. Use the template.';
        _result = null;
      });
    }
    final head = rows.first.map((e) => e.trim()).toList();
    final norm = head.map(_norm).toList();
    final needs = _template == 'full' ? ['name', 'mobile', 'course'] : ['name', 'mobile'];
    // The same other names the server accepts, for the columns that decide whether the file is usable at all.
    const alias = {'student_name': 'name', 'full_name': 'name', 'phone': 'mobile', 'mobile_number': 'mobile', 'phone_number': 'mobile'};
    final have = norm.map((h) => alias[h] ?? h).toSet();
    final missing = needs.where((k) => !have.contains(k)).toList();
    if (missing.isNotEmpty) {
      return setState(() {
        _fatal = 'The file is missing the ${missing.join(', ')} column${missing.length == 1 ? '' : 's'}. Download the template and copy your students into it.';
        _result = null;
      });
    }
    final cells = [for (final r in rows.skip(1)) [for (var i = 0; i < head.length; i++) i < r.length ? r[i] : '']];
    final body = [for (final r in cells) {for (var i = 0; i < head.length; i++) head[i]: r[i]}];
    setState(() {
      _busy = true;
      _fatal = null;
    });
    try {
      final r = await ref.read(dioClientProvider).postMap('/admin/hq/academies/$_academy/import', body: {'rows': body, 'commit': false, 'template': _template});
      setState(() {
        _headers = head;
        _cells = cells;
        _result = r;
        _busy = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _fatal = e.message;
        _result = null;
      });
    }
  }

  Future<void> _pick() async {
    final t = await pickTextFile();
    if (t != null) await _check(t);
  }

  /// Your file again, with a what_to_correct column on every row that failed. Fix the cells it names and upload the
  /// whole file again: the extra row and what_to_correct columns are ignored.
  void _errorFile() {
    final bad = _result?.maps('bad') ?? const <Map<String, dynamic>>[];
    final notes = <int, String>{
      for (final b in bad)
        b.integer('row'): [for (final i in b.maps('issues')) '${i.str('column')}: ${i.str('problem')}${i.str('value').isEmpty ? '' : ' (you wrote "${i.str('value')}")'}. ${i.str('fix')}'].join('  |  '),
    };
    final out = <List<Object?>>[
      ['row', ..._headers, 'what_to_correct'],
      for (var i = 0; i < _cells.length; i++) [i + 2, ..._cells[i], notes[i + 2] ?? ''],
    ];
    downloadText('owleo-import-errors-${DateTime.now().toIso8601String().substring(0, 10)}.csv', csvText(out));
    showToast(context, 'Fix the rows marked in what_to_correct, then upload the file again');
  }

  Future<void> _reference() async {
    if (_academy == null) return setState(() => _fatal = 'Choose the academy first.');
    try {
      final r = await ref.read(dioClientProvider).getList('/admin/hq/academies/$_academy/import/reference');
      final rows = <List<Object?>>[
        ['course', 'batch'],
        for (final c in r)
          if (c.strings('batches').isEmpty) [c.str('course'), ''] else for (final b in c.strings('batches')) [c.str('course'), b],
      ];
      downloadText('owleo-courses-and-batches.csv', csvText(rows));
    } on ApiException catch (e) {
      if (mounted) setState(() => _fatal = e.message);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final body = [for (final r in _cells) {for (var i = 0; i < _headers.length; i++) _headers[i]: r[i]}];
      final r = await ref.read(dioClientProvider).postMap('/admin/hq/academies/$_academy/import', body: {'rows': body, 'commit': true, 'template': _template});
      ref.invalidate(academiesProvider);
      ref.invalidate(usersProvider);
      final creds = r.maps('credentials');
      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, 'Imported ${r.integer('created')} students');
      if (creds.isNotEmpty) {
        downloadText('owleo-new-student-logins-${DateTime.now().toIso8601String().substring(0, 10)}.csv', csvText([['name', 'username', 'temporary password'], for (final c in creds) [c.str('name'), c.str('username'), c.str('password')]]));
      }
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _fatal = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final total = r?.integer('total') ?? 0;
    final ready = r?.integer('ready') ?? 0;
    final bad = r?.maps('bad') ?? const <Map<String, dynamic>>[];
    return ModalFrame(
      title: 'Bulk import',
      sub: 'Add many students to an academy from one file',
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        if (r != null) HqButton(bad.isEmpty ? 'Import $ready ${ready == 1 ? 'student' : 'students'}' : 'Fix ${bad.length} ${bad.length == 1 ? 'row' : 'rows'} first', kind: BtnKind.primary, busy: _busy, onPressed: bad.isEmpty && ready > 0 ? _import : null),
      ],
      children: [
        HqSelect<String>(label: 'Academy', value: _academy, hint: 'Choose an academy', options: [for (final a in widget.academies) SelectOption(a.str('id'), a.str('name'))], onChanged: (v) => setState(() {
              _academy = v;
              _result = null;
            })),
        Text('Template', style: HqText.label),
        const SizedBox(height: 6),
        SegControl<String>(
          expand: true,
          items: const [('full', 'Full details'), ('basic', 'Basic (5 columns)')],
          value: _template,
          onChanged: (v) => setState(() {
            _template = v;
            _result = null;
            _fatal = null;
          }),
        ),
        const SizedBox(height: 6),
        Text(
          _template == 'full'
              ? 'Every detail is checked: mobile, email, date of birth, blood group, address, PIN code, guardian, and the course and batch must exist in the academy.'
              : 'Name and mobile are required. Course and batch are optional.',
          style: HqText.sub,
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          HqButton('Download template', icon: 'dl', small: true, onPressed: () => downloadText(_file, _template == 'full' ? _fullTemplate : _basicTemplate)),
          if (_template == 'full') HqButton('Course and batch list', icon: 'dl', small: true, onPressed: _reference),
          HqButton('Choose file', icon: 'ul', small: true, kind: BtnKind.primary, onPressed: _pick),
          HqButton('Try a sample file', small: true, onPressed: () => _check(_template == 'full' ? _fullSample : _basicSample)),
          if (_template == 'full') HqButton(_rules ? 'Hide column rules' : 'Column rules', small: true, onPressed: () => setState(() => _rules = !_rules)),
        ]),
        if (_rules && _template == 'full') ...[
          const SizedBox(height: 12),
          HqCard(padding: const EdgeInsets.all(12), child: HqList([for (final (c, t) in _fullRules) HqRow(title: c, sub: t, wrap: true)])),
        ],
        const SizedBox(height: 12),
        if (_fatal != null)
          HqCard(borderColor: Hq.red.withValues(alpha: .4), padding: const EdgeInsets.all(12), child: Text(_fatal!, style: HqText.body.copyWith(color: Hq.red, fontSize: 13)))
        else if (r == null)
          const EmptyNote('Choose a file to check it. Nothing is created until every row passes.', padding: 16)
        else ...[
          MiniStats([('$total', 'Rows checked', null), ('$ready', 'Passed', Hq.green), ('${bad.length}', 'Need fixing', bad.isEmpty ? Hq.muted : Hq.red)]),
          if (bad.isEmpty)
            Text('Every row passed. Each student gets an account, is added to the academy and is mapped to their course and batch. A file with the temporary passwords downloads when you import: hand it to the academy.', style: HqText.sub.copyWith(height: 1.5))
          else ...[
            HqCard(
              borderColor: Hq.red.withValues(alpha: .4),
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Nothing has been created. Fix ${bad.length == 1 ? 'this row' : 'these rows'} and check the file again.', style: HqText.row.copyWith(fontSize: 13)),
                const SizedBox(height: 10),
                HqList([
                  for (final b in bad.take(6))
                    HqRow(
                      leading: Tag('Row ${b.integer('row')}', tone: Tone.red),
                      title: b.str('name').isEmpty ? '(no name)' : b.str('name'),
                      sub: [for (final i in b.maps('issues').take(6)) '${i.str('column')}: ${i.str('problem')}. ${i.str('fix')}'].join('\n'),
                      wrap: true,
                    ),
                ]),
                if (bad.length > 6) Padding(padding: const EdgeInsets.only(top: 8), child: Text('and ${bad.length - 6} more rows. They are all in the error file.', style: HqText.sub)),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: HqButton('Download error file', icon: 'dl', small: true, kind: BtnKind.primary, onPressed: _errorFile)),
              ]),
            ),
          ],
          const SizedBox(height: 8),
        ],
        if (_busy && r == null) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(color: Hq.primary, strokeWidth: 2.5))),
      ],
    );
  }
}
