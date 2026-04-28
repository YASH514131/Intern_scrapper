import 'dart:async';
import 'dart:io';

import 'package:nexus_mobile/src/local_scraper/models.dart';
import 'package:nexus_mobile/src/local_scraper/services/scraper_service.dart';

const _defaultKeywords = <String>[
  'intern',
  'internship',
  'trainee',
  'co-op',
  'apprentice',
];

const _defaultExcludes = <String>[
  'senior',
  'staff',
  'director',
  'manager',
  'principal',
];

final _sampleCompanies = <CompanyInput>[
  CompanyInput(name: 'Amazon', url: 'https://www.amazon.jobs/en/'),
  CompanyInput(name: 'Aon', url: 'https://jobs.aon.com'),
  CompanyInput(name: 'AMD', url: 'https://careers.amd.com/careers-home/jobs'),
  CompanyInput(name: '0x', url: 'https://0x.org/careers'),
];

class _Scenario {
  const _Scenario({
    required this.name,
    required this.callsPerSecond,
    required this.hardTimeoutSeconds,
  });

  final String name;
  final double callsPerSecond;
  final int hardTimeoutSeconds;
}

Future<void> main(List<String> args) async {
  final includeBaseline = args.contains('--with-baseline');

  final scenarios = <_Scenario>[
    if (includeBaseline)
      const _Scenario(
        name: 'baseline',
        callsPerSecond: 0.5,
        hardTimeoutSeconds: 40,
      ),
    const _Scenario(name: 'tuned', callsPerSecond: 0.8, hardTimeoutSeconds: 24),
  ];

  stdout.writeln(
    'Benchmarking local scraper with ${_sampleCompanies.length} companies...',
  );

  for (final scenario in scenarios) {
    final service = ScraperService(callsPerSecond: scenario.callsPerSecond);
    final config = ScanConfig(
      keywords: _defaultKeywords,
      excludeKeywords: _defaultExcludes,
      scanLimit: 1,
      concurrency: 1,
      enableJs: false,
      hardTimeoutSeconds: scenario.hardTimeoutSeconds,
    );

    var totalHits = 0;
    var totalErrors = 0;
    final elapsedByCompanyMs = <int>[];
    final totalWatch = Stopwatch()..start();

    stdout.writeln('');
    stdout.writeln(
      'Scenario ${scenario.name} '
      '(cps=${scenario.callsPerSecond}, timeout=${scenario.hardTimeoutSeconds}s)',
    );

    for (final company in _sampleCompanies) {
      final watch = Stopwatch()..start();
      try {
        final rows = await service
            .scrapeCompany(company, config)
            .timeout(Duration(seconds: scenario.hardTimeoutSeconds + 5));

        final hits = rows.where((r) => r.bucket == ResultBucket.hit).length;
        final errors = rows.where((r) => r.bucket == ResultBucket.error).length;
        totalHits += hits;
        totalErrors += errors;

        watch.stop();
        elapsedByCompanyMs.add(watch.elapsedMilliseconds);

        stdout.writeln(
          ' - ${company.name.padRight(8)} '
          '${watch.elapsedMilliseconds}ms '
          'hits=$hits errors=$errors rows=${rows.length}',
        );
      } catch (e) {
        watch.stop();
        elapsedByCompanyMs.add(watch.elapsedMilliseconds);
        totalErrors += 1;
        stdout.writeln(
          ' - ${company.name.padRight(8)} '
          '${watch.elapsedMilliseconds}ms '
          'hits=0 errors=1 exception=$e',
        );
      }
    }

    totalWatch.stop();

    final avgMs = elapsedByCompanyMs.isEmpty
        ? 0
        : elapsedByCompanyMs.reduce((a, b) => a + b) ~/
              elapsedByCompanyMs.length;
    final fastestMs = elapsedByCompanyMs.isEmpty
        ? 0
        : elapsedByCompanyMs.reduce((a, b) => a < b ? a : b);
    final slowestMs = elapsedByCompanyMs.isEmpty
        ? 0
        : elapsedByCompanyMs.reduce((a, b) => a > b ? a : b);

    stdout.writeln(
      'Summary ${scenario.name}: total=${totalWatch.elapsedMilliseconds}ms '
      'avg=$avgMs ms fastest=$fastestMs ms slowest=$slowestMs ms '
      'hits=$totalHits errors=$totalErrors',
    );
  }

  stdout.writeln('');
  stdout.writeln('Done.');
}
