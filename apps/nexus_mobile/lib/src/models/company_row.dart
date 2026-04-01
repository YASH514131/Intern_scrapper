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
}
