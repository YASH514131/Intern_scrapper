class CompanyRow {
  CompanyRow({required this.name, required this.url, this.category = ''});

  final String name;
  final String url;
  final String category;
}

class ScanResultRow {
  ScanResultRow({required this.raw});

  final Map<String, dynamic> raw;

  String get company => (raw['company'] ?? '').toString();
  String get title => (raw['title'] ?? '—').toString();
  String get location => (raw['location'] ?? '—').toString();
  String get duration => (raw['duration'] ?? '—').toString();
  String get source => (raw['source'] ?? '—').toString();
  String get applyLink => (raw['applyLink'] ?? '').toString();
  String get error => (raw['error'] ?? '').toString();
  String get bucket => (raw['bucket'] ?? 'error').toString();
  bool get isNew => raw['isNew'] == true;
  bool get isSeenBefore => raw['isSeenBefore'] == true;
  int get fitScore => ((raw['fitScore'] as num?) ?? 0).toInt();
  String get fitLabel => (raw['fitLabel'] ?? '').toString();
  List<String> get scoreWhy =>
      (raw['scoreWhy'] as List<dynamic>? ?? const <dynamic>[])
          .map((e) => e.toString())
          .toList(growable: false);
  bool get eligibilityIssue => raw['eligibilityIssue'] == true;
}
