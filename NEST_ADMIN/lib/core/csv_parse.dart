/// Splits CSV text into rows of cells, honouring double quotes.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  for (final line in text.replaceFirst('\u{feff}', '').split(RegExp(r'\r?\n'))) {
    if (line.trim().isEmpty) continue;
    final cells = <String>[];
    final b = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (quoted && i + 1 < line.length && line[i + 1] == '"') {
          b.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (ch == ',' && !quoted) {
        cells.add(b.toString().trim());
        b.clear();
      } else {
        b.write(ch);
      }
    }
    cells.add(b.toString().trim());
    rows.add(cells);
  }
  return rows;
}
