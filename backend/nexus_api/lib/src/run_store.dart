import 'dart:math';

import 'models.dart';

class RunStore {
  final _runs = <String, ScanRun>{};

  List<ScanRun> allRuns() {
    final values = _runs.values.toList();
    values.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return values;
  }

  ScanRun? getRun(String id) => _runs[id];

  ScanRun? previousCompletedRun(String runId) {
    final current = _runs[runId];
    if (current == null) return null;

    final candidates = _runs.values
        .where((r) => r.id != runId)
        .where((r) => r.status == RunStatus.complete)
        .where((r) => r.createdAt.isBefore(current.createdAt))
        .toList();
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return candidates.first;
  }

  ScanRun createRun({required int total, required ScanConfig config}) {
    final id = _newId();
    final run = ScanRun(
      id: id,
      createdAt: DateTime.now().toUtc(),
      status: RunStatus.queued,
      config: config,
      total: total,
      results: <ScanResultRow>[],
      events: <RunEvent>[],
    );
    _runs[id] = run;
    return run;
  }

  void setStatus(String runId, RunStatus status) {
    final run = _runs[runId];
    if (run == null) return;
    run.status = status;
  }

  void addResults(String runId, List<ScanResultRow> rows) {
    final run = _runs[runId];
    if (run == null) return;
    run.results.addAll(rows);
  }

  void addEvent(String runId, {required String kind, required String message}) {
    final run = _runs[runId];
    if (run == null) return;
    run.events.add(
      RunEvent(
        index: run.events.length,
        timestamp: DateTime.now().toUtc(),
        kind: kind,
        message: message,
        metrics: run.metrics,
      ),
    );
  }

  List<RunEvent> eventsAfter(String runId, int after) {
    final run = _runs[runId];
    if (run == null) return const [];
    return run.events.where((e) => e.index > after).toList();
  }

  String _newId() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 12; i++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }
}
