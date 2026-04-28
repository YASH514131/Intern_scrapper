import 'package:nexus_api/src/services/scraper_service.dart';
import 'package:test/test.dart';

void main() {
  group('ScraperService.extractWorkdayTenantAndSite', () {
    test('parses /recruiting style myworkdaysite URL', () {
      final uri = Uri.parse(
        'https://wd3.myworkdaysite.com/recruiting/brevanhoward/BH_ExternalCareers',
      );

      final parsed = ScraperService.extractWorkdayTenantAndSite(uri);

      expect(parsed, isNotNull);
      expect(parsed!.tenant, 'brevanhoward');
      expect(parsed.site, 'BH_ExternalCareers');
    });

    test('parses root-site style myworkdayjobs URL', () {
      final uri = Uri.parse('https://bullish.wd3.myworkdayjobs.com/Bullish');

      final parsed = ScraperService.extractWorkdayTenantAndSite(uri);

      expect(parsed, isNotNull);
      expect(parsed!.tenant, 'bullish');
      expect(parsed.site, 'Bullish');
    });

    test('returns null for non-workday host', () {
      final uri = Uri.parse('https://careers.example.com/jobs');

      final parsed = ScraperService.extractWorkdayTenantAndSite(uri);

      expect(parsed, isNull);
    });

    test('returns null when workday path has no usable segments', () {
      final uri = Uri.parse('https://foo.wd3.myworkdayjobs.com/');

      final parsed = ScraperService.extractWorkdayTenantAndSite(uri);

      expect(parsed, isNull);
    });
  });
}
