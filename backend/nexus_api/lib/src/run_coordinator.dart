import 'dart:async';

import 'models.dart';
import 'run_store.dart';
import 'services/scraper_service.dart';

class RunCoordinator {
  RunCoordinator({required this.store, required this.scraper});

  final RunStore store;
  final ScraperService scraper;

  void start(String runId, List<CompanyInput> companies, ScanConfig config) {
    unawaited(_execute(runId, companies, config));
  }

  Future<void> _execute(
    String runId,
    List<CompanyInput> companies,
    ScanConfig config,
  ) async {
    store.setStatus(runId, RunStatus.scanning);
    store.addEvent(
      runId,
      kind: 'info',
      message: 'Run started with ${companies.length} companies',
    );

    final pending = companies.take(config.scanLimit).toList();
    final concurrency = config.concurrency < 1 ? 1 : config.concurrency;
    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        if (cursor >= pending.length) return;
        final idx = cursor;
        cursor += 1;
        final company = pending[idx];

        try {
          final rows = await scraper
              .scrapeCompany(company, config)
              .timeout(Duration(seconds: config.hardTimeoutSeconds));
          store.addResults(runId, rows);
          final hits = rows.where((r) => r.bucket == ResultBucket.hit).length;
          if (hits > 0) {
            store.addEvent(
              runId,
              kind: 'hit',
              message: '[${company.name}] $hits position(s)',
            );
          } else {
            store.addEvent(
              runId,
              kind: 'miss',
              message: '[${company.name}] no listings',
            );
          }
        } on TimeoutException {
          store.addResults(runId, [
            ScanResultRow(
              company: company.name,
              title: '—',
              companyUrl: company.url,
              applyLink: company.url,
              location: '—',
              duration: '—',
              deadline: '—',
              source: '—',
              error: 'Timeout >${config.hardTimeoutSeconds}s',
            ),
          ]);
          store.addEvent(
            runId,
            kind: 'error',
            message: '[${company.name}] timeout',
          );
        } catch (e) {
          store.addResults(runId, [
            ScanResultRow(
              company: company.name,
              title: '—',
              companyUrl: company.url,
              applyLink: company.url,
              location: '—',
              duration: '—',
              deadline: '—',
              source: '—',
              error: e.toString(),
            ),
          ]);
          store.addEvent(
            runId,
            kind: 'error',
            message: '[${company.name}] ${e.runtimeType}',
          );
        }
      }
    }

    final workers = List<Future<void>>.generate(concurrency, (_) => worker());
    await Future.wait(workers);

    store.setStatus(runId, RunStatus.complete);
    store.addEvent(runId, kind: 'info', message: 'Run completed');
  }
}
