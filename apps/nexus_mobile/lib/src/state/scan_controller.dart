import 'dart:async';
import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/company_row.dart';
import '../services/nexus_api_client.dart';

class ScanController extends ChangeNotifier {
  bool isDarkMode = true;
  bool isScanning = false;
  String appStatus = 'idle';

  String apiUrl = 'http://10.0.2.2:8080';
  String keywords = 'intern, internship, trainee, co-op, apprentice';
  String excludes = 'senior, staff, director, manager, principal';
  int maxDuration = 6;
  int scanLimit = 20;
  int workers = 1;

  List<CompanyRow> uploadedCompanies = <CompanyRow>[];
  List<ScanResultRow> allResults = <ScanResultRow>[];
  List<Map<String, dynamic>> logLines = <Map<String, dynamic>>[];
  Map<String, dynamic> metrics = <String, dynamic>{};

  List<String> scanTargets = <String>[];
  Map<String, String> companyStatus = <String, String>{};
  String currentCompany = '';
  double scanProgress = 0.0;
  int doneCount = 0;
  int errorCount = 0;
  int newOpenings = 0;
  int activeStep = 1;

  String? _runId;
  int _lastEventIndex = -1;
  Timer? _pollTimer;

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

    scanTargets = uploadedCompanies.take(scanLimit).map((e) => e.name).toList();
    companyStatus = {for (final c in scanTargets) _key(c): 'pending'};
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
      allResults = (resultsBody['results'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((e) => ScanResultRow(raw: e))
          .toList();
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
}
