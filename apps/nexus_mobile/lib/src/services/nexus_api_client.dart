import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/company_row.dart';

class NexusApiClient {
  NexusApiClient(this.baseUrl);

  // Kept for compatibility with existing state/UI wiring.
  final String baseUrl;

  static const String _seenHitsKey = 'nexus.seen_hit_keys.v1';
  static final Map<String, _LocalRunState> _runs = <String, _LocalRunState>{};
  static String? _lastCompletedRunId;
  static Set<String> _persistedSeenHits = <String>{};
  static bool _storeLoaded = false;

  Future<Map<String, dynamic>> startRun({
    required List<CompanyRow> companies,
    required String keywords,
    required String excludes,
    required int scanLimit,
    required int concurrency,
    required num maxDuration,
  }) async {
    await _ensureStoreLoaded();

    final id = _newRunId();
    final run = _LocalRunState(
      id: id,
      companies: companies.take(scanLimit).toList(growable: false),
      keywords: _splitCsv(keywords),
      excludes: _splitCsv(excludes),
      maxDurationMonths: maxDuration.toInt(),
      scanLimit: scanLimit,
      concurrency: concurrency,
    );
    _runs[id] = run;

    unawaited(_executeRun(run));

    return <String, dynamic>{
      'run': <String, dynamic>{
        'id': run.id,
        'status': run.status,
        'createdAt': run.createdAt.toIso8601String(),
      },
    };
  }

  Future<Map<String, dynamic>> fetchEvents(String runId, int after) async {
    final run = _runs[runId];
    if (run == null) {
      throw Exception('Run not found: $runId');
    }

    final events = run.events
        .where((e) => (e['index'] as int) > after)
        .toList(growable: false);

    return <String, dynamic>{'status': run.status, 'events': events};
  }

  Future<Map<String, dynamic>> fetchResults(String runId) async {
    final run = _runs[runId];
    if (run == null) {
      throw Exception('Run not found: $runId');
    }

    final hitCount = run.results.where((r) => r['bucket'] == 'hit').length;
    final missCount = run.results.where((r) => r['bucket'] == 'miss').length;
    final errorCount = run.results.where((r) => r['bucket'] == 'error').length;
    final scanned = run.results.length;
    final seenBeforeCount = run.results
        .where((r) => r['bucket'] == 'hit' && r['isSeenBefore'] == true)
        .length;
    final newCount = run.results
        .where((r) => r['bucket'] == 'hit' && r['isNew'] == true)
        .length;

    return <String, dynamic>{
      'run': <String, dynamic>{'id': run.id, 'status': run.status},
      'results': run.results,
      'metrics': <String, dynamic>{
        'total': run.companies.length,
        'scanned': scanned,
        'hits': hitCount,
        'misses': missCount,
        'errors': errorCount,
        'seenBefore': seenBeforeCount,
      },
      'comparison': <String, dynamic>{'newCount': newCount},
    };
  }

  Future<String> downloadAllCsv(String runId) async {
    final run = _runs[runId];
    if (run == null) {
      throw Exception('Run not found: $runId');
    }

    final rows = <List<String>>[
      <String>[
        'Company',
        'Bucket',
        'Title',
        'Location',
        'Duration',
        'Source',
        'ApplyLink',
        'Error',
        'IsNew',
        'IsSeenBefore',
      ],
      ...run.results.map(
        (r) => <String>[
          (r['company'] ?? '').toString(),
          (r['bucket'] ?? '').toString(),
          (r['title'] ?? '').toString(),
          (r['location'] ?? '').toString(),
          (r['duration'] ?? '').toString(),
          (r['source'] ?? '').toString(),
          (r['applyLink'] ?? '').toString(),
          (r['error'] ?? '').toString(),
          (r['isNew'] ?? false).toString(),
          (r['isSeenBefore'] ?? false).toString(),
        ],
      ),
    ];

    return rows.map(_toCsvLine).join('\n');
  }

  Future<void> _executeRun(_LocalRunState run) async {
    run.status = 'running';
    _addEvent(run, 'info', '[system] local engine started');

    final seenKeys = _previousAndPersistedHitKeys();

    for (final company in run.companies) {
      _addEvent(run, 'info', '[${company.name}] scanning started');
      try {
        final result = await _scanCompany(company, run.keywords, run.excludes);
        if (result['bucket'] == 'hit') {
          final key = _hitKey(result);
          final seenBefore = seenKeys.contains(key);
          result['isSeenBefore'] = seenBefore;
          result['isNew'] = !seenBefore;
        } else {
          result['isSeenBefore'] = false;
          result['isNew'] = false;
        }

        run.results.add(result);
        final bucket = result['bucket'].toString();
        if (bucket == 'hit') {
          _addEvent(
            run,
            'hit',
            '[${company.name}] internship hit: ${result['title'] ?? 'opening'}',
          );
        } else if (bucket == 'miss') {
          _addEvent(
            run,
            'miss',
            '[${company.name}] no matching openings found',
          );
        } else {
          _addEvent(
            run,
            'error',
            '[${company.name}] scan error: ${(result['error'] ?? '').toString()}',
          );
        }
      } catch (e) {
        run.results.add(<String, dynamic>{
          'company': company.name,
          'bucket': 'error',
          'title': '—',
          'location': '—',
          'duration': '—',
          'source': _hostOf(company.url),
          'applyLink': _normalizeUrl(company.url),
          'error': e.toString(),
          'isNew': false,
          'isSeenBefore': false,
        });
        _addEvent(run, 'error', '[${company.name}] scan error: $e');
      }
    }

    run.status = 'complete';
    run.completedAt = DateTime.now();
    _addEvent(run, 'info', '[system] local engine complete');
    _lastCompletedRunId = run.id;
    await _persistRunHits(run);
  }

  Future<Map<String, dynamic>> _scanCompany(
    CompanyRow company,
    List<String> keywords,
    List<String> excludes,
  ) async {
    final normalizedUrl = _normalizeUrl(company.url);
    final rootUri = Uri.parse(normalizedUrl);
    final rootHtml = await _fetchText(rootUri);

    final ats = _detectAts(rootUri, rootHtml);
    if (ats != null) {
      final viaApi = await _scanViaAts(ats, company.name, keywords, excludes);
      if (viaApi != null) return viaApi;
    }

    return _fallbackTextScan(
      companyName: company.name,
      pageUrl: normalizedUrl,
      html: rootHtml,
      keywords: keywords,
      excludes: excludes,
    );
  }

  Future<Map<String, dynamic>?> _scanViaAts(
    _AtsTarget ats,
    String companyName,
    List<String> keywords,
    List<String> excludes,
  ) async {
    if (ats.type == _AtsType.greenhouse) {
      final uri = Uri.parse(
        'https://boards-api.greenhouse.io/v1/boards/${ats.token}/jobs',
      );
      final res = await http
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final jobs = (decoded['jobs'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>();

      final best = _pickBestJob(
        jobs: jobs,
        titleOf: (j) => (j['title'] ?? '').toString(),
        linkOf: (j) => (j['absolute_url'] ?? '').toString(),
        locationOf: (j) =>
            ((j['location'] as Map<String, dynamic>? ?? const {})['name'] ??
                    'Not specified')
                .toString(),
        keywords: keywords,
        excludes: excludes,
      );
      if (best == null) {
        return _miss(companyName, 'greenhouse', ats.fallbackApplyLink);
      }
      return _hit(
        company: companyName,
        title: best.title,
        location: best.location,
        source: 'greenhouse-api',
        applyLink: best.applyLink,
      );
    }

    if (ats.type == _AtsType.lever) {
      final uri = Uri.parse('https://api.lever.co/v0/postings/${ats.token}');
      final res = await http
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;

      final jobs = (jsonDecode(res.body) as List<dynamic>)
          .whereType<Map<String, dynamic>>();

      final best = _pickBestJob(
        jobs: jobs,
        titleOf: (j) => (j['text'] ?? '').toString(),
        linkOf: (j) =>
            (j['hostedUrl'] ?? j['applyUrl'] ?? ats.fallbackApplyLink)
                .toString(),
        locationOf: (j) =>
            ((j['categories'] as Map<String, dynamic>? ?? const {})['location']
                as String? ??
            'Not specified'),
        keywords: keywords,
        excludes: excludes,
      );
      if (best == null) {
        return _miss(companyName, 'lever', ats.fallbackApplyLink);
      }
      return _hit(
        company: companyName,
        title: best.title,
        location: best.location,
        source: 'lever-api',
        applyLink: best.applyLink,
      );
    }

    if (ats.type == _AtsType.ashby) {
      final uri = Uri.parse('https://jobs.ashbyhq.com/${ats.token}');
      final res = await http
          .get(uri, headers: _headers())
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;

      final html = res.body;
      final openings = RegExp(
        r'href="([^"]+)"[^>]*>([^<]*(intern|trainee|apprentice|co-op)[^<]*)<',
        caseSensitive: false,
      ).allMatches(html).toList(growable: false);

      if (openings.isEmpty) {
        return _miss(companyName, 'ashby', ats.fallbackApplyLink);
      }

      final m = openings.first;
      final rawLink = m.group(1) ?? ats.fallbackApplyLink;
      final title = (m.group(2) ?? 'Internship Opportunity').trim();
      final link = rawLink.startsWith('http')
          ? rawLink
          : 'https://jobs.ashbyhq.com$rawLink';

      return _hit(
        company: companyName,
        title: title,
        location: 'Not specified',
        source: 'ashby',
        applyLink: link,
      );
    }

    return null;
  }

  Map<String, dynamic> _fallbackTextScan({
    required String companyName,
    required String pageUrl,
    required String html,
    required List<String> keywords,
    required List<String> excludes,
  }) {
    final lower = html.toLowerCase();

    final matchedKeyword = keywords.firstWhere(
      (k) => k.isNotEmpty && lower.contains(k),
      orElse: () => '',
    );

    final hasExcluded = excludes.any((x) => x.isNotEmpty && lower.contains(x));

    if (matchedKeyword.isEmpty || hasExcluded) {
      return _miss(companyName, _hostOf(pageUrl), pageUrl);
    }

    return _hit(
      company: companyName,
      title: _titleFromKeyword(matchedKeyword),
      location: _detectLocation(lower),
      source: _hostOf(pageUrl),
      applyLink: pageUrl,
    );
  }

  Future<String> _fetchText(Uri uri) async {
    final response = await http
        .get(uri, headers: _headers())
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw Exception('HTTP ${response.statusCode} from $uri');
    }
    return response.body;
  }

  _AtsTarget? _detectAts(Uri companyUri, String html) {
    final text = html.toLowerCase();

    final gh = RegExp(
      r'boards\.greenhouse\.io/([a-z0-9\-_.]+)',
      caseSensitive: false,
    ).firstMatch(html);
    if (gh != null) {
      return _AtsTarget(
        type: _AtsType.greenhouse,
        token: gh.group(1)!.toLowerCase(),
        fallbackApplyLink: 'https://boards.greenhouse.io/${gh.group(1)!}',
      );
    }

    final lever = RegExp(
      r'jobs\.lever\.co/([a-z0-9\-_.]+)',
      caseSensitive: false,
    ).firstMatch(html);
    if (lever != null) {
      return _AtsTarget(
        type: _AtsType.lever,
        token: lever.group(1)!.toLowerCase(),
        fallbackApplyLink: 'https://jobs.lever.co/${lever.group(1)!}',
      );
    }

    final ashby = RegExp(
      r'jobs\.ashbyhq\.com/([a-z0-9\-_.]+)',
      caseSensitive: false,
    ).firstMatch(html);
    if (ashby != null) {
      return _AtsTarget(
        type: _AtsType.ashby,
        token: ashby.group(1)!.toLowerCase(),
        fallbackApplyLink: 'https://jobs.ashbyhq.com/${ashby.group(1)!}',
      );
    }

    final hostBase = companyUri.host.replaceFirst('www.', '').split('.').first;
    if (text.contains('greenhouse.io') && hostBase.isNotEmpty) {
      return _AtsTarget(
        type: _AtsType.greenhouse,
        token: hostBase.toLowerCase(),
        fallbackApplyLink: companyUri.toString(),
      );
    }
    if (text.contains('lever.co') && hostBase.isNotEmpty) {
      return _AtsTarget(
        type: _AtsType.lever,
        token: hostBase.toLowerCase(),
        fallbackApplyLink: companyUri.toString(),
      );
    }
    if (text.contains('ashbyhq.com') && hostBase.isNotEmpty) {
      return _AtsTarget(
        type: _AtsType.ashby,
        token: hostBase.toLowerCase(),
        fallbackApplyLink: companyUri.toString(),
      );
    }

    return null;
  }

  _JobMatch? _pickBestJob({
    required Iterable<Map<String, dynamic>> jobs,
    required String Function(Map<String, dynamic>) titleOf,
    required String Function(Map<String, dynamic>) linkOf,
    required String Function(Map<String, dynamic>) locationOf,
    required List<String> keywords,
    required List<String> excludes,
  }) {
    for (final job in jobs) {
      final title = titleOf(job).trim();
      if (title.isEmpty) continue;

      final lower = title.toLowerCase();
      final hasKeyword = keywords.any((k) => k.isNotEmpty && lower.contains(k));
      final hasExcluded = excludes.any(
        (x) => x.isNotEmpty && lower.contains(x),
      );
      if (!hasKeyword || hasExcluded) continue;

      final link = linkOf(job).trim();
      final location = locationOf(job).trim();
      return _JobMatch(
        title: title,
        applyLink: link.isEmpty ? '' : link,
        location: location.isEmpty ? 'Not specified' : location,
      );
    }
    return null;
  }

  Map<String, dynamic> _hit({
    required String company,
    required String title,
    required String location,
    required String source,
    required String applyLink,
  }) {
    return <String, dynamic>{
      'company': company,
      'bucket': 'hit',
      'title': title,
      'location': location,
      'duration': '${DateTime.now().year} intake',
      'source': source,
      'applyLink': applyLink,
      'error': '',
    };
  }

  Map<String, dynamic> _miss(String company, String source, String applyLink) {
    return <String, dynamic>{
      'company': company,
      'bucket': 'miss',
      'title': '—',
      'location': '—',
      'duration': '${DateTime.now().year} intake',
      'source': source,
      'applyLink': applyLink,
      'error': '',
    };
  }

  Future<void> _ensureStoreLoaded() async {
    if (_storeLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _persistedSeenHits =
        prefs.getStringList(_seenHitsKey)?.toSet() ?? <String>{};
    _storeLoaded = true;
  }

  Future<void> _persistRunHits(_LocalRunState run) async {
    await _ensureStoreLoaded();
    final newKeys = run.results
        .where((r) => r['bucket'] == 'hit')
        .map(_hitKey)
        .toSet();

    if (newKeys.isEmpty) return;

    _persistedSeenHits.addAll(newKeys);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_seenHitsKey, _persistedSeenHits.toList());
  }

  static String _newRunId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final suffix = Random().nextInt(99999).toString().padLeft(5, '0');
    return 'run-$ts-$suffix';
  }

  static List<String> _splitCsv(String raw) {
    return raw
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, String> _headers() {
    return <String, String>{
      'user-agent': 'NEXUS-Mobile/1.0',
      'accept': 'application/json,text/html;q=0.9,*/*;q=0.8',
    };
  }

  static void _addEvent(_LocalRunState run, String kind, String message) {
    run.events.add(<String, dynamic>{
      'index': run._nextEventIndex++,
      'kind': kind,
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Set<String> _previousAndPersistedHitKeys() {
    final seen = <String>{..._persistedSeenHits};

    final prevId = _lastCompletedRunId;
    if (prevId == null) return seen;

    final prev = _runs[prevId];
    if (prev == null) return seen;

    seen.addAll(prev.results.where((r) => r['bucket'] == 'hit').map(_hitKey));
    return seen;
  }

  static String _normalizeUrl(String raw) {
    final input = raw.trim();
    if (input.startsWith('http://') || input.startsWith('https://')) {
      return input;
    }
    return 'https://$input';
  }

  static String _hostOf(String rawUrl) {
    final uri = Uri.tryParse(_normalizeUrl(rawUrl));
    return uri?.host.replaceFirst('www.', '') ?? 'unknown';
  }

  static String _detectLocation(String lowerHtml) {
    if (lowerHtml.contains('remote')) return 'Remote';
    if (lowerHtml.contains('bangalore') || lowerHtml.contains('bengaluru')) {
      return 'Bengaluru';
    }
    if (lowerHtml.contains('hyderabad')) return 'Hyderabad';
    if (lowerHtml.contains('pune')) return 'Pune';
    if (lowerHtml.contains('mumbai')) return 'Mumbai';
    if (lowerHtml.contains('delhi')) return 'Delhi';
    return 'Not specified';
  }

  static String _titleFromKeyword(String keyword) {
    switch (keyword) {
      case 'intern':
      case 'internship':
        return 'Internship Opportunity';
      case 'trainee':
        return 'Trainee Program';
      case 'co-op':
        return 'Co-op Opening';
      case 'apprentice':
        return 'Apprenticeship Opening';
      default:
        return 'Early Career Opening';
    }
  }

  static String _hitKey(Map<String, dynamic> row) {
    final company = (row['company'] ?? '').toString().trim().toLowerCase();
    final title = (row['title'] ?? '').toString().trim().toLowerCase();
    final link = (row['applyLink'] ?? '').toString().trim().toLowerCase();
    return '$company|$title|$link';
  }

  static String _toCsvLine(List<String> values) {
    return values.map(_csvEscape).join(',');
  }

  static String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    final needsQuotes =
        escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n');
    if (!needsQuotes) return escaped;
    return '"$escaped"';
  }
}

enum _AtsType { greenhouse, lever, ashby }

class _AtsTarget {
  _AtsTarget({
    required this.type,
    required this.token,
    required this.fallbackApplyLink,
  });

  final _AtsType type;
  final String token;
  final String fallbackApplyLink;
}

class _JobMatch {
  _JobMatch({
    required this.title,
    required this.applyLink,
    required this.location,
  });

  final String title;
  final String applyLink;
  final String location;
}

class _LocalRunState {
  _LocalRunState({
    required this.id,
    required this.companies,
    required this.keywords,
    required this.excludes,
    required this.maxDurationMonths,
    required this.scanLimit,
    required this.concurrency,
  });

  final String id;
  final DateTime createdAt = DateTime.now();
  DateTime? completedAt;

  String status = 'queued';
  final List<CompanyRow> companies;
  final List<String> keywords;
  final List<String> excludes;
  final int maxDurationMonths;
  final int scanLimit;
  final int concurrency;

  final List<Map<String, dynamic>> events = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> results = <Map<String, dynamic>>[];

  int _nextEventIndex = 0;
}
