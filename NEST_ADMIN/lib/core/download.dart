import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Saves [text] as a file through the browser's download. A UTF-8 byte-order mark is added for CSV
/// so Excel reads ₹ and accented names correctly.
void downloadText(String filename, String text, {String mime = 'text/csv'}) {
  final bytes = Uint8List.fromList(utf8.encode('﻿$text'));
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: '$mime;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}

/// Opens the browser's file chooser and returns the chosen text file's contents, or null if the
/// person cancels.
Future<String?> pickTextFile({String accept = '.csv,text/csv'}) {
  final done = Completer<String?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept;
  input.onChange.first.then((_) async {
    final f = input.files?.item(0);
    if (f == null) {
      done.complete(null);
      return;
    }
    done.complete((await f.text().toDart).toDart);
  });
  input.oncancel = ((web.Event _) => done.complete(null)).toJS;
  input.click();
  return done.future;
}

/// One CSV cell: quoted only when it has to be.
String csvCell(Object? v) {
  final s = v?.toString() ?? '';
  return RegExp(r'[",\n]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
}

String csvText(List<List<Object?>> rows) => rows.map((r) => r.map(csvCell).join(',')).join('\n');
