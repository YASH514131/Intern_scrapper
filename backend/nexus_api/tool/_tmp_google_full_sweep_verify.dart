import 'package:nexus_api/src/models.dart';
import 'package:nexus_api/src/services/scraper_service.dart';

Future<void> main() async {
  final service = ScraperService();
  final defaults = ScanConfig.defaults();
  final rows = await service.scrapeCompany(
    CompanyInput(
      name: 'Google',
      url:
          'https://www.google.com/about/careers/applications/jobs/results?has_remote=true&location=India',
    ),
    ScanConfig(
      keywords: const ['software'],
      excludeKeywords: const [],
      scanLimit: defaults.scanLimit,
      concurrency: defaults.concurrency,
      enableJs: true,
      hardTimeoutSeconds: defaults.hardTimeoutSeconds,
    ),
  );

  final hits = rows
      .where((r) => (r.error).isEmpty && r.title != 'No internship found')
      .toList();
  final misses = rows.where((r) => r.title == 'No internship found').length;
  final errors = rows.where((r) => r.error.isNotEmpty).length;

  print(
    'rows=${rows.length} hits=${hits.length} misses=$misses errors=$errors',
  );
  for (final row in hits.take(25)) {
    print('HIT: ${row.title} | ${row.applyLink}');
  }
}
