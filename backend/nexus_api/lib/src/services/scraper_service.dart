import 'dart:async';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'career_discovery.dart';
import 'extractor.dart';
import 'rate_limiter.dart';
import 'robots_checker.dart';

class ScraperService {
  ScraperService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final RateLimiter _limiter = RateLimiter(callsPerSecond: 0.5);
  final JobExtractor _extractor = JobExtractor();

  static const userAgents = <String>[
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Mobile/15E148 Safari/604.1',
  ];

  Future<List<ScanResultRow>> scrapeCompany(
    CompanyInput company,
    ScanConfig config,
  ) async {
    final base = _normalize(company.url);
    final uri = Uri.parse(base);

    final robotAllowed = await robotsOk(_client, uri);
    if (!robotAllowed) {
      return [
        ScanResultRow(
          company: company.name,
          title: '—',
          companyUrl: base,
          applyLink: base,
          location: '—',
          duration: '—',
          deadline: '—',
          source: '—',
          error: 'robots.txt disallowed',
        ),
      ];
    }

    final careerUri = await discoverCareerUrl(_client, uri);
    final html = await _fetch(careerUri);
    if (html == null || html.trim().isEmpty) {
      return [
        ScanResultRow(
          company: company.name,
          title: '—',
          companyUrl: base,
          applyLink: careerUri.toString(),
          location: '—',
          duration: '—',
          deadline: '—',
          source: '—',
          error: 'Fetch failed',
        ),
      ];
    }

    final rows = _extractor.extract(
      html: html,
      sourceUrl: careerUri,
      company: company.name,
      terms: config.keywords,
      excludes: config.excludeKeywords,
      maxMonths: config.maxDurationMonths,
    );

    if (rows.isEmpty) {
      return [
        ScanResultRow(
          company: company.name,
          title: 'No internship found',
          companyUrl: base,
          applyLink: careerUri.toString(),
          location: '—',
          duration: '—',
          deadline: '—',
          source: '—',
          error: '',
        ),
      ];
    }
    return rows;
  }

  Future<String?> _fetch(Uri uri) async {
    final domain = uri.host;
    await _limiter.wait(domain);

    try {
      final response = await _client
          .get(
            uri,
            headers: {
              'User-Agent':
                  userAgents[DateTime.now().millisecond % userAgents.length],
              'Accept-Language': 'en-US,en;q=0.9',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'DNT': '1',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 429) {
        _limiter.penalize(domain);
        return null;
      }
      if (response.statusCode >= 400) {
        return null;
      }
      _limiter.reset(domain);
      return response.body;
    } catch (_) {
      return null;
    }
  }

  String _normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }
}
