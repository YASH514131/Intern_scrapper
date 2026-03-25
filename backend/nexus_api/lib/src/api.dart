import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'models.dart';
import 'run_coordinator.dart';
import 'run_store.dart';
import 'services/scraper_service.dart';

class NexusApi {
  NexusApi() : _store = RunStore(), _scraper = ScraperService() {
    _coordinator = RunCoordinator(store: _store, scraper: _scraper);
  }

  final RunStore _store;
  final ScraperService _scraper;
  late final RunCoordinator _coordinator;

  Handler get handler {
    final router = Router()
      ..get('/health', _health)
      ..get('/api/v1/runs', _listRuns)
      ..post('/api/v1/runs', _startRun)
      ..get('/api/v1/runs/<id>', _getRun)
      ..get('/api/v1/runs/<id>/events', _events)
      ..get('/api/v1/runs/<id>/results', _results)
      ..get('/api/v1/runs/<id>/export.csv', _exportCsv);

    return Pipeline()
        .addMiddleware(_cors)
        .addMiddleware(logRequests())
        .addHandler(router.call);
  }

  Response _health(Request req) {
    return _json({'ok': true, 'service': 'nexus_api'});
  }

  Future<Response> _startRun(Request req) async {
    try {
      final body = await req.readAsString();
      final input = StartRunRequest.fromJson(jsonObject(body));
      if (input.companies.isEmpty) {
        return _json({'error': 'No valid companies supplied'}, status: 400);
      }

      final run = _store.createRun(
        total: input.companies.length > input.config.scanLimit
            ? input.config.scanLimit
            : input.companies.length,
        config: input.config,
      );

      _store.addEvent(
        run.id,
        kind: 'info',
        message: r'$ nexus-scanner started',
      );
      _coordinator.start(run.id, input.companies, input.config);

      return _json({'run': run.toJson()}, status: 202);
    } catch (e) {
      return _json({'error': 'Invalid request: $e'}, status: 400);
    }
  }

  Response _listRuns(Request req) {
    final runs = _store.allRuns().map((r) => r.toJson()).toList();
    return _json({'runs': runs});
  }

  Response _getRun(Request req, String id) {
    final run = _store.getRun(id);
    if (run == null) {
      return _json({'error': 'Run not found'}, status: 404);
    }
    return _json({'run': run.toJson()});
  }

  Response _events(Request req, String id) {
    final run = _store.getRun(id);
    if (run == null) {
      return _json({'error': 'Run not found'}, status: 404);
    }

    final after = int.tryParse(req.url.queryParameters['after'] ?? '-1') ?? -1;
    final events = _store
        .eventsAfter(id, after)
        .map((e) => e.toJson())
        .toList();
    return _json({'events': events, 'status': run.status.name});
  }

  Response _results(Request req, String id) {
    final run = _store.getRun(id);
    if (run == null) {
      return _json({'error': 'Run not found'}, status: 404);
    }

    final previous = _store.previousCompletedRun(id);
    final previousHitKeys = previous == null
        ? <String>{}
        : previous.results
              .where((r) => r.bucket == ResultBucket.hit)
              .map(_resultKey)
              .toSet();

    var newCount = 0;

    final bucket = req.url.queryParameters['bucket'];
    final rows = run.results
        .where((r) {
          if (bucket == null || bucket.isEmpty) return true;
          return r.bucket.name == bucket;
        })
        .map((r) {
          final isNew = r.bucket == ResultBucket.hit &&
              (previous == null || !previousHitKeys.contains(_resultKey(r)));
          if (isNew) {
            newCount += 1;
          }
          return {...r.toJson(), 'isNew': isNew};
        })
        .toList();

    return _json({
      'results': rows,
      'metrics': run.metrics.toJson(),
      'comparison': {
        'baselineRunId': previous?.id,
        'newCount': newCount,
      },
    });
  }

  Response _exportCsv(Request req, String id) {
    final run = _store.getRun(id);
    if (run == null) {
      return _json({'error': 'Run not found'}, status: 404);
    }

    final out = StringBuffer();
    out.writeln(
      'Company,Title,Company URL,Apply Link,Location,Duration,Deadline,Source,Error,Bucket',
    );
    for (final row in run.results) {
      out.writeln(
        [
          row.company,
          row.title,
          row.companyUrl,
          row.applyLink,
          row.location,
          row.duration,
          row.deadline,
          row.source,
          row.error,
          row.bucket.name,
        ].map(_csvEscape).join(','),
      );
    }

    return Response.ok(
      out.toString(),
      headers: {
        'content-type': 'text/csv; charset=utf-8',
        'content-disposition': 'attachment; filename="nexus_$id.csv"',
      },
    );
  }

  static String _csvEscape(String input) {
    final safe = input.replaceAll('"', '""');
    if (safe.contains(',') || safe.contains('\n') || safe.contains('"')) {
      return '"$safe"';
    }
    return safe;
  }

  Response _json(Map<String, dynamic> body, {int status = 200}) {
    return Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

String _resultKey(ScanResultRow row) {
  final company = row.company.trim().toLowerCase();
  final title = row.title.trim().toLowerCase();
  final apply = row.applyLink.trim().toLowerCase();
  return '$company|$title|$apply';
}

Middleware get _cors => (innerHandler) {
  return (request) async {
    if (request.method == 'OPTIONS') {
      return Response.ok('', headers: _corsHeaders);
    }
    final response = await innerHandler(request);
    return response.change(headers: {...response.headers, ..._corsHeaders});
  };
};

const _corsHeaders = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'content-type, authorization',
};
