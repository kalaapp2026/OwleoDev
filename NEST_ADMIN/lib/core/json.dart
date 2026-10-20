/// Typed reads from the server's JSON maps. The HQ screens read dozens of fields each; these keep
/// every read null-safe in one short call instead of a cast and a fallback at each use.
extension JsonMap on Map<String, dynamic> {
  String str(String k, [String fallback = '']) => this[k]?.toString() ?? fallback;

  String? strOrNull(String k) {
    final v = this[k];
    return v == null || v.toString().isEmpty ? null : v.toString();
  }

  int integer(String k, [int fallback = 0]) {
    final v = this[k];
    if (v is num) return v.round();
    return int.tryParse('$v') ?? fallback;
  }

  int? integerOrNull(String k) {
    final v = this[k];
    if (v == null) return null;
    if (v is num) return v.round();
    return int.tryParse('$v');
  }

  double number(String k, [double fallback = 0]) {
    final v = this[k];
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? fallback;
  }

  bool flag(String k) => this[k] == true;

  Map<String, dynamic> obj(String k) {
    final v = this[k];
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  List<Map<String, dynamic>> maps(String k) {
    final v = this[k];
    if (v is! List) return const [];
    return [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)];
  }

  List<double> doubles(String k) {
    final v = this[k];
    if (v is! List) return const [];
    return v.map((e) => (e as num).toDouble()).toList();
  }

  List<String> strings(String k) {
    final v = this[k];
    if (v is! List) return const [];
    return v.map((e) => e.toString()).toList();
  }
}
