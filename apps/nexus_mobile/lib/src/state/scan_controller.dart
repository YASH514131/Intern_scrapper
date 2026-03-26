import 'dart:async';
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/company_row.dart';
import '../services/nexus_api_client.dart';

class ScanController extends ChangeNotifier {
  ScanController() {
    unawaited(_loadProfilePrefs());
  }

  static const String _prefResumeText = 'nexus.profile.resumeText';
  static const String _prefSkills = 'nexus.profile.skills';
  static const String _prefRoles = 'nexus.profile.roles';
  static const String _prefLocations = 'nexus.profile.locations';
  static const String _prefGradYear = 'nexus.profile.gradYear';
  static const String _prefEligible = 'nexus.profile.eligible';

  bool isDarkMode = true;
  bool isScanning = false;
  String appStatus = 'idle';

  String apiUrl = 'http://10.0.2.2:8080';
  String keywords = 'intern, internship, trainee, co-op, apprentice';
  String excludes = 'senior, staff, director, manager, principal';
  int maxDuration = 6;
  int scanLimit = 20;
  int workers = 1;

  String resumeText = '';
  String profileSkillsInput = 'dart, flutter, api, sql';
  String preferredRolesInput = 'software, backend, mobile, blockchain';
  String preferredLocationsInput = 'remote, bengaluru';
  String graduationYearInput = '';
  bool eligibleForWork = true;

  List<CompanyRow> uploadedCompanies = <CompanyRow>[];
  List<ScanResultRow> allResults = <ScanResultRow>[];
  List<Map<String, dynamic>> logLines = <Map<String, dynamic>>[];
  Map<String, dynamic> metrics = <String, dynamic>{};

  List<String> scanTargets = <String>[];
  Map<String, String> companyStatus = <String, String>{};
  String currentCompany = '';
  String currentCompanyUrl = '';
  double scanProgress = 0.0;
  int doneCount = 0;
  int errorCount = 0;
  int newOpenings = 0;
  int activeStep = 1;
  List<AppAlert> alerts = <AppAlert>[];

  String? _runId;
  int _lastEventIndex = -1;
  Timer? _pollTimer;
  int _lastNewAlertCount = 0;
  int _lastErrorAlertCount = 0;
  bool _completionAlertShown = false;

  String? get runId => _runId;

  void setApiUrl(String value) {
    apiUrl = value;
    notifyListeners();
  }

  void setKeywords(String value) {
    keywords = value;
    notifyListeners();
  }

  void setExcludes(String value) {
    excludes = value;
    notifyListeners();
  }

  void setMaxDuration(double value) {
    maxDuration = value.toInt();
    notifyListeners();
  }

  void setScanLimit(double value) {
    scanLimit = value.toInt();
    notifyListeners();
  }

  void setWorkers(double value) {
    workers = value.toInt();
    notifyListeners();
  }

  void setResumeText(String value) {
    resumeText = value;
    unawaited(_saveProfilePrefs());
    notifyListeners();
  }

  void setProfileSkillsInput(String value) {
    profileSkillsInput = value;
    unawaited(_saveProfilePrefs());
    notifyListeners();
  }

  void setPreferredRolesInput(String value) {
    preferredRolesInput = value;
    unawaited(_saveProfilePrefs());
    notifyListeners();
  }

  void setPreferredLocationsInput(String value) {
    preferredLocationsInput = value;
    unawaited(_saveProfilePrefs());
    notifyListeners();
  }

  void setGraduationYearInput(String value) {
    graduationYearInput = value;
    unawaited(_saveProfilePrefs());
    notifyListeners();
  }

  void setEligibleForWork(bool value) {
    eligibleForWork = value;
    unawaited(_saveProfilePrefs());
    notifyListeners();
  }

  Future<void> pickResumeFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'md', 'doc', 'docx', 'pdf'],
      withData: true,
    );
    if (picked == null || picked.files.single.bytes == null) return;
    final bytes = picked.files.single.bytes!;
    resumeText = utf8.decode(bytes, allowMalformed: true).trim();
    unawaited(_saveProfilePrefs());
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void toggleTheme() {
    isDarkMode = !isDarkMode;
    notifyListeners();
  }

  Future<void> pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'xls'],
      withData: true,
    );
    if (picked == null || picked.files.single.bytes == null) return;

    final file = picked.files.single;
    final bytes = file.bytes!;
    if ((file.extension ?? '').toLowerCase() == 'csv') {
      uploadedCompanies = _parseCsv(bytes);
    } else {
      uploadedCompanies = _parseExcel(bytes);
    }

    activeStep = uploadedCompanies.isEmpty ? 1 : 2;
    notifyListeners();
  }

  Future<void> startScan() async {
    if (uploadedCompanies.isEmpty) return;

    final client = NexusApiClient(apiUrl.trim());
    isScanning = true;
    appStatus = 'queued';
    activeStep = 3;
    logLines = <Map<String, dynamic>>[];
    allResults = <ScanResultRow>[];
    metrics = <String, dynamic>{};
    _lastEventIndex = -1;
    doneCount = 0;
    errorCount = 0;
    newOpenings = 0;
    alerts = <AppAlert>[];
    _lastNewAlertCount = 0;
    _lastErrorAlertCount = 0;
    _completionAlertShown = false;

    scanTargets = uploadedCompanies.take(scanLimit).map((e) => e.name).toList();
    companyStatus = {for (final c in scanTargets) _key(c): 'pending'};
    currentCompanyUrl = '';
    _appendLog(
      kind: 'info',
      message: r'$ starting scan (sequential mode: 1 worker)',
    );
    notifyListeners();

    try {
      final response = await client.startRun(
        companies: uploadedCompanies,
        keywords: keywords,
        excludes: excludes,
        scanLimit: scanLimit,
        concurrency: 1,
        maxDuration: maxDuration,
      );

      final run = response['run'] as Map<String, dynamic>;
      _runId = run['id'].toString();
      appStatus = run['status'].toString();
      _appendLog(kind: 'info', message: '[system] run started id=$_runId');
      notifyListeners();

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
      await poll();
    } catch (e) {
      isScanning = false;
      appStatus = 'failed';
      _appendLog(
        kind: 'error',
        message: '[system] failed to start scan: ${_friendlyNetworkError(e)}',
      );
      notifyListeners();
    }
  }

  Future<void> poll() async {
    final runId = _runId;
    if (runId == null) return;

    final client = NexusApiClient(apiUrl.trim());
    try {
      final eventsBody = await client.fetchEvents(runId, _lastEventIndex);
      final incoming = (eventsBody['events'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (incoming.isNotEmpty) {
        _lastEventIndex = incoming.last['index'] as int;
      }
      for (final e in incoming) {
        _applyCompanyEvent(e);
      }
      logLines = <Map<String, dynamic>>[...logLines, ...incoming];
      appStatus = (eventsBody['status'] ?? appStatus).toString();

      final resultsBody = await client.fetchResults(runId);
      final scoredResults =
          (resultsBody['results'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList();
      _applyRoleFitScoring(scoredResults);
      allResults = scoredResults.map((e) => ScanResultRow(raw: e)).toList();
      metrics =
          resultsBody['metrics'] as Map<String, dynamic>? ??
          <String, dynamic>{};
      newOpenings =
          ((resultsBody['comparison'] as Map<String, dynamic>? ??
                      <String, dynamic>{})['newCount']
                  as num?)
              ?.toInt() ??
          0;

      _syncStatusFromResults();
      final scanned = (metrics['scanned'] as num?)?.toInt() ?? 0;
      final total = (metrics['total'] as num?)?.toInt() ?? scanTargets.length;
      scanProgress = total > 0 ? (scanned / total) : 0;
      doneCount = companyStatus.values.where((s) => s == 'done').length;
      errorCount = companyStatus.values.where((s) => s == 'error').length;
      _raiseRuntimeAlerts();

      if (appStatus == 'complete' || appStatus == 'failed') {
        isScanning = false;
        activeStep = 4;
        _pollTimer?.cancel();
      }
      notifyListeners();
    } catch (e) {
      isScanning = false;
      appStatus = 'failed';
      _appendLog(
        kind: 'error',
        message: '[system] polling failed: ${_friendlyNetworkError(e)}',
      );
      notifyListeners();
    }
  }

  List<ScanResultRow> get hits =>
      allResults.where((r) => r.bucket == 'hit').toList(growable: false);
  List<ScanResultRow> get misses =>
      allResults.where((r) => r.bucket == 'miss').toList(growable: false);
  List<ScanResultRow> get errors =>
      allResults.where((r) => r.bucket == 'error').toList(growable: false);

  Map<String, int> get locationDistribution {
    final map = <String, int>{};
    for (final r in hits) {
      map[r.location] = (map[r.location] ?? 0) + 1;
    }
    return map;
  }

  Map<String, int> get sourceDistribution {
    final map = <String, int>{};
    for (final r in hits) {
      map[r.source] = (map[r.source] ?? 0) + 1;
    }
    return map;
  }

  List<CompanyRow> _parseCsv(Uint8List bytes) {
    final text = utf8.decode(bytes);
    final rows = const CsvToListConverter(eol: '\n').convert(text);
    if (rows.isEmpty) return const [];

    final headers = rows.first.map((e) => e.toString()).toList();
    final urlIndex = _detectUrlIndex(headers);
    final nameIndex = _detectNameIndex(headers);
    final catIndex = _detectCategoryIndex(headers);
    if (urlIndex < 0) return const [];

    return rows
        .skip(1)
        .where((row) => row.length > urlIndex)
        .map((row) {
          final url = row[urlIndex].toString().trim();
          final name = nameIndex >= 0 && row.length > nameIndex
              ? row[nameIndex].toString().trim()
              : _nameFromUrl(url);
          final category = catIndex >= 0 && row.length > catIndex
              ? row[catIndex].toString().trim()
              : '';
          return CompanyRow(name: name, url: url, category: category);
        })
        .where((row) => row.name.isNotEmpty && row.url.isNotEmpty)
        .toList();
  }

  List<CompanyRow> _parseExcel(Uint8List bytes) {
    final excel = xls.Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return const [];

    final sheet = excel.tables.values.first;
    if (sheet.rows.isEmpty) return const [];

    final headers = sheet.rows.first
        .map((e) => e?.value.toString() ?? '')
        .toList();
    final urlIndex = _detectUrlIndex(headers);
    final nameIndex = _detectNameIndex(headers);
    final catIndex = _detectCategoryIndex(headers);
    if (urlIndex < 0) return const [];

    return sheet.rows
        .skip(1)
        .where((row) => row.length > urlIndex)
        .map((row) {
          final url = row[urlIndex]?.value.toString().trim() ?? '';
          final name = nameIndex >= 0 && row.length > nameIndex
              ? row[nameIndex]?.value.toString().trim() ?? ''
              : _nameFromUrl(url);
          final category = catIndex >= 0 && row.length > catIndex
              ? row[catIndex]?.value.toString().trim() ?? ''
              : '';
          return CompanyRow(name: name, url: url, category: category);
        })
        .where((row) => row.name.isNotEmpty && row.url.isNotEmpty)
        .toList();
  }

  int _detectUrlIndex(List<String> headers) {
    final normalized = headers.map((e) => e.trim().toLowerCase()).toList();
    return normalized.indexWhere(
      (h) => const [
        'url',
        'link',
        'website',
        'careers',
        'career url',
        'career_url',
      ].contains(h),
    );
  }

  int _detectNameIndex(List<String> headers) {
    final normalized = headers.map((e) => e.trim().toLowerCase()).toList();
    return normalized.indexWhere(
      (h) => h.contains('company') || h.contains('name'),
    );
  }

  int _detectCategoryIndex(List<String> headers) {
    final normalized = headers.map((e) => e.trim().toLowerCase()).toList();
    return normalized.indexWhere(
      (h) => h.contains('category') || h.contains('sector'),
    );
  }

  String _nameFromUrl(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return '';
    final normalized =
        input.startsWith('http://') || input.startsWith('https://')
        ? input
        : 'https://$input';
    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) return input;
    final host = uri.host.replaceFirst('www.', '');
    final base = host.split('.').isNotEmpty ? host.split('.').first : host;
    if (base.isEmpty) return host;
    return '${base[0].toUpperCase()}${base.substring(1)}';
  }

  void _applyCompanyEvent(Map<String, dynamic> event) {
    final message = (event['message'] ?? '').toString();
    final kind = (event['kind'] ?? '').toString();
    final company = _extractCompany(message);
    if (company == null) return;
    final key = _key(company);
    if (!companyStatus.containsKey(key)) return;

    currentCompany = company;
    currentCompanyUrl = _urlForCompany(company);
    if (kind == 'hit') {
      companyStatus[key] = 'done';
    } else if (kind == 'miss') {
      companyStatus[key] = 'no-listing';
    } else if (kind == 'error') {
      companyStatus[key] = 'error';
    }
  }

  void _syncStatusFromResults() {
    for (final row in allResults) {
      final key = _key(row.company);
      if (!companyStatus.containsKey(key)) continue;
      if (row.bucket == 'hit') {
        companyStatus[key] = 'done';
      } else if (row.bucket == 'miss') {
        companyStatus[key] = 'no-listing';
      } else if (row.bucket == 'error') {
        companyStatus[key] = 'error';
      }
    }
  }

  String _key(String company) => company.trim().toLowerCase();

  String _urlForCompany(String company) {
    final key = _key(company);
    for (final row in uploadedCompanies) {
      if (_key(row.name) == key) return _normalizeUrl(row.url);
    }
    return '';
  }

  String _normalizeUrl(String raw) {
    final input = raw.trim();
    if (input.isEmpty) return '';
    if (input.startsWith('http://') || input.startsWith('https://')) {
      return input;
    }
    return 'https://$input';
  }

  void _appendLog({required String kind, required String message}) {
    logLines = <Map<String, dynamic>>[
      ...logLines,
      {
        'kind': kind,
        'message': message,
        'timestamp': DateTime.now().toIso8601String(),
      },
    ];
  }

  String? _extractCompany(String message) {
    final match = RegExp(r'\[(.+?)\]').firstMatch(message);
    return match?.group(1)?.trim();
  }

  String _friendlyNetworkError(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    final isSocket =
        lower.contains('socketexception') ||
        lower.contains('connection refused') ||
        lower.contains('connection timed out') ||
        lower.contains('failed host lookup');
    if (!isSocket) return raw;

    return '$raw\\n'
        'Hint: this run uses local in-app scanning.\n'
        'Check internet connectivity and verify company URLs are reachable.';
  }

  void dismissAlert(String id) {
    alerts = alerts.where((a) => a.id != id).toList(growable: false);
    notifyListeners();
  }

  void _raiseRuntimeAlerts() {
    if (newOpenings > _lastNewAlertCount) {
      final delta = newOpenings - _lastNewAlertCount;
      _lastNewAlertCount = newOpenings;
      _pushAlert(
        level: 'success',
        title: 'New openings detected',
        body: '$delta new internship opening(s) found this run.',
      );
    }

    if (errorCount > _lastErrorAlertCount) {
      final delta = errorCount - _lastErrorAlertCount;
      _lastErrorAlertCount = errorCount;
      _pushAlert(
        level: 'warning',
        title: 'Scan issues detected',
        body: '$delta company scan(s) failed. Review Errors tab.',
      );
    }

    final atsHits = hits
        .where(
          (h) =>
              h.source.contains('greenhouse') ||
              h.source.contains('lever') ||
              h.source.contains('ashby'),
        )
        .length;
    if (atsHits > 0 && !alerts.any((a) => a.title == 'ATS deep scan active')) {
      _pushAlert(
        level: 'info',
        title: 'ATS deep scan active',
        body: '$atsHits result(s) came from ATS-native extraction.',
      );
    }

    if ((appStatus == 'complete' || appStatus == 'failed') &&
        !_completionAlertShown) {
      _completionAlertShown = true;
      _pushAlert(
        level: appStatus == 'complete' ? 'success' : 'warning',
        title: appStatus == 'complete' ? 'Scan completed' : 'Scan failed',
        body:
            'Hits: ${metrics['hits'] ?? 0}, Seen before: ${metrics['seenBefore'] ?? 0}, New: $newOpenings',
      );
    }
  }

  void _pushAlert({
    required String level,
    required String title,
    required String body,
  }) {
    final id = '${DateTime.now().microsecondsSinceEpoch}-$level';
    alerts = <AppAlert>[
      AppAlert(id: id, level: level, title: title, body: body),
      ...alerts,
    ];
  }

  void _applyRoleFitScoring(List<Map<String, dynamic>> rows) {
    final skillTokens = _tokenize(profileSkillsInput);
    final roleTokens = _tokenize(preferredRolesInput);
    final locationTokens = _tokenize(preferredLocationsInput);
    final resumeTokens = _tokenize(resumeText);
    final gradYear = int.tryParse(graduationYearInput.trim());

    for (final row in rows) {
      if ((row['bucket'] ?? '').toString() != 'hit') {
        row['fitScore'] = 0;
        row['fitLabel'] = 'N/A';
        row['eligibilityIssue'] = false;
        row['scoreWhy'] = <String>[
          'Scoring available for internship hits only.',
        ];
        continue;
      }

      final title = (row['title'] ?? '').toString().toLowerCase();
      final company = (row['company'] ?? '').toString().toLowerCase();
      final source = (row['source'] ?? '').toString().toLowerCase();
      final location = (row['location'] ?? '').toString().toLowerCase();
      final text = '$title $company $source $location';

      final skillMatch = _ratioMatch(skillTokens, text);
      final roleMatch = _ratioMatch(roleTokens, title.isEmpty ? text : title);
      final locationMatch = locationTokens.isEmpty
          ? 0.8
          : _ratioMatch(locationTokens, location);

      double eligibility = 1.0;
      final why = <String>[];
      if (!eligibleForWork) {
        eligibility = 0.15;
        why.add('Eligibility concern: work authorization marked unavailable.');
      }
      if (gradYear != null && gradYear < DateTime.now().year - 3) {
        eligibility = (eligibility - 0.2).clamp(0.0, 1.0);
        why.add('Older graduation year may reduce internship eligibility fit.');
      }
      if (title.contains('senior') || title.contains('staff')) {
        eligibility = (eligibility - 0.55).clamp(0.0, 1.0);
        why.add('Role appears senior-level vs internship target.');
      }
      final eligibilityIssue = eligibility < 0.3;

      final resumeSkillCoverage = skillTokens.isEmpty
          ? 0.0
          : _ratioSetCoverage(skillTokens, resumeTokens);
      final prefsBonus =
          ((row['isNew'] == true ? 1.0 : 0.0) * 0.6) +
          (source.contains('greenhouse') ||
                  source.contains('lever') ||
                  source.contains('ashby')
              ? 0.4
              : 0.0);

      var score =
          (40 * skillMatch) +
          (20 * roleMatch) +
          (15 * locationMatch) +
          (20 * eligibility) +
          (5 * prefsBonus);

      if (eligibilityIssue) {
        score = score > 35 ? 35 : score;
      }

      final rounded = score.round().clamp(0, 100);
      row['fitScore'] = rounded;
      row['fitLabel'] = rounded >= 85
          ? 'Excellent fit'
          : rounded >= 70
          ? 'Strong fit'
          : rounded >= 50
          ? 'Moderate fit'
          : 'Low fit';
      row['eligibilityIssue'] = eligibilityIssue;

      final matchedSkills = skillTokens
          .where((t) => t.isNotEmpty && text.contains(t))
          .toList(growable: false);
      final missingSkills = skillTokens
          .where((t) => t.isNotEmpty && !text.contains(t))
          .take(4)
          .toList(growable: false);

      why.add(
        'Skill match: ${(skillMatch * 100).round()}% (${matchedSkills.isEmpty ? 'no direct skill terms found' : 'matched ${matchedSkills.join(', ')}'}).',
      );
      why.add('Role relevance: ${(roleMatch * 100).round()}%.');
      why.add('Location fit: ${(locationMatch * 100).round()}%.');
      why.add(
        'Resume overlap with profile skills: ${(resumeSkillCoverage * 100).round()}%.',
      );
      if (missingSkills.isNotEmpty) {
        why.add(
          'Missing keywords to improve fit: ${missingSkills.join(', ')}.',
        );
      }

      row['scoreWhy'] = why;
    }
  }

  Future<void> _loadProfilePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    resumeText = prefs.getString(_prefResumeText) ?? resumeText;
    profileSkillsInput = prefs.getString(_prefSkills) ?? profileSkillsInput;
    preferredRolesInput = prefs.getString(_prefRoles) ?? preferredRolesInput;
    preferredLocationsInput =
        prefs.getString(_prefLocations) ?? preferredLocationsInput;
    graduationYearInput = prefs.getString(_prefGradYear) ?? graduationYearInput;
    eligibleForWork = prefs.getBool(_prefEligible) ?? eligibleForWork;
    notifyListeners();
  }

  Future<void> _saveProfilePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefResumeText, resumeText);
    await prefs.setString(_prefSkills, profileSkillsInput);
    await prefs.setString(_prefRoles, preferredRolesInput);
    await prefs.setString(_prefLocations, preferredLocationsInput);
    await prefs.setString(_prefGradYear, graduationYearInput);
    await prefs.setBool(_prefEligible, eligibleForWork);
  }

  List<String> _tokenize(String raw) {
    return raw
        .toLowerCase()
        .split(RegExp(r'[,\n;| ]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e.length > 1)
        .toSet()
        .toList(growable: false);
  }

  double _ratioMatch(List<String> tokens, String text) {
    if (tokens.isEmpty) return 0.0;
    var hits = 0;
    for (final t in tokens) {
      if (text.contains(t)) hits++;
    }
    return hits / tokens.length;
  }

  double _ratioSetCoverage(List<String> left, List<String> right) {
    if (left.isEmpty) return 0.0;
    final r = right.toSet();
    var hits = 0;
    for (final t in left) {
      if (r.contains(t)) hits++;
    }
    return hits / left.length;
  }
}

class AppAlert {
  AppAlert({
    required this.id,
    required this.level,
    required this.title,
    required this.body,
  });

  final String id;
  final String level;
  final String title;
  final String body;
}
