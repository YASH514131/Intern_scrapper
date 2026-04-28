import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/company_row.dart';
import '../local_scraper/models.dart' as local_models;
import '../local_scraper/services/scraper_service.dart' as local_services;

class NexusApiClient {
  NexusApiClient(this.baseUrl);

  // Kept for compatibility with existing state/UI wiring.
  final String baseUrl;

  static const String _seenHitsKey = 'nexus.seen_hit_keys.v1';
  static const String _rateLimitUserAgent = 'Mozilla/5.0';
  static const Duration _minRequestGap = Duration(milliseconds: 1500);
  static const Duration _requestTimeout = Duration(seconds: 10);
  static const int _maxRetries = 3;

  static final Map<String, _LocalRunState> _runs = <String, _LocalRunState>{};
  static Set<String> _persistedSeenHits = <String>{};
  static bool _storeLoaded = false;
  static final Map<String, DateTime> _lastRequestAtByHost =
      <String, DateTime>{};
  static final Map<String, Future<void>> _hostRateLimitChains =
      <String, Future<void>>{};

  static Database? _db;
  static final local_services.ScraperService _fullScraperEngine =
      local_services.ScraperService(client: http.Client(), callsPerSecond: 0.8);

  Future<Map<String, dynamic>> startRun({
    required List<CompanyRow> companies,
    required String keywords,
    required String excludes,
    required int scanLimit,
    required int concurrency,
  }) async {
    final selected = companies
        .take(scanLimit)
        .where((c) => c.name.trim().isNotEmpty && c.url.trim().isNotEmpty)
        .toList(growable: false);
    if (selected.isEmpty) {
      throw Exception('No valid companies were provided for this run.');
    }

    await _ensureStoreLoaded();
    await _ensureDb();

    final run = _LocalRunState(
      id: _newRunId(),
      companies: selected,
      keywords: _splitCsv(keywords),
      excludes: _splitCsv(excludes),
      scanLimit: selected.length,
      concurrency: min(max(1, concurrency), 10),
    );
    _runs[run.id] = run;
    _addEvent(
      run,
      'info',
      '[system] run queued (${run.companies.length} companies)',
    );

    unawaited(
      _executeRun(run).catchError((Object error, StackTrace stackTrace) {
        run.status = 'failed';
        run.completedAt = DateTime.now();
        _addEvent(run, 'error', '[system] local engine failed: $error');
      }),
    );

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
      throw Exception('Unknown run id: $runId');
    }

    final events = run.events
        .where((event) => (event['index'] as int? ?? -1) > after)
        .map((event) => Map<String, dynamic>.from(event))
        .toList(growable: false);

    return <String, dynamic>{'status': run.status, 'events': events};
  }

  Future<Map<String, dynamic>> fetchResults(String runId) async {
    final run = _runs[runId];
    if (run == null) {
      throw Exception('Unknown run id: $runId');
    }

    final rows = await _readRunRows(runId);
    final hitCount = rows.where((r) => r['bucket'] == 'hit').length;
    final missCount = rows.where((r) => r['bucket'] == 'miss').length;
    final errorCount = rows.where((r) => r['bucket'] == 'error').length;
    final seenBeforeCount = rows
        .where((r) => r['bucket'] == 'hit' && r['isSeenBefore'] == true)
        .length;
    final newCount = rows
        .where((r) => r['bucket'] == 'hit' && r['isNew'] == true)
        .length;

    return <String, dynamic>{
      'status': run.status,
      'results': rows,
      'metrics': <String, dynamic>{
        'scanned': run.processedCompanies,
        'total': run.companies.length,
        'hits': hitCount,
        'misses': missCount,
        'errors': errorCount,
        'seenBefore': seenBeforeCount,
      },
      'comparison': <String, dynamic>{'newCount': newCount},
    };
  }

  Future<String> downloadAllCsv(String runId) async {
    final rows = await _readRunRows(runId);
    final lines = <String>[
      _toCsvLine(<String>[
        'Company',
        'Title',
        'Location',
        'Duration',
        'Source',
        'Apply Link',
        'Bucket',
        'Is New',
        'Seen Before',
        'Error',
      ]),
      ...rows.map(
        (row) => _toCsvLine(<String>[
          (row['company'] ?? '').toString(),
          (row['title'] ?? '').toString(),
          (row['location'] ?? '').toString(),
          (row['duration'] ?? '').toString(),
          (row['source'] ?? '').toString(),
          (row['applyLink'] ?? '').toString(),
          (row['bucket'] ?? '').toString(),
          ((row['isNew'] ?? false) == true) ? 'yes' : 'no',
          ((row['isSeenBefore'] ?? false) == true) ? 'yes' : 'no',
          (row['error'] ?? '').toString(),
        ]),
      ),
    ];
    return lines.join('\n');
  }

  Future<void> _executeRun(_LocalRunState run) async {
    run.status = 'running';
    _addEvent(run, 'info', '[system] local engine started');

    final historicalSeen = <String>{..._persistedSeenHits};
    final runInsertedKeys = <String>{};

    final queue = Queue<CompanyRow>.from(run.companies);
    final workerCount = run.companies.isEmpty
        ? 0
        : min(max(1, run.concurrency), run.companies.length);
    final workers = <Future<void>>[];
    for (var i = 0; i < workerCount; i++) {
      workers.add(
        _runWorkerLoop(
          run: run,
          queue: queue,
          historicalSeen: historicalSeen,
          runInsertedKeys: runInsertedKeys,
        ),
      );
    }
    await Future.wait(workers);

    run.status = 'complete';
    run.completedAt = DateTime.now();
    _addEvent(run, 'info', '[system] local engine complete');
    await _persistRunHits(run.id);
  }

  Future<void> _runWorkerLoop({
    required _LocalRunState run,
    required Queue<CompanyRow> queue,
    required Set<String> historicalSeen,
    required Set<String> runInsertedKeys,
  }) async {
    while (true) {
      if (queue.isEmpty) {
        return;
      }
      final company = queue.removeFirst();

      _addEvent(run, 'info', '[${company.name}] scanning started');
      try {
        final summary = await _scanCompanyAndStore(
          runId: run.id,
          company: company,
          keywords: run.keywords,
          excludes: run.excludes,
          historicalSeen: historicalSeen,
          runInsertedKeys: runInsertedKeys,
        );

        run.processedCompanies++;
        if (summary.hits > 0) {
          _addEvent(
            run,
            'hit',
            '[${company.name}] internship hit${summary.hits > 1 ? 's' : ''}: ${summary.previewTitle}',
          );
        } else if (summary.errors > 0) {
          run.errorCompanies++;
          _addEvent(
            run,
            'error',
            '[${company.name}] scan error: ${summary.errorText}',
          );
        } else {
          _addEvent(
            run,
            'miss',
            '[${company.name}] no matching openings found',
          );
        }
      } catch (e) {
        run.processedCompanies++;
        run.errorCompanies++;
        await _insertResultRow(
          runId: run.id,
          row: _error(
            company: company.name,
            source: _hostOf(company.url),
            applyLink: _normalizeUrl(company.url),
            error: e.toString(),
            atsType: _detectAtsType(_normalizeUrl(company.url)).name,
          ),
        );
        _addEvent(run, 'error', '[${company.name}] scan error: $e');
      }
    }
  }

  Future<_ScanSummary> _scanCompanyAndStore({
    required String runId,
    required CompanyRow company,
    required List<String> keywords,
    required List<String> excludes,
    required Set<String> historicalSeen,
    required Set<String> runInsertedKeys,
  }) async {
    final normalizedUrl = _normalizeUrl(company.url);
    final atsType = _detectAtsType(normalizedUrl).name;

    final effectiveKeywords = keywords.isEmpty
        ? local_models.ScanConfig.defaults().keywords
        : keywords;
    final engineConfig = local_models.ScanConfig(
      keywords: effectiveKeywords,
      excludeKeywords: excludes,
      scanLimit: 1,
      concurrency: 1,
      enableJs: false,
      hardTimeoutSeconds: 24,
    );

    try {
      final rows = await _fullScraperEngine
          .scrapeCompany(
            local_models.CompanyInput(name: company.name, url: normalizedUrl),
            engineConfig,
          )
          .timeout(Duration(seconds: engineConfig.hardTimeoutSeconds + 5));

      var hitCount = 0;
      var errorCount = 0;
      var preview = 'opening';
      var firstError = '';
      var errorSource = _hostOf(normalizedUrl);

      for (final row in rows) {
        switch (row.bucket) {
          case local_models.ResultBucket.hit:
            final title = row.title.trim();
            if (title.isEmpty || title == '—') {
              continue;
            }
            final inserted = await _insertHit(
              runId: runId,
              company: company.name,
              title: title,
              location: row.location.trim().isEmpty
                  ? 'Not specified'
                  : row.location.trim(),
              source: row.source.trim().isEmpty
                  ? _hostOf(normalizedUrl)
                  : row.source.trim(),
              applyLink: row.applyLink.trim().isEmpty
                  ? normalizedUrl
                  : row.applyLink.trim(),
              duration: row.duration.trim(),
              atsType: atsType,
              historicalSeen: historicalSeen,
              runInsertedKeys: runInsertedKeys,
            );
            if (inserted) {
              hitCount++;
              preview = title;
            }
            break;
          case local_models.ResultBucket.error:
            errorCount++;
            if (firstError.isEmpty) {
              firstError = row.error.trim().isEmpty
                  ? 'Local scraper failed'
                  : row.error.trim();
            }
            if (row.source.trim().isNotEmpty) {
              errorSource = row.source.trim();
            }
            break;
          case local_models.ResultBucket.miss:
            break;
        }
      }

      if (hitCount > 0) {
        return _ScanSummary.hit(hitCount, preview);
      }

      if (errorCount > 0) {
        await _insertResultRow(
          runId: runId,
          row: _error(
            company: company.name,
            source: errorSource,
            applyLink: normalizedUrl,
            error: firstError,
            atsType: atsType,
          ),
        );
        return _ScanSummary.error(firstError);
      }

      if (rows.isEmpty) {
        return _scanCompanyAndStoreLegacy(
          runId: runId,
          company: company,
          keywords: keywords,
          excludes: excludes,
          historicalSeen: historicalSeen,
          runInsertedKeys: runInsertedKeys,
        );
      }

      await _insertResultRow(
        runId: runId,
        row: _miss(
          company.name,
          _hostOf(normalizedUrl),
          normalizedUrl,
          atsType: atsType,
        ),
      );
      return _ScanSummary.miss();
    } catch (_) {
      return _scanCompanyAndStoreLegacy(
        runId: runId,
        company: company,
        keywords: keywords,
        excludes: excludes,
        historicalSeen: historicalSeen,
        runInsertedKeys: runInsertedKeys,
      );
    }
  }

  Future<_ScanSummary> _scanCompanyAndStoreLegacy({
    required String runId,
    required CompanyRow company,
    required List<String> keywords,
    required List<String> excludes,
    required Set<String> historicalSeen,
    required Set<String> runInsertedKeys,
  }) async {
    final normalizedUrl = _normalizeUrl(company.url);
    final uri = Uri.parse(normalizedUrl);
    final ats = _detectAtsType(normalizedUrl);

    // Fallback path kept for resilience if the full engine times out/fails.
    if (ats != _AtsType.custom) {
      final directSummary = await _scanCustom(
        runId: runId,
        company: company,
        uri: uri,
        keywords: keywords,
        excludes: excludes,
        historicalSeen: historicalSeen,
        runInsertedKeys: runInsertedKeys,
        writeTerminalMiss: false,
      );
      if (directSummary.hits > 0) {
        return directSummary;
      }
    }

    switch (ats) {
      case _AtsType.lever:
        return _scanLever(
          runId: runId,
          company: company,
          uri: uri,
          keywords: keywords,
          excludes: excludes,
          historicalSeen: historicalSeen,
          runInsertedKeys: runInsertedKeys,
        );
      case _AtsType.ashby:
        return _scanAshby(
          runId: runId,
          company: company,
          uri: uri,
          keywords: keywords,
          excludes: excludes,
          historicalSeen: historicalSeen,
          runInsertedKeys: runInsertedKeys,
        );
      case _AtsType.greenhouse:
        return _scanGreenhouse(
          runId: runId,
          company: company,
          uri: uri,
          keywords: keywords,
          excludes: excludes,
          historicalSeen: historicalSeen,
          runInsertedKeys: runInsertedKeys,
        );
      case _AtsType.workday:
        return _scanWorkday(
          runId: runId,
          company: company,
          uri: uri,
          keywords: keywords,
          excludes: excludes,
          historicalSeen: historicalSeen,
          runInsertedKeys: runInsertedKeys,
        );
      case _AtsType.coinbase:
        return _scanCoinbase(
          runId: runId,
          company: company,
          keywords: keywords,
          excludes: excludes,
          historicalSeen: historicalSeen,
          runInsertedKeys: runInsertedKeys,
        );
      case _AtsType.rippling:
        return _scanRippling(
          runId: runId,
          company: company,
          uri: uri,
          keywords: keywords,
          excludes: excludes,
          historicalSeen: historicalSeen,
          runInsertedKeys: runInsertedKeys,
        );
      case _AtsType.custom:
        return _scanCustom(
          runId: runId,
          company: company,
          uri: uri,
          keywords: keywords,
          excludes: excludes,
          historicalSeen: historicalSeen,
          runInsertedKeys: runInsertedKeys,
        );
    }
  }

  Future<_ScanSummary> _scanLever({
    required String runId,
    required CompanyRow company,
    required Uri uri,
    required List<String> keywords,
    required List<String> excludes,
    required Set<String> historicalSeen,
    required Set<String> runInsertedKeys,
  }) async {
    final slug = _lastPathSegment(uri);
    if (slug.isEmpty) {
      await _insertResultRow(
        runId: runId,
        row: _miss(
          company.name,
          'lever-api',
          _normalizeUrl(company.url),
          atsType: _AtsType.lever.name,
        ),
      );
      return _ScanSummary.miss();
    }

    final endpoint = Uri.parse(
      'https://api.lever.co/v0/postings/$slug?mode=json',
    );
    final outcome = await _requestWithRetry(_HttpMethod.get, endpoint);
    if (outcome.statusCode == 404) {
      await _insertResultRow(
        runId: runId,
        row: _miss(
          company.name,
          'lever-api',
          _normalizeUrl(company.url),
          atsType: _AtsType.lever.name,
        ),
      );
      return _ScanSummary.miss();
    }
    if (outcome.statusCode != 200) {
      await _insertResultRow(
        runId: runId,
        row: _error(
          company: company.name,
          source: 'lever-api',
          applyLink: _normalizeUrl(company.url),
          error: 'HTTP ${outcome.statusCode}',
          atsType: _AtsType.lever.name,
        ),
      );
      return _ScanSummary.error('HTTP ${outcome.statusCode}');
    }

    final jobs = (jsonDecode(outcome.body) as List<dynamic>)
        .whereType<Map<String, dynamic>>();
    var hitCount = 0;
    var preview = 'opening';

    for (final job in jobs) {
      final title = (job['text'] ?? '').toString().trim();
      if (!_isInternshipMatch(title, keywords, excludes)) continue;
      final categories = job['categories'] as Map<String, dynamic>? ?? const {};
      final location = (categories['location'] ?? 'Not specified').toString();
      final link = (job['hostedUrl'] ?? _normalizeUrl(company.url)).toString();
      final inserted = await _insertHit(
        runId: runId,
        company: company.name,
        title: title,
        location: location,
        source: 'lever-api',
        applyLink: link,
        atsType: _AtsType.lever.name,
        historicalSeen: historicalSeen,
        runInsertedKeys: runInsertedKeys,
      );
      if (inserted) {
        hitCount++;
        preview = title;
      }
    }

    if (hitCount == 0) {
      await _insertResultRow(
        runId: runId,
        row: _miss(
          company.name,
          'lever-api',
          _normalizeUrl(company.url),
          atsType: _AtsType.lever.name,
        ),
      );
      return _ScanSummary.miss();
    }
    return _ScanSummary.hit(hitCount, preview);
  }

  Future<_ScanSummary> _scanAshby({
    required String runId,
    required CompanyRow company,
    required Uri uri,
    required List<String> keywords,
    required List<String> excludes,
    required Set<String> historicalSeen,
    required Set<String> runInsertedKeys,
  }) async {
    final slugs = _ashbySlugCandidates(uri);
    if (slugs.isEmpty) {
      await _insertResultRow(
        runId: runId,
        row: _miss(
          company.name,
          'ashby-api',
          _normalizeUrl(company.url),
          atsType: _AtsType.ashby.name,
        ),
      );
      return _ScanSummary.miss();
    }

    var hitCount = 0;
    var preview = 'opening';

    for (final slug in slugs) {
      final endpoint = Uri.parse(
        'https://api.ashbyhq.com/posting-api/job-board/$slug',
      );
      final outcome = await _requestWithRetry(
        _HttpMethod.post,
        endpoint,
        headers: <String, String>{
          'content-type': 'application/json',
          ..._headers(),
        },
        body: jsonEncode(<String, dynamic>{
          'organizationHostedJobsPageName': slug,
        }),
      );

      if (outcome.statusCode != 200) {
        continue;
      }

      final body = jsonDecode(outcome.body) as Map<String, dynamic>;
      final jobs = (body['jobs'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>();

      for (final job in jobs) {
        final title = (job['title'] ?? '').toString().trim();
        if (!_isInternshipMatch(title, keywords, excludes)) continue;
        final location = (job['location'] ?? 'Not specified').toString();
        final link = (job['jobUrl'] ?? 'https://jobs.ashbyhq.com/$slug')
            .toString();
        final inserted = await _insertHit(
          runId: runId,
          company: company.name,
          title: title,
          location: location,
          source: 'ashby-api',
          applyLink: link,
          atsType: _AtsType.ashby.name,
          historicalSeen: historicalSeen,
          runInsertedKeys: runInsertedKeys,
        );
        if (inserted) {
          hitCount++;
          preview = title;
        }
      }

      if (hitCount > 0) {
        return _ScanSummary.hit(hitCount, preview);
      }
    }

    // Some Ashby boards resolve in HTML even when posting-api slug mapping fails.
    final htmlOutcome = await _requestWithRetry(_HttpMethod.get, uri);
    if (htmlOutcome.statusCode == 200 && htmlOutcome.body.trim().isNotEmpty) {
      final htmlJobs = _extractAshbyJobsFromHtml(htmlOutcome.body, uri);
      for (final job in htmlJobs) {
        final title = (job['title'] ?? '').toString().trim();
        if (!_isInternshipMatch(title, keywords, excludes)) continue;
        final link = (job['url'] ?? uri.toString()).toString();
        final inserted = await _insertHit(
          runId: runId,
          company: company.name,
          title: title,
          location: 'Not specified',
          source: 'ashby-html',
          applyLink: link,
          atsType: _AtsType.ashby.name,
          historicalSeen: historicalSeen,
          runInsertedKeys: runInsertedKeys,
        );
        if (inserted) {
          hitCount++;
          preview = title;
        }
      }
      if (hitCount > 0) {
        return _ScanSummary.hit(hitCount, preview);
      }
    }

    await _insertResultRow(
      runId: runId,
      row: _miss(
        company.name,
        'ashby-api',
        _normalizeUrl(company.url),
        atsType: _AtsType.ashby.name,
      ),
    );
    return _ScanSummary.miss();
  }

  Future<_ScanSummary> _scanGreenhouse({
    required String runId,
    required CompanyRow company,
    required Uri uri,
    required List<String> keywords,
    required List<String> excludes,
    required Set<String> historicalSeen,
    required Set<String> runInsertedKeys,
  }) async {
    final slug = _lastPathSegment(uri);
    if (slug.isEmpty) {
      await _insertResultRow(
        runId: runId,
        row: _miss(
          company.name,
          'greenhouse-api',
          _normalizeUrl(company.url),
          atsType: _AtsType.greenhouse.name,
        ),
      );
      return _ScanSummary.miss();
    }

    final endpoint = Uri.parse(
      'https://boards-api.greenhouse.io/v1/boards/$slug/jobs?content=true',
    );
    final outcome = await _requestWithRetry(_HttpMethod.get, endpoint);
    if (outcome.statusCode == 404) {
      await _insertResultRow(
        runId: runId,
        row: _miss(
          company.name,
          'greenhouse-api',
          _normalizeUrl(company.url),
          atsType: _AtsType.greenhouse.name,
        ),
      );
      return _ScanSummary.miss();
    }
    if (outcome.statusCode != 200) {
      await _insertResultRow(
        runId: runId,
        row: _error(
          company: company.name,
          source: 'greenhouse-api',
          applyLink: _normalizeUrl(company.url),
          error: 'HTTP ${outcome.statusCode}',
          atsType: _AtsType.greenhouse.name,
        ),
      );
      return _ScanSummary.error('HTTP ${outcome.statusCode}');
    }

    final body = jsonDecode(outcome.body) as Map<String, dynamic>;
    final jobs = (body['jobs'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>();

    var hitCount = 0;
    var preview = 'opening';
    for (final job in jobs) {
      final title = (job['title'] ?? '').toString().trim();
      if (!_isInternshipMatch(title, keywords, excludes)) continue;
      final loc =
          (job['location'] as Map<String, dynamic>? ?? const {})['name'];
      final location = (loc ?? 'Not specified').toString();
      final link = (job['absolute_url'] ?? _normalizeUrl(company.url))
          .toString();
      final inserted = await _insertHit(
        runId: runId,
        company: company.name,
        title: title,
        location: location,
        source: 'greenhouse-api',
        applyLink: link,
        atsType: _AtsType.greenhouse.name,
        historicalSeen: historicalSeen,
        runInsertedKeys: runInsertedKeys,
      );
      if (inserted) {
        hitCount++;
        preview = title;
      }
    }

    if (hitCount == 0) {
      await _insertResultRow(
        runId: runId,
        row: _miss(
          company.name,
          'greenhouse-api',
          _normalizeUrl(company.url),
          atsType: _AtsType.greenhouse.name,
        ),
      );
      return _ScanSummary.miss();
    }
    return _ScanSummary.hit(hitCount, preview);
  }

  Future<_ScanSummary> _scanRippling({
    required String runId,
    required CompanyRow company,
    required Uri uri,
    required List<String> keywords,
    required List<String> excludes,
    required Set<String> historicalSeen,
    required Set<String> runInsertedKeys,
  }) async {
    final slug =
        _segmentAfter(uri.pathSegments, 'rippling.com') ??
        _firstPathSegment(uri);
    final safeSlug = slug.isEmpty ? _firstPathSegment(uri) : slug;
    if (safeSlug.isEmpty) {
      await _insertResultRow(
        runId: runId,
        row: _miss(
          company.name,
          'rippling-api',
          _normalizeUrl(company.url),
          atsType: _AtsType.rippling.name,
        ),
      );
      return _ScanSummary.miss();
    }

    final endpoint = Uri.parse(
      'https://app.rippling.com/api/ats/jobs/public/?company=$safeSlug',
    );
    final outcome = await _requestWithRetry(_HttpMethod.get, endpoint);
    if (outcome.statusCode == 404) {
      await _insertResultRow(
        runId: runId,
        row: _miss(
          company.name,
          'rippling-api',
          _normalizeUrl(company.url),
          atsType: _AtsType.rippling.name,
        ),
      );
      return _ScanSummary.miss();
    }
    if (outcome.statusCode != 200) {
      await _insertResultRow(
        runId: runId,
        row: _error(
          company: company.name,
          source: 'rippling-api',
          applyLink: _normalizeUrl(company.url),
          error: 'HTTP ${outcome.statusCode}',
          atsType: _AtsType.rippling.name,
        ),
      );
      return _ScanSummary.error('HTTP ${outcome.statusCode}');
    }

    final body = jsonDecode(outcome.body) as Map<String, dynamic>;
    final jobs = (body['results'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>();

    var hitCount = 0;
    var preview = 'opening';
    for (final job in jobs) {
      final title = (job['title'] ?? '').toString().trim();
      if (!_isInternshipMatch(title, keywords, excludes)) continue;
      final location = (job['location'] ?? 'Not specified').toString();
      final link = _normalizeUrl(company.url);
      final inserted = await _insertHit(
        runId: runId,
        company: company.name,
        title: title,
        location: location,
        source: 'rippling-api',
        applyLink: link,
        atsType: _AtsType.rippling.name,
        historicalSeen: historicalSeen,
        runInsertedKeys: runInsertedKeys,
      );
      if (inserted) {
        hitCount++;
        preview = title;
      }
    }

    if (hitCount == 0) {
      await _insertResultRow(
        runId: runId,
        row: _miss(
          company.name,
          'rippling-api',
          _normalizeUrl(company.url),
          atsType: _AtsType.rippling.name,
        ),
      );
      return _ScanSummary.miss();
    }
    return _ScanSummary.hit(hitCount, preview);
  }

  Future<_ScanSummary> _scanWorkday({
    required String runId,
    required CompanyRow company,
    required Uri uri,
    required List<String> keywords,
    required List<String> excludes,
    required Set<String> historicalSeen,
    required Set<String> runInsertedKeys,
  }) async {
    final hostParts = uri.host.split('.');
    final tenant = hostParts.isNotEmpty ? hostParts.first : '';
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final cxsIndex = segments.indexOf('cxs');
    String tenantPath = tenant;
    String board = 'jobs';

    if (cxsIndex >= 0 && cxsIndex + 2 < segments.length) {
      tenantPath = segments[cxsIndex + 1];
      board = segments[cxsIndex + 2];
    } else {
      final jobsIndex = segments.indexOf('jobs');
      if (jobsIndex > 0) {
        board = segments[jobsIndex - 1];
      } else if (segments.isNotEmpty) {
        board = segments.last;
      }
    }

    if (tenantPath.isEmpty || board.isEmpty) {
      await _insertResultRow(
        runId: runId,
        row: _miss(
          company.name,
          'workday-api',
          _normalizeUrl(company.url),
          atsType: _AtsType.workday.name,
        ),
      );
      return _ScanSummary.miss();
    }

    final endpoint = Uri.parse(
      'https://$tenant.myworkdayjobs.com/wday/cxs/$tenantPath/$board/jobs',
    );

    const limit = 20;
    var offset = 0;
    var total = 1;
    var pageGuard = 0;
    var hitCount = 0;
    var preview = 'opening';

    while (offset < total && pageGuard < 200) {
      pageGuard++;
      final outcome = await _requestWithRetry(
        _HttpMethod.post,
        endpoint,
        headers: <String, String>{
          'content-type': 'application/json',
          ..._headers(),
        },
        body: jsonEncode(<String, dynamic>{'limit': limit, 'offset': offset}),
      );

      if (outcome.statusCode == 404) {
        if (hitCount == 0) {
          await _insertResultRow(
            runId: runId,
            row: _miss(
              company.name,
              'workday-api',
              _normalizeUrl(company.url),
              atsType: _AtsType.workday.name,
            ),
          );
          return _ScanSummary.miss();
        }
        break;
      }
      if (outcome.statusCode != 200) {
        if (hitCount == 0) {
          await _insertResultRow(
            runId: runId,
            row: _error(
              company: company.name,
              source: 'workday-api',
              applyLink: _normalizeUrl(company.url),
              error: 'HTTP ${outcome.statusCode}',
              atsType: _AtsType.workday.name,
            ),
          );
          return _ScanSummary.error('HTTP ${outcome.statusCode}');
        }
        break;
      }

      final body = jsonDecode(outcome.body) as Map<String, dynamic>;
      total =
          (body['total'] as num?)?.toInt() ??
          (body['totalCount'] as num?)?.toInt() ??
          total;

      final postings =
          (body['jobPostings'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
      if (postings.isEmpty) break;

      for (final job in postings) {
        final title = (job['title'] ?? '').toString().trim();
        if (!_isInternshipMatch(title, keywords, excludes)) continue;
        final location = (job['locationsText'] ?? 'Not specified').toString();
        final externalPath = (job['externalPath'] ?? '').toString();
        final link = externalPath.isEmpty
            ? _normalizeUrl(company.url)
            : endpoint.resolve(externalPath).toString();

        final inserted = await _insertHit(
          runId: runId,
          company: company.name,
          title: title,
          location: location,
          source: 'workday-api',
          applyLink: link,
          atsType: _AtsType.workday.name,
          historicalSeen: historicalSeen,
          runInsertedKeys: runInsertedKeys,
        );
        if (inserted) {
          hitCount++;
          preview = title;
        }
      }

      offset += limit;
    }

    if (hitCount == 0) {
      await _insertResultRow(
        runId: runId,
        row: _miss(
          company.name,
          'workday-api',
          _normalizeUrl(company.url),
          atsType: _AtsType.workday.name,
        ),
      );
      return _ScanSummary.miss();
    }
    return _ScanSummary.hit(hitCount, preview);
  }

  Future<_ScanSummary> _scanCoinbase({
    required String runId,
    required CompanyRow company,
    required List<String> keywords,
    required List<String> excludes,
    required Set<String> historicalSeen,
    required Set<String> runInsertedKeys,
  }) async {
    var page = 1;
    var hitCount = 0;
    var preview = 'opening';

    while (page <= 50) {
      final endpoint = Uri.parse(
        'https://www.coinbase.com/en-in/careers/positions?pageNumber=$page',
      );
      final outcome = await _requestWithRetry(_HttpMethod.get, endpoint);
      if (outcome.statusCode == 404) break;
      if (outcome.statusCode == 403) break;
      if (outcome.statusCode != 200) {
        if (hitCount == 0) {
          await _insertResultRow(
            runId: runId,
            row: _error(
              company: company.name,
              source: 'coinbase',
              applyLink: endpoint.toString(),
              error: 'HTTP ${outcome.statusCode}',
              atsType: _AtsType.coinbase.name,
            ),
          );
          return _ScanSummary.error('HTTP ${outcome.statusCode}');
        }
        break;
      }

      final jobs = _extractCoinbaseJobs(outcome.body, endpoint);
      if (jobs.isEmpty) break;

      for (final job in jobs) {
        final title = (job['title'] ?? '').toString().trim();
        if (!_isInternshipMatch(title, keywords, excludes)) continue;
        final location = (job['location'] ?? 'Not specified').toString();
        final link = (job['url'] ?? endpoint.toString()).toString();

        final inserted = await _insertHit(
          runId: runId,
          company: company.name,
          title: title,
          location: location,
          source: 'coinbase',
          applyLink: link,
          atsType: _AtsType.coinbase.name,
          historicalSeen: historicalSeen,
          runInsertedKeys: runInsertedKeys,
        );
        if (inserted) {
          hitCount++;
          preview = title;
        }
      }

      page++;
    }

    if (hitCount == 0) {
      await _insertResultRow(
        runId: runId,
        row: _miss(
          company.name,
          'coinbase',
          'https://www.coinbase.com/en-in/careers/positions?pageNumber=1',
          atsType: _AtsType.coinbase.name,
        ),
      );
      return _ScanSummary.miss();
    }
    return _ScanSummary.hit(hitCount, preview);
  }

  Future<_ScanSummary> _scanCustom({
    required String runId,
    required CompanyRow company,
    required Uri uri,
    required List<String> keywords,
    required List<String> excludes,
    required Set<String> historicalSeen,
    required Set<String> runInsertedKeys,
    bool writeTerminalMiss = true,
  }) async {
    final first = await _requestWithRetry(_HttpMethod.get, uri);
    if (first.statusCode == 403 || first.body.trim().isEmpty) {
      if (writeTerminalMiss) {
        await _insertJsFallback(
          runId: runId,
          company: company.name,
          url: uri.toString(),
          reason: 'JS_RENDERED',
        );
        await _insertResultRow(
          runId: runId,
          row: _miss(
            company.name,
            _hostOf(uri.toString()),
            uri.toString(),
            atsType: _AtsType.custom.name,
          ),
        );
      }
      return _ScanSummary.miss();
    }

    final firstPageJobElements = _jobElementCount(first.body);
    if (firstPageJobElements == 0) {
      if (writeTerminalMiss) {
        await _insertJsFallback(
          runId: runId,
          company: company.name,
          url: uri.toString(),
          reason: 'JS_RENDERED_NO_JOB_NODES',
        );
        await _insertResultRow(
          runId: runId,
          row: _miss(
            company.name,
            _hostOf(uri.toString()),
            uri.toString(),
            atsType: _AtsType.custom.name,
          ),
        );
      }
      return _ScanSummary.miss();
    }

    final pagination = _detectPagination(first.body, uri, firstPageJobElements);
    final maxPages = min(pagination.maxPages, 50);

    var page = 1;
    var hitCount = 0;
    var preview = 'opening';

    while (page <= maxPages) {
      final pageUri = page == 1
          ? uri
          : _buildPageUri(
              uri,
              pagination.paramName,
              page,
              firstPageJobElements,
            );
      final res = page == 1
          ? first
          : await _requestWithRetry(_HttpMethod.get, pageUri);

      if (page > 1 && (res.statusCode == 404 || res.statusCode == 403)) {
        break;
      }
      if (res.statusCode != 200) {
        if (hitCount == 0 && page == 1) {
          if (writeTerminalMiss) {
            await _insertResultRow(
              runId: runId,
              row: _error(
                company: company.name,
                source: _hostOf(uri.toString()),
                applyLink: uri.toString(),
                error: 'HTTP ${res.statusCode}',
                atsType: _AtsType.custom.name,
              ),
            );
          }
          return _ScanSummary.error('HTTP ${res.statusCode}');
        }
        break;
      }

      final elementCount = _jobElementCount(res.body);
      if (elementCount == 0) {
        if (page == 1 && writeTerminalMiss) {
          await _insertJsFallback(
            runId: runId,
            company: company.name,
            url: uri.toString(),
            reason: 'JS_RENDERED_AFTER_PARSE',
          );
        }
        break;
      }

      final candidates = _extractCustomJobCandidates(res.body, pageUri);
      var matchedOnPage = 0;
      for (final c in candidates) {
        final title = (c['title'] ?? '').toString().trim();
        if (!_isInternshipMatch(title, keywords, excludes)) continue;
        final location = _detectLocation(
          '${res.body.toLowerCase()} ${title.toLowerCase()}',
        );
        final link = (c['url'] ?? pageUri.toString()).toString();

        final inserted = await _insertHit(
          runId: runId,
          company: company.name,
          title: title,
          location: location,
          source: _hostOf(uri.toString()),
          applyLink: link,
          atsType: _AtsType.custom.name,
          historicalSeen: historicalSeen,
          runInsertedKeys: runInsertedKeys,
        );
        if (inserted) {
          matchedOnPage++;
          hitCount++;
          preview = title;
        }
      }

      if (page > 1 && matchedOnPage == 0 && elementCount == 0) {
        break;
      }

      if (!pagination.hasPagination) {
        break;
      }
      page++;
    }

    if (hitCount == 0) {
      if (writeTerminalMiss) {
        await _insertResultRow(
          runId: runId,
          row: _miss(
            company.name,
            _hostOf(uri.toString()),
            uri.toString(),
            atsType: _AtsType.custom.name,
          ),
        );
      }
      return _ScanSummary.miss();
    }

    return _ScanSummary.hit(hitCount, preview);
  }

  Future<bool> _insertHit({
    required String runId,
    required String company,
    required String title,
    required String location,
    required String source,
    required String applyLink,
    String? duration,
    required String atsType,
    required Set<String> historicalSeen,
    required Set<String> runInsertedKeys,
  }) async {
    final key = _hitKey(<String, dynamic>{
      'company': company,
      'title': title,
      'applyLink': applyLink,
    });
    if (runInsertedKeys.contains(key)) return false;

    final seenBefore = historicalSeen.contains(key);
    runInsertedKeys.add(key);

    await _insertResultRow(
      runId: runId,
      row: <String, dynamic>{
        ..._hit(
          company: company,
          title: title,
          location: location,
          source: source,
          applyLink: applyLink,
          duration: duration,
          atsType: atsType,
        ),
        'isSeenBefore': seenBefore,
        'isNew': !seenBefore,
      },
    );
    return true;
  }

  Future<void> _insertResultRow({
    required String runId,
    required Map<String, dynamic> row,
  }) async {
    await _ensureDb();
    final db = _db!;
    await db.insert('scraped_jobs', <String, Object?>{
      'run_id': runId,
      'company': row['company']?.toString() ?? '',
      'title': row['title']?.toString() ?? '',
      'location': row['location']?.toString() ?? '',
      'url': row['applyLink']?.toString() ?? '',
      'ats_type': row['atsType']?.toString() ?? _AtsType.custom.name,
      'scraped_at': DateTime.now().toIso8601String(),
      'bucket': row['bucket']?.toString() ?? 'miss',
      'source': row['source']?.toString() ?? '',
      'duration': row['duration']?.toString() ?? '',
      'error': row['error']?.toString() ?? '',
      'is_new': (row['isNew'] == true) ? 1 : 0,
      'is_seen_before': (row['isSeenBefore'] == true) ? 1 : 0,
    });
  }

  Future<void> _insertJsFallback({
    required String runId,
    required String company,
    required String url,
    required String reason,
  }) async {
    await _ensureDb();
    await _db!.insert('js_fallback_sites', <String, Object?>{
      'run_id': runId,
      'company': company,
      'url': url,
      'reason': reason,
      'scraped_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> _readRunRows(String runId) async {
    await _ensureDb();
    final rows = await _db!.query(
      'scraped_jobs',
      where: 'run_id = ?',
      whereArgs: <Object>[runId],
      orderBy: 'id DESC',
    );
    return rows
        .map(
          (r) => <String, dynamic>{
            'company': r['company'] ?? '',
            'bucket': r['bucket'] ?? 'miss',
            'title': r['title'] ?? '—',
            'location': r['location'] ?? '—',
            'duration': r['duration'] ?? '${DateTime.now().year} intake',
            'source': r['source'] ?? '',
            'applyLink': r['url'] ?? '',
            'error': r['error'] ?? '',
            'isNew': (r['is_new'] as int? ?? 0) == 1,
            'isSeenBefore': (r['is_seen_before'] as int? ?? 0) == 1,
          },
        )
        .toList(growable: false);
  }

  Future<void> _ensureStoreLoaded() async {
    if (_storeLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _persistedSeenHits =
        prefs.getStringList(_seenHitsKey)?.toSet() ?? <String>{};
    _storeLoaded = true;
  }

  Future<void> _ensureDb() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'nexus_scraper_v2.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE scraped_jobs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id TEXT NOT NULL,
            company TEXT NOT NULL,
            title TEXT NOT NULL,
            location TEXT NOT NULL,
            url TEXT NOT NULL,
            ats_type TEXT NOT NULL,
            scraped_at TEXT NOT NULL,
            bucket TEXT NOT NULL,
            source TEXT NOT NULL,
            duration TEXT NOT NULL,
            error TEXT NOT NULL,
            is_new INTEGER NOT NULL DEFAULT 0,
            is_seen_before INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE js_fallback_sites (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id TEXT NOT NULL,
            company TEXT NOT NULL,
            url TEXT NOT NULL,
            reason TEXT NOT NULL,
            scraped_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> _persistRunHits(String runId) async {
    await _ensureStoreLoaded();
    final rows = await _readRunRows(runId);
    final newKeys = rows
        .where((r) => r['bucket'] == 'hit')
        .map(_hitKey)
        .toSet();

    if (newKeys.isEmpty) return;

    _persistedSeenHits.addAll(newKeys);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_seenHitsKey, _persistedSeenHits.toList());
  }

  Future<_HttpOutcome> _requestWithRetry(
    _HttpMethod method,
    Uri uri, {
    Map<String, String>? headers,
    String? body,
  }) async {
    final mergedHeaders = <String, String>{..._headers(), ...?headers};
    var attempt = 0;

    while (attempt < _maxRetries) {
      await _respectRateLimit(uri);
      try {
        http.Response response;
        if (method == _HttpMethod.get) {
          response = await http
              .get(uri, headers: mergedHeaders)
              .timeout(_requestTimeout);
        } else {
          response = await http
              .post(uri, headers: mergedHeaders, body: body)
              .timeout(_requestTimeout);
        }

        if ((response.statusCode == 429 || response.statusCode == 503) &&
            attempt < _maxRetries - 1) {
          final wait = Duration(seconds: 2 * (1 << attempt));
          await Future<void>.delayed(wait);
          attempt++;
          continue;
        }

        return _HttpOutcome(
          statusCode: response.statusCode,
          body: response.body,
        );
      } catch (_) {
        if (attempt >= _maxRetries - 1) {
          rethrow;
        }
        final wait = Duration(seconds: 2 * (1 << attempt));
        await Future<void>.delayed(wait);
        attempt++;
      }
    }

    return _HttpOutcome(statusCode: 599, body: 'request failed');
  }

  Future<void> _respectRateLimit(Uri uri) async {
    final host = uri.host.toLowerCase();
    final previousChain = _hostRateLimitChains[host] ?? Future<void>.value();

    final completer = Completer<void>();
    _hostRateLimitChains[host] = completer.future;

    await previousChain;
    try {
      final now = DateTime.now();
      final previous = _lastRequestAtByHost[host];
      if (previous != null) {
        final delta = now.difference(previous);
        if (delta < _minRequestGap) {
          await Future<void>.delayed(_minRequestGap - delta);
        }
      }
      _lastRequestAtByHost[host] = DateTime.now();
    } finally {
      completer.complete();
    }
  }

  _AtsType _detectAtsType(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('lever.co')) return _AtsType.lever;
    if (lower.contains('ashbyhq.com')) return _AtsType.ashby;
    if (lower.contains('greenhouse.io')) return _AtsType.greenhouse;
    if (lower.contains('myworkdayjobs')) return _AtsType.workday;
    if (lower.contains('coinbase.com')) return _AtsType.coinbase;
    if (lower.contains('rippling.com')) return _AtsType.rippling;
    return _AtsType.custom;
  }

  List<Map<String, String>> _extractCoinbaseJobs(String html, Uri pageUri) {
    final jobs = <Map<String, String>>[];

    final cardMatches = RegExp(
      r'<div[^>]*data-testid="job-listing"[^>]*>([\s\S]*?)</div>',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in cardMatches) {
      final block = m.group(1) ?? '';
      final anchor = RegExp(r'href="([^"]+)"').firstMatch(block);
      final titleMatch = RegExp(r'>([^<>]{4,120})<').firstMatch(block);
      final rawHref = anchor?.group(1) ?? '';
      final title = _cleanText(titleMatch?.group(1) ?? 'Internship Opening');
      if (rawHref.isEmpty || title.isEmpty) continue;
      jobs.add(<String, String>{
        'title': title,
        'location': 'Not specified',
        'url': pageUri.resolve(rawHref).toString(),
      });
    }

    final nextData = RegExp(
      r'<script[^>]*id="__NEXT_DATA__"[^>]*>([\s\S]*?)</script>',
      caseSensitive: false,
    ).firstMatch(html);
    if (nextData != null) {
      try {
        final decoded = jsonDecode(nextData.group(1) ?? '{}');
        _collectCoinbaseJobsFromJson(decoded, pageUri, jobs);
      } catch (_) {
        // Ignore malformed JSON-LD payloads.
      }
    }

    final unique = <String, Map<String, String>>{};
    for (final j in jobs) {
      final key = '${j['title']}|${j['url']}';
      unique[key] = j;
    }
    return unique.values.toList(growable: false);
  }

  void _collectCoinbaseJobsFromJson(
    dynamic node,
    Uri base,
    List<Map<String, String>> out,
  ) {
    if (node is Map<String, dynamic>) {
      final title = (node['title'] ?? node['name'] ?? '').toString().trim();
      final rawUrl = (node['url'] ?? node['href'] ?? node['absolute_url'] ?? '')
          .toString()
          .trim();
      if (title.isNotEmpty && rawUrl.isNotEmpty) {
        out.add(<String, String>{
          'title': title,
          'location':
              (node['location'] ?? node['locationName'] ?? 'Not specified')
                  .toString(),
          'url': base.resolve(rawUrl).toString(),
        });
      }
      for (final v in node.values) {
        _collectCoinbaseJobsFromJson(v, base, out);
      }
      return;
    }

    if (node is List<dynamic>) {
      for (final item in node) {
        _collectCoinbaseJobsFromJson(item, base, out);
      }
    }
  }

  int _jobElementCount(String html) {
    final checks = <RegExp>[
      RegExp(r'data-testid="[^"]*job[^"]*"', caseSensitive: false),
      RegExp(r'class="[^"]*job-card[^"]*"', caseSensitive: false),
      RegExp(r'class="[^"]*job-listing[^"]*"', caseSensitive: false),
      RegExp(r'class="[^"]*position[^"]*"', caseSensitive: false),
      RegExp(
        r'<ul[^>]*class="[^"]*jobs[^"]*"[\s\S]*?<li',
        caseSensitive: false,
      ),
      RegExp(r'<a[^>]+href="[^"]*/jobs/[^"]*"', caseSensitive: false),
      RegExp(r'<a[^>]+href="[^"]*/careers/[^"]*"', caseSensitive: false),
      RegExp(r'<a[^>]+href="[^"]*/positions/[^"]*"', caseSensitive: false),
    ];

    for (final re in checks) {
      final count = re.allMatches(html).length;
      if (count > 0) return count;
    }
    return 0;
  }

  List<Map<String, String>> _extractCustomJobCandidates(
    String html,
    Uri pageUri,
  ) {
    final candidates = <Map<String, String>>[];

    final linkRegexes = <RegExp>[
      RegExp(
        r'<a[^>]+href="([^"]*?/jobs/[^"]*)"[^>]*>([\s\S]{1,120}?)</a>',
        caseSensitive: false,
      ),
      RegExp(
        r'<a[^>]+href="([^"]*?/careers/[^"]*)"[^>]*>([\s\S]{1,120}?)</a>',
        caseSensitive: false,
      ),
      RegExp(
        r'<a[^>]+href="([^"]*?/positions/[^"]*)"[^>]*>([\s\S]{1,120}?)</a>',
        caseSensitive: false,
      ),
    ];

    for (final re in linkRegexes) {
      final matches = re.allMatches(html);
      for (final m in matches) {
        final href = (m.group(1) ?? '').trim();
        final rawTitle = _cleanText(m.group(2) ?? '');
        final title = rawTitle.isEmpty ? 'Internship Opportunity' : rawTitle;
        if (href.isEmpty) continue;
        candidates.add(<String, String>{
          'title': title,
          'url': pageUri.resolve(href).toString(),
        });
      }
      if (candidates.isNotEmpty) break;
    }

    return candidates;
  }

  _PaginationPlan _detectPagination(
    String html,
    Uri baseUri,
    int firstPageJobCount,
  ) {
    String paramName = 'page';
    var hasPagination = false;
    var maxPages = 1;

    final paramMatch = RegExp(
      r'href="[^"]*[?&](page|p|start|offset)=',
      caseSensitive: false,
    ).firstMatch(html);
    if (paramMatch != null) {
      paramName = (paramMatch.group(1) ?? 'page').toLowerCase();
      hasPagination = true;
    }

    if (!hasPagination &&
        RegExp(
          r'>\s*(Next|Next Page|›|→)\s*<',
          caseSensitive: false,
        ).hasMatch(html)) {
      hasPagination = true;
      paramName = 'page';
    }

    if (!hasPagination) {
      final relNext = RegExp(
        r'<link[^>]*rel="next"[^>]*href="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(html);
      if (relNext != null) {
        hasPagination = true;
        final uri = baseUri.resolve(relNext.group(1) ?? '');
        final queryNames = uri.queryParameters.keys.toList(growable: false);
        if (queryNames.isNotEmpty) {
          paramName = queryNames.first;
        }
      }
    }

    if (!hasPagination) {
      final pageOf = RegExp(
        r'page\s+\d+\s+of\s+(\d+)',
        caseSensitive: false,
      ).firstMatch(html);
      if (pageOf != null) {
        hasPagination = true;
        maxPages = int.tryParse(pageOf.group(1) ?? '1') ?? 1;
      }
    }

    if (!hasPagination) {
      final showing = RegExp(
        r'showing\s+\d+\s+of\s+(\d+)',
        caseSensitive: false,
      ).firstMatch(html);
      if (showing != null) {
        hasPagination = true;
        final total = int.tryParse(showing.group(1) ?? '0') ?? 0;
        if (total > 0 && firstPageJobCount > 0) {
          maxPages = (total / firstPageJobCount).ceil();
        }
      }
    }

    if (hasPagination && maxPages < 2) {
      maxPages = 50;
    }

    return _PaginationPlan(
      hasPagination: hasPagination,
      paramName: paramName,
      maxPages: maxPages,
    );
  }

  Uri _buildPageUri(Uri base, String param, int page, int firstPageCount) {
    final query = Map<String, String>.from(base.queryParameters);
    if (param == 'offset' || param == 'start') {
      final size = firstPageCount <= 0 ? 20 : firstPageCount;
      query[param] = ((page - 1) * size).toString();
    } else {
      query[param] = page.toString();
    }
    return base.replace(queryParameters: query);
  }

  bool _isInternshipMatch(
    String title,
    List<String> keywords,
    List<String> excludes,
  ) {
    final lower = title.toLowerCase();
    final hasKeyword = keywords.any((k) => k.isNotEmpty && lower.contains(k));
    final hasExclude = excludes.any((e) => e.isNotEmpty && lower.contains(e));
    return hasKeyword && !hasExclude;
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
    final text = lowerHtml.toLowerCase();
    if (text.contains('remote')) return 'Remote';
    if (text.contains('bangalore') || text.contains('bengaluru')) {
      return 'Bengaluru';
    }
    if (text.contains('hyderabad')) return 'Hyderabad';
    if (text.contains('pune')) return 'Pune';
    if (text.contains('mumbai')) return 'Mumbai';
    if (text.contains('delhi')) return 'Delhi';
    if (text.contains('new york')) return 'New York';
    if (text.contains('london')) return 'London';
    return 'Not specified';
  }

  static String _cleanText(String raw) {
    return raw
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _lastPathSegment(Uri uri) {
    final seg = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
    if (seg.isEmpty) return '';
    return seg.last.trim();
  }

  static List<String> _ashbySlugCandidates(Uri uri) {
    final raw = _lastPathSegment(uri).trim().toLowerCase();
    if (raw.isEmpty) return const <String>[];

    final candidates = <String>{raw};
    final noSlash = raw.replaceAll('/', '');
    if (noSlash.isNotEmpty) {
      candidates.add(noSlash);
    }

    // Common case: boards like flashbots.net sometimes need flashbots fallback.
    if (raw.contains('.')) {
      final left = raw.split('.').first.trim();
      if (left.isNotEmpty) {
        candidates.add(left);
      }
    }

    return candidates.toList(growable: false);
  }

  List<Map<String, String>> _extractAshbyJobsFromHtml(String html, Uri base) {
    final out = <Map<String, String>>[];

    final anchorMatches = RegExp(
      r'<a[^>]+href="([^"]+)"[^>]*>([\s\S]{1,180}?)</a>',
      caseSensitive: false,
    ).allMatches(html);

    for (final m in anchorMatches) {
      final href = (m.group(1) ?? '').trim();
      if (href.isEmpty) continue;
      final title = _cleanText(m.group(2) ?? '');
      if (title.isEmpty) continue;
      final link = base.resolve(href).toString();
      if (!link.contains('/jobs/') && !link.contains('/job/')) continue;
      out.add(<String, String>{'title': title, 'url': link});
    }

    final jsonUrlMatches = RegExp(
      r'"jobUrl"\s*:\s*"([^"]+)"',
      caseSensitive: false,
    ).allMatches(html);
    for (final m in jsonUrlMatches) {
      final link = base.resolve(m.group(1) ?? '').toString();
      if (link.isEmpty) continue;
      out.add(<String, String>{'title': 'Internship Opportunity', 'url': link});
    }

    final unique = <String, Map<String, String>>{};
    for (final e in out) {
      unique['${e['title']}|${e['url']}'] = e;
    }
    return unique.values.toList(growable: false);
  }

  static String _firstPathSegment(Uri uri) {
    final seg = uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
    if (seg.isEmpty) return '';
    return seg.first.trim();
  }

  static String? _segmentAfter(List<String> segments, String marker) {
    final idx = segments.indexOf(marker);
    if (idx < 0 || idx + 1 >= segments.length) return null;
    return segments[idx + 1];
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
      'user-agent': _rateLimitUserAgent,
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

  static String _newRunId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final suffix = Random().nextInt(99999).toString().padLeft(5, '0');
    return 'run-$ts-$suffix';
  }

  Map<String, dynamic> _hit({
    required String company,
    required String title,
    required String location,
    required String source,
    required String applyLink,
    String? duration,
    required String atsType,
  }) {
    return <String, dynamic>{
      'company': company,
      'bucket': 'hit',
      'title': title,
      'location': location,
      'duration': (duration == null || duration.trim().isEmpty)
          ? '${DateTime.now().year} intake'
          : duration,
      'source': source,
      'applyLink': applyLink,
      'error': '',
      'atsType': atsType,
      'isNew': false,
      'isSeenBefore': false,
    };
  }

  Map<String, dynamic> _miss(
    String company,
    String source,
    String applyLink, {
    required String atsType,
  }) {
    return <String, dynamic>{
      'company': company,
      'bucket': 'miss',
      'title': '—',
      'location': '—',
      'duration': '${DateTime.now().year} intake',
      'source': source,
      'applyLink': applyLink,
      'error': '',
      'atsType': atsType,
      'isNew': false,
      'isSeenBefore': false,
    };
  }

  Map<String, dynamic> _error({
    required String company,
    required String source,
    required String applyLink,
    required String error,
    required String atsType,
  }) {
    return <String, dynamic>{
      'company': company,
      'bucket': 'error',
      'title': '—',
      'location': '—',
      'duration': '${DateTime.now().year} intake',
      'source': source,
      'applyLink': applyLink,
      'error': error,
      'atsType': atsType,
      'isNew': false,
      'isSeenBefore': false,
    };
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

enum _HttpMethod { get, post }

class _HttpOutcome {
  _HttpOutcome({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

enum _AtsType { lever, ashby, greenhouse, workday, coinbase, rippling, custom }

class _PaginationPlan {
  _PaginationPlan({
    required this.hasPagination,
    required this.paramName,
    required this.maxPages,
  });

  final bool hasPagination;
  final String paramName;
  final int maxPages;
}

class _ScanSummary {
  _ScanSummary({
    required this.hits,
    required this.errors,
    required this.previewTitle,
    required this.errorText,
  });

  factory _ScanSummary.hit(int hits, String title) {
    return _ScanSummary(
      hits: hits,
      errors: 0,
      previewTitle: title,
      errorText: '',
    );
  }

  factory _ScanSummary.miss() {
    return _ScanSummary(
      hits: 0,
      errors: 0,
      previewTitle: 'opening',
      errorText: '',
    );
  }

  factory _ScanSummary.error(String message) {
    return _ScanSummary(
      hits: 0,
      errors: 1,
      previewTitle: 'opening',
      errorText: message,
    );
  }

  final int hits;
  final int errors;
  final String previewTitle;
  final String errorText;
}

class _LocalRunState {
  _LocalRunState({
    required this.id,
    required this.companies,
    required this.keywords,
    required this.excludes,
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
  final int scanLimit;
  final int concurrency;

  int processedCompanies = 0;
  int errorCompanies = 0;

  final List<Map<String, dynamic>> events = <Map<String, dynamic>>[];

  int _nextEventIndex = 0;
}
