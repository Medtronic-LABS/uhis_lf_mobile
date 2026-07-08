/// Canonical in-progress visit state — flat map of fieldId → value.
///
/// Persisted to [assessment_draft.field_values] (SQLite JSON column).
/// Immutable: every mutation returns a new instance.
class CanonicalVisitData {
  const CanonicalVisitData([Map<String, dynamic>? values])
      : values = values ?? const {};

  /// Raw field values keyed by fieldId.
  final Map<String, dynamic> values;

  CanonicalVisitData setValue(String fieldId, dynamic value) =>
      CanonicalVisitData(Map<String, dynamic>.from(values)..[fieldId] = value);

  dynamic getValue(String fieldId) => values[fieldId];

  /// Merge [other] on top of this — [other] values take precedence.
  CanonicalVisitData merge(CanonicalVisitData other) =>
      CanonicalVisitData({...values, ...other.values});

  CanonicalVisitData removeNulls() => CanonicalVisitData(
        Map<String, dynamic>.from(values)..removeWhere((_, v) => v == null),
      );

  /// Returns a copy with [fieldIds] removed.
  CanonicalVisitData removeFields(Iterable<String> fieldIds) {
    final copy = Map<String, dynamic>.from(values);
    for (final id in fieldIds) {
      copy.remove(id);
    }
    return CanonicalVisitData(copy);
  }

  bool get isEmpty => values.isEmpty;
  bool get isNotEmpty => values.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanonicalVisitData &&
          _mapsEqual(values, other.values);

  @override
  int get hashCode => Object.hashAll(
        values.entries.map((e) => Object.hash(e.key, e.value)),
      );

  static bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
}
