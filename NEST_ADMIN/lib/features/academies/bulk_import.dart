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

const _template = 'name,mobile,email,course,batch\nAnanya Rao,9845012345,ananya.rao@example.in,Bharatnatyam,Batch A';
const _sample = '$_template\nKabir Shah,9900011122,kabir.shah@example.in,Guitar Beginner,Batch B\nMeera Pillai,98450,meera@example.in,Kathak,Batch A\nDev Menon,9811122233,not-an-email,Hip-hop,Batch C\nTara Nair,9822233344,tara.nair@example.in,Watercolor Painting,Batch B';

Future<void> showBulkImport(BuildContext context, List<Map<String, dynamic>> academies) => showHqModal<void>(context, width: 560, builder: (_) => _BulkImport(academies: academies));

class _BulkImport extends ConsumerStatefulWidget {
  const _BulkImport({required this.academies});
  final List<Map<String, dynamic>> academies;

  @override
  ConsumerState<_BulkImport> createState() => _BulkImportState();
}

class _BulkImportState extends ConsumerState<_BulkImport> {
  String? _academy;
  List<Map<String, String>> _rows = const [];
  Map<String, dynamic>? _result;
  String? _fatal;
  bool _busy = false;

  Future<void> _check(String text) async {
    final rows = parseCsv(text);
    final head = rows.isEmpty ? <String>[] : rows.first.map((e) => e.toLowerCase()).toList();
    final missing = ['name', 'mobile'].where((k) => !head.contains(k)).toList();
    if (missing.isNotEmpty) {
      return setState(() {
        _fatal = 'The file is missing the ${missing.join(' and ')} column. Use the template.';
        _result = null;
      });
    }
    String cell(List<String> r, String k) {
      final i = head.indexOf(k);
      return i < 0 || i >= r.length ? '' : r[i];
    }

    final parsed = [for (final r in rows.skip(1)) {'name': cell(r, 'name'), 'mobile': cell(r, 'mobile'), 'email': cell(r, 'email'), 'course': cell(r, 'course'), 'batch': cell(r, 'batch')}];
    if (_academy == null) return setState(() => _fatal = 'Choose the academy first.');
    setState(() {
      _busy = true;
      _fatal = null;
    });
    try {
      final r = await ref.read(dioClientProvider).postMap('/admin/hq/academies/$_academy/import', body: {'rows': parsed, 'commit': false});
      setState(() {
        _rows = parsed;
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

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(dioClientProvider).postMap('/admin/hq/academies/$_academy/import', body: {'rows': _rows, 'commit': true});
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
    final ready = r?.integer('ready') ?? 0;
    final bad = r?.maps('bad') ?? const <Map<String, dynamic>>[];
    return ModalFrame(
      title: 'Bulk import',
      sub: 'Add many students to an academy from one file',
      actions: [
        HqButton('Cancel', onPressed: () => Navigator.of(context).pop()),
        if (r != null) HqButton('Import $ready valid ${ready == 1 ? 'row' : 'rows'}', kind: BtnKind.primary, busy: _busy, onPressed: ready == 0 ? null : _import),
      ],
      children: [
        HqSelect<String>(label: 'Academy', value: _academy, hint: 'Choose an academy', options: [for (final a in widget.academies) SelectOption(a.str('id'), a.str('name'))], onChanged: (v) => setState(() {
              _academy = v;
              _result = null;
            })),
        Wrap(spacing: 8, runSpacing: 8, children: [
          HqButton('Download template', icon: 'dl', small: true, onPressed: () => downloadText('owleo-student-import-template.csv', _template)),
          HqButton('Choose file', icon: 'ul', small: true, onPressed: _pick),
          HqButton('Try a sample file', small: true, onPressed: () => _check(_sample)),
        ]),
        const SizedBox(height: 12),
        if (_fatal != null)
          HqCard(borderColor: Hq.red.withValues(alpha: .4), padding: const EdgeInsets.all(12), child: Text(_fatal!, style: HqText.body.copyWith(color: Hq.red, fontSize: 13)))
        else if (r == null)
          const EmptyNote('Choose a file to check it. Nothing is added until you confirm.', padding: 16)
        else ...[
          MiniStats([('$ready', 'Ready to import', Hq.green), ('${bad.length}', 'Need fixing', bad.isEmpty ? Hq.muted : Hq.red)]),
          if (bad.isNotEmpty) HqList([for (final b in bad.take(8)) HqRow(leading: Tag('Row ${b.integer('row')}', tone: Tone.red), title: b.str('name').isEmpty ? '(no name)' : b.str('name'), sub: b.str('why'), wrap: true)]),
          const SizedBox(height: 8),
          Text('Each student gets an account and a temporary password. A file with the passwords downloads when you import: hand it to the academy.', style: HqText.sub),
          const SizedBox(height: 8),
        ],
        if (_busy && r == null) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(color: Hq.primary, strokeWidth: 2.5))),
      ],
    );
  }
}
