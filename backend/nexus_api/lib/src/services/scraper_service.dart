import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:puppeteer/puppeteer.dart' as pptr;
import '../models.dart';
import 'career_discovery.dart';
import 'extractor.dart';
import 'fuzzy_matcher.dart';
import 'parser_helpers.dart';
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

  static const _jobBoardHostHints = <String>[
    'careers.kula.ai',
    'kula.ai',
    'greenhouse.io',
    'lever.co',
    'workdayjobs.com',
    'myworkdayjobs.com',
    'ashbyhq.com',
    'smartrecruiters.com',
    'jobvite.com',
    'icims.com',
    'teamtailor.com',
    'recruitee.com',
    'bamboohr.com',
  ];

  static ({String tenant, String site})? extractWorkdayTenantAndSite(
    Uri careerUri,
  ) {
    final host = careerUri.host.toLowerCase();
    if (!host.contains('myworkdaysite.com') &&
        !host.contains('myworkdayjobs.com')) {
      return null;
    }

    final segments = careerUri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;

    final recruitingIndex = segments.indexWhere(
      (s) => s.toLowerCase() == 'recruiting',
    );
    if (recruitingIndex >= 0 && recruitingIndex + 2 < segments.length) {
      return (
        tenant: segments[recruitingIndex + 1],
        site: segments[recruitingIndex + 2],
      );
    }

    final hostLabels = careerUri.host
        .split('.')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (hostLabels.isEmpty) return null;
    return (tenant: hostLabels.first, site: segments.first);
  }

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
    final knownApiSeedUri = _selectKnownApiSeedUri(
      originalUri: uri,
      discoveredUri: careerUri,
    );

    final html = await _fetch(careerUri);
    String? renderedHtml;
    if (html == null || html.trim().isEmpty) {
      final apiRows = await _fetchKnownJsonApiRows(
        companyName: company.name,
        careerUri: knownApiSeedUri,
        keywords: config.keywords,
      );
      if (apiRows.isNotEmpty) {
        return apiRows;
      }

      if (config.enableJs) {
        renderedHtml = await _fetchRendered(careerUri);
      }
      if (renderedHtml != null && renderedHtml.trim().isNotEmpty) {
        final renderedRows = _extractor.extract(
          html: renderedHtml,
          sourceUrl: careerUri,
          company: company.name,
          terms: config.keywords,
        );
        if (renderedRows.isNotEmpty) {
          return renderedRows;
        }
      }
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

    final loweredHost = careerUri.host.toLowerCase();
    final shouldPrioritizeKnownApi =
        loweredHost.contains('awign.com') ||
        loweredHost.contains('bain.com') ||
        loweredHost.contains('darwinbox.in') ||
        loweredHost.contains('capitalonecareers.com') ||
        loweredHost.contains('capgemini.com') ||
        loweredHost.contains('myworkdaysite.com') ||
        loweredHost.contains('myworkdayjobs.com') ||
        loweredHost.contains('careers.breadfinancial.com') ||
        loweredHost.contains('bitso.com') ||
        loweredHost.contains('careers.blackline.com') ||
        loweredHost.contains('jobs.blockchaincapital.com') ||
        loweredHost.contains('block.xyz') ||
        loweredHost.contains('blockchain.com') ||
        loweredHost.contains('avature.net') ||
        loweredHost.contains('binance.com') ||
        loweredHost.contains('bitcoinsuisse.com') ||
        loweredHost.contains('greenhouse.io') ||
        loweredHost.contains('careers.bcg.com') ||
        loweredHost.contains('careers.bankofamerica.com') ||
        loweredHost.contains('oraclecloud.com') ||
        loweredHost.contains('workforcenow.adp.com') ||
        loweredHost.contains('acko.com') ||
        loweredHost.contains('cashfree.com') ||
        loweredHost.contains('artivatic.ai') ||
        loweredHost.contains('att.jobs') ||
        loweredHost.contains('careers.astrazeneca.com') ||
        loweredHost.contains('careers.blackrock.com') ||
        loweredHost.contains('careers.kula.ai') ||
        loweredHost.contains('jobs.apple.com') ||
        loweredHost.contains('jobs.lever.co') ||
        loweredHost.contains('jobs.ashbyhq.com') ||
        loweredHost.contains('chainlinklabs.com') ||
        loweredHost.contains('jobs.aon.com') ||
        loweredHost.contains('0x.org') ||
        loweredHost.contains('amazon.jobs') ||
        loweredHost.contains('careers.amd.com') ||
        loweredHost.contains('careers.amgen.com');
    if (shouldPrioritizeKnownApi) {
      final apiRows = await _fetchKnownJsonApiRows(
        companyName: company.name,
        careerUri: knownApiSeedUri,
        keywords: config.keywords,
      );
      if (apiRows.isNotEmpty) {
        return apiRows;
      }
    }

    final rows = _extractor.extract(
      html: html,
      sourceUrl: careerUri,
      company: company.name,
      terms: config.keywords,
    );

    if (rows.isEmpty) {
      final apiRows = await _fetchKnownJsonApiRows(
        companyName: company.name,
        careerUri: knownApiSeedUri,
        keywords: config.keywords,
      );
      if (apiRows.isNotEmpty) {
        return apiRows;
      }
    }

    if (rows.isEmpty && config.enableJs) {
      renderedHtml ??= await _fetchRendered(careerUri);
      if (renderedHtml != null && renderedHtml.trim().isNotEmpty) {
        final renderedRows = _extractor.extract(
          html: renderedHtml,
          sourceUrl: careerUri,
          company: company.name,
          terms: config.keywords,
        );
        if (renderedRows.isNotEmpty) {
          return renderedRows;
        }
      }
    }

    if (rows.isEmpty) {
      final linkSources = <String>[];
      if (html.trim().isNotEmpty) {
        linkSources.add(html);
      }
      if (renderedHtml != null && renderedHtml.trim().isNotEmpty) {
        linkSources.add(renderedHtml);
      }

      final candidates = _discoverLikelyJobBoardLinks(
        baseUrl: careerUri,
        sourceHtml: linkSources,
      );

      for (final candidate in candidates.take(3)) {
        final candidateHtml = await _fetch(candidate);
        if (candidateHtml != null && candidateHtml.trim().isNotEmpty) {
          final candidateRows = _extractor.extract(
            html: candidateHtml,
            sourceUrl: candidate,
            company: company.name,
            terms: config.keywords,
          );
          if (candidateRows.isNotEmpty) {
            return candidateRows;
          }
        }

        if (config.enableJs) {
          final candidateRendered = await _fetchRendered(candidate);
          if (candidateRendered != null &&
              candidateRendered.trim().isNotEmpty) {
            final candidateRows = _extractor.extract(
              html: candidateRendered,
              sourceUrl: candidate,
              company: company.name,
              terms: config.keywords,
            );
            if (candidateRows.isNotEmpty) {
              return candidateRows;
            }
          }
        }
      }
    }

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

  Future<String?> _fetchRendered(Uri uri) async {
    pptr.Browser? browser;
    try {
      browser = await pptr.puppeteer
          .launch(
            headless: true,
            args: const [
              '--no-sandbox',
              '--disable-setuid-sandbox',
              '--disable-dev-shm-usage',
              '--disable-gpu',
            ],
          )
          .timeout(const Duration(seconds: 15));

      final page = await browser.newPage().timeout(const Duration(seconds: 10));
      await page
          .setUserAgent(
            userAgents[DateTime.now().millisecond % userAgents.length],
          )
          .timeout(const Duration(seconds: 5));
      try {
        await page
            .goto(uri.toString(), wait: pptr.Until.networkIdle)
            .timeout(const Duration(seconds: 20));
      } catch (_) {
        await page
            .goto(uri.toString(), wait: pptr.Until.domContentLoaded)
            .timeout(const Duration(seconds: 10));
      }
      return await page.content.timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    } finally {
      await browser?.close();
    }
  }

  List<Uri> _discoverLikelyJobBoardLinks({
    required Uri baseUrl,
    required List<String> sourceHtml,
  }) {
    final out = <Uri>[];
    final seen = <String>{};

    bool isLikely(Uri uri) {
      final host = uri.host.toLowerCase();
      final path = uri.path.toLowerCase();
      final hintHost = _jobBoardHostHints.any(host.contains);
      final hintPath = [
        '/jobs',
        '/careers',
        '/positions',
        '/open-positions',
        '/job/',
      ].any(path.contains);
      return hintHost || hintPath;
    }

    void maybeAdd(String? raw) {
      if (raw == null || raw.trim().isEmpty) return;
      final resolved = baseUrl.resolve(raw.trim());
      if (!['http', 'https'].contains(resolved.scheme)) return;
      if (!isLikely(resolved)) return;
      final key = resolved.toString();
      if (seen.contains(key)) return;
      if (resolved.toString() == baseUrl.toString()) return;
      seen.add(key);
      out.add(resolved);
    }

    for (final html in sourceHtml) {
      final doc = html_parser.parse(html);
      for (final a in doc.querySelectorAll('a[href]')) {
        maybeAdd(a.attributes['href']);
      }
      for (final frame in doc.querySelectorAll('iframe[src]')) {
        maybeAdd(frame.attributes['src']);
      }
      for (final script in doc.querySelectorAll('script[src]')) {
        maybeAdd(script.attributes['src']);
      }
    }

    return out;
  }

  Uri _selectKnownApiSeedUri({
    required Uri originalUri,
    required Uri discoveredUri,
  }) {
    final discoveredHost = discoveredUri.host.toLowerCase();
    final originalHost = originalUri.host.toLowerCase();
    if (discoveredHost.contains('workforcenow.adp.com') &&
        originalHost.contains('workforcenow.adp.com')) {
      final discoveredPath = discoveredUri.path.toLowerCase();
      final originalPath = originalUri.path.toLowerCase();
      final hasCid = (originalUri.queryParameters['cid'] ?? '')
          .trim()
          .isNotEmpty;
      final isRecruitmentUrl = originalPath.contains('/mdf/recruitment/');
      if (discoveredPath == '/careers' && hasCid && isRecruitmentUrl) {
        return originalUri;
      }
    }

    if (discoveredHost.contains('jobs.apple.com') &&
        originalHost.contains('jobs.apple.com')) {
      final discoveredPath = discoveredUri.path.toLowerCase();
      final originalPath = originalUri.path.toLowerCase();
      if (discoveredPath.contains('/careers') &&
          originalPath.contains('/search')) {
        return originalUri;
      }
    }

    if (discoveredHost.contains('jobs.ashbyhq.com') &&
        originalHost.contains('jobs.ashbyhq.com')) {
      final discoveredPath = discoveredUri.path.toLowerCase();
      final originalSegments = originalUri.pathSegments
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if ((discoveredPath == '/careers' ||
              discoveredPath == '/' ||
              discoveredPath.isEmpty) &&
          originalSegments.isNotEmpty &&
          originalSegments.first.toLowerCase() != 'careers') {
        return originalUri;
      }
    }

    if (discoveredHost.contains('greenhouse.io') &&
        originalHost.contains('greenhouse.io')) {
      final discoveredSegments = discoveredUri.pathSegments
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final originalSegments = originalUri.pathSegments
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (discoveredSegments.length == 1 &&
          discoveredSegments.first.toLowerCase() == 'opportunities' &&
          originalSegments.isNotEmpty &&
          originalSegments.first.toLowerCase() != 'opportunities') {
        return originalUri;
      }
    }
    return discoveredUri;
  }

  Future<List<ScanResultRow>> _fetchKnownJsonApiRows({
    required String companyName,
    required Uri careerUri,
    required List<String> keywords,
  }) async {
    final host = careerUri.host.toLowerCase();

    if (host.contains('chainlinklabs.com')) {
      try {
        final pageResponse = await _client
            .get(
              careerUri,
              headers: {
                'accept':
                    'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'user-agent':
                    userAgents[DateTime.now().millisecond % userAgents.length],
              },
            )
            .timeout(const Duration(seconds: 12));

        if (pageResponse.statusCode >= 400 ||
            pageResponse.body.trim().isEmpty) {
          return const [];
        }

        final ashbyMatch = RegExp(
          r'jobs\.ashbyhq\.com/([a-zA-Z0-9\-]+)/?',
          caseSensitive: false,
        ).firstMatch(pageResponse.body);

        final board = ashbyMatch?.group(1)?.trim().isNotEmpty == true
            ? ashbyMatch!.group(1)!.trim()
            : 'chainlink-labs';

        return await _fetchAshbyRows(
          board: board,
          companyName: companyName,
          careerUri: careerUri,
          keywords: keywords,
        );
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('capitalonecareers.com') &&
        careerUri.path.toLowerCase().contains('/category/')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;
        final basePath = careerUri.path.endsWith('/')
            ? careerUri.path.substring(0, careerUri.path.length - 1)
            : careerUri.path;

        for (var page = 1; page <= 80; page++) {
          final pagePath = page == 1 ? basePath : '$basePath/$page';
          final pageUri = careerUri.replace(path: pagePath);

          final response = await _client
              .get(
                pageUri,
                headers: {
                  'accept':
                      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                  'user-agent':
                      userAgents[DateTime.now().millisecond %
                          userAgents.length],
                },
              )
              .timeout(const Duration(seconds: 15));

          if (response.statusCode >= 400 || response.body.trim().isEmpty) {
            if (page == 1) {
              return const [];
            }
            break;
          }

          final doc = html_parser.parse(response.body);
          final links = doc
              .querySelectorAll('a[href*="/job/"]')
              .where((a) => (a.attributes['href'] ?? '').trim().isNotEmpty)
              .toList();
          if (links.isEmpty) {
            break;
          }

          var pageAdded = 0;
          for (final a in links) {
            final href = (a.attributes['href'] ?? '').trim();
            final applyLink = pageUri.resolve(href).toString();
            final applyUri = Uri.tryParse(applyLink);
            if (applyUri == null) continue;

            final segments = applyUri.pathSegments
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            if (segments.length < 5 || segments.first.toLowerCase() != 'job') {
              continue;
            }

            final locationRaw = segments[1];
            final slug = segments[2];
            final slugText = slug.replaceAll('-', ' ').trim();
            if (slugText.isEmpty) continue;

            final title = slugText
                .split(' ')
                .where((w) => w.trim().isNotEmpty)
                .map(
                  (w) => w.length == 1
                      ? w.toUpperCase()
                      : '${w[0].toUpperCase()}${w.substring(1)}',
                )
                .join(' ');

            final titleLower = title.toLowerCase();
            final exactWordMatch = matchTerms.any((kw) {
              final pattern = RegExp(
                '\\b${RegExp.escape(kw.toLowerCase())}\\b',
              );
              return pattern.hasMatch(titleLower);
            });
            if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
              continue;
            }

            final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
            if (seen.contains(key)) continue;
            seen.add(key);
            pageAdded += 1;

            rows.add(
              ScanResultRow(
                company: companyName,
                title: title,
                companyUrl: careerUri.toString(),
                applyLink: applyLink,
                location: locationRaw.replaceAll('-', ' '),
                duration: parseDuration(title).$1,
                deadline: '—',
                source: 'Capital One Careers HTML',
                error: '',
              ),
            );
          }

          if (pageAdded == 0) {
            break;
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('capgemini.com') &&
        careerUri.path.toLowerCase().contains(
          '/careers/join-capgemini/job-search',
        )) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;

        final baseQuery = Map<String, String>.from(careerUri.queryParameters);
        final countryCode = (baseQuery['country_code'] ?? '').trim();
        final pageSize = int.tryParse(baseQuery['size'] ?? '') ?? 11;
        final startPage = 1;

        for (final term in matchTerms) {
          var page = startPage;
          var maxPage = startPage + 80;
          int? total;

          while (page <= maxPage) {
            final qp = <String, String>{
              'search': term,
              'size': '$pageSize',
              'page': '$page',
            };
            if (countryCode.isNotEmpty) {
              qp['country_code'] = countryCode;
            }

            final apiUri = Uri.https(
              'cg-jobstream-api.azurewebsites.net',
              '/api/job-search',
              qp,
            );

            final response = await _client
                .get(
                  apiUri,
                  headers: {
                    'accept': 'application/json, text/plain, */*',
                    'referer': careerUri.toString(),
                    'user-agent':
                        userAgents[DateTime.now().millisecond %
                            userAgents.length],
                  },
                )
                .timeout(const Duration(seconds: 15));

            if (response.statusCode >= 400 || response.body.trim().isEmpty) {
              break;
            }

            final decoded = jsonDecode(response.body);
            if (decoded is! Map) {
              break;
            }

            total ??= int.tryParse('${decoded['total'] ?? ''}');
            if (total != null && total! > 0) {
              final computedMaxPage = ((total! - 1) ~/ pageSize) + 1;
              if (computedMaxPage < maxPage) {
                maxPage = computedMaxPage;
              }
            }

            final jobs = (decoded['data'] is List)
                ? (decoded['data'] as List).whereType<Map>().toList()
                : const <Map>[];
            if (jobs.isEmpty) {
              break;
            }

            for (final item in jobs) {
              final map = item.map((k, v) => MapEntry(k.toString(), v));
              final title = (map['title'] ?? '').toString().trim();
              if (title.isEmpty) continue;

              final location = (map['location'] ?? '').toString().trim();
              final rawDescription =
                  '${map['description_stripped'] ?? map['description'] ?? ''}';
              final titleLower = title.toLowerCase();
              final locationLower = location.toLowerCase();
              final descriptionLower = rawDescription.toLowerCase();

              final exactWordMatch = matchTerms.any((kw) {
                final pattern = RegExp(
                  '\\b${RegExp.escape(kw.toLowerCase())}\\b',
                );
                return pattern.hasMatch(titleLower) ||
                    pattern.hasMatch(locationLower) ||
                    pattern.hasMatch(descriptionLower);
              });
              if (!exactWordMatch &&
                  !fuzzyMatch(titleLower, matchTerms) &&
                  !fuzzyMatch(descriptionLower, matchTerms)) {
                continue;
              }

              var applyLink = (map['apply_job_url'] ?? '').toString().trim();
              if (applyLink.isEmpty) {
                final ref = (map['ref'] ?? '').toString().trim();
                applyLink = ref.isNotEmpty
                    ? 'https://www.capgemini.com/jobs/$ref'
                    : careerUri.toString();
              }

              final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
              if (seen.contains(key)) continue;
              seen.add(key);

              rows.add(
                ScanResultRow(
                  company: companyName,
                  title: title,
                  companyUrl: careerUri.toString(),
                  applyLink: applyLink,
                  location: location.isEmpty ? 'Not specified' : location,
                  duration: parseDuration('$title $rawDescription').$1,
                  deadline: '—',
                  source: 'Capgemini Jobstream API',
                  error: '',
                ),
              );
            }

            if (jobs.length < pageSize) {
              break;
            }

            page += 1;
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('myworkdaysite.com') ||
        host.contains('myworkdayjobs.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;

        final workdayParams = extractWorkdayTenantAndSite(careerUri);
        if (workdayParams == null) {
          return const [];
        }

        final tenant = workdayParams.tenant;
        final site = workdayParams.site;

        final apiUri = Uri.https(
          careerUri.host,
          '/wday/cxs/$tenant/$site/jobs',
        );

        for (final term in matchTerms) {
          var offset = 0;
          const limit = 20;
          int? total;

          while (offset <= 300) {
            final payload = jsonEncode({
              'limit': limit,
              'offset': offset,
              'searchText': term,
            });

            final response = await _client
                .post(
                  apiUri,
                  headers: {
                    'accept': 'application/json, text/plain, */*',
                    'content-type': 'application/json',
                    'origin': '${careerUri.scheme}://${careerUri.host}',
                    'referer': careerUri.toString(),
                    'user-agent':
                        userAgents[DateTime.now().millisecond %
                            userAgents.length],
                  },
                  body: payload,
                )
                .timeout(const Duration(seconds: 15));

            if (response.statusCode >= 400 || response.body.trim().isEmpty) {
              break;
            }

            final decoded = jsonDecode(response.body);
            if (decoded is! Map) {
              break;
            }

            total ??= int.tryParse('${decoded['total'] ?? ''}');
            final jobs = (decoded['jobPostings'] is List)
                ? (decoded['jobPostings'] as List).whereType<Map>().toList()
                : const <Map>[];

            if (jobs.isEmpty) {
              break;
            }

            for (final item in jobs) {
              final map = item.map((k, v) => MapEntry(k.toString(), v));
              final title = (map['title'] ?? '').toString().trim();
              if (title.isEmpty) continue;

              final location = (map['locationsText'] ?? '').toString().trim();
              final postedOn = (map['postedOn'] ?? '').toString().trim();
              final titleLower = title.toLowerCase();
              final locationLower = location.toLowerCase();

              final exactWordMatch = matchTerms.any((kw) {
                final pattern = RegExp(
                  '\\b${RegExp.escape(kw.toLowerCase())}\\b',
                );
                return pattern.hasMatch(titleLower) ||
                    pattern.hasMatch(locationLower);
              });
              if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
                continue;
              }

              final externalPath = (map['externalPath'] ?? '')
                  .toString()
                  .trim();
              final applyLink = externalPath.isNotEmpty
                  ? careerUri.resolve(externalPath).toString()
                  : careerUri.toString();
              final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
              if (seen.contains(key)) continue;
              seen.add(key);

              rows.add(
                ScanResultRow(
                  company: companyName,
                  title: title,
                  companyUrl: careerUri.toString(),
                  applyLink: applyLink,
                  location: location.isEmpty ? 'Not specified' : location,
                  duration: parseDuration('$title $postedOn').$1,
                  deadline: '—',
                  source: 'Workday CXS Jobs API',
                  error: '',
                ),
              );
            }

            offset += limit;
            if (total != null && offset >= total!) {
              break;
            }
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('avature.net')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;
        final searchPath =
            careerUri.path.toLowerCase().contains('/search-results')
            ? careerUri.path
            : '/us/en/search-results';

        final baseQuery = Map<String, String>.from(careerUri.queryParameters);
        final recordsPerPage =
            int.tryParse(baseQuery['jobRecordsPerPage'] ?? '') ?? 12;

        var offset = int.tryParse(baseQuery['jobOffset'] ?? '') ?? 0;
        for (var page = 0; page < 60; page++) {
          final qp = Map<String, String>.from(baseQuery);
          qp['jobRecordsPerPage'] = '$recordsPerPage';
          if (offset > 0) {
            qp['jobOffset'] = '$offset';
          } else {
            qp.remove('jobOffset');
          }

          final pageUri = Uri.https(
            careerUri.host,
            careerUri.path,
            qp.isEmpty ? null : qp,
          );

          final response = await _client
              .get(
                pageUri,
                headers: {
                  'accept':
                      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                  'user-agent':
                      userAgents[DateTime.now().millisecond %
                          userAgents.length],
                },
              )
              .timeout(const Duration(seconds: 15));

          if (response.statusCode >= 400 || response.body.trim().isEmpty) {
            break;
          }

          final doc = html_parser.parse(response.body);
          final links = doc
              .querySelectorAll('a[href*="/careers/JobDetail/"]')
              .where((a) => (a.attributes['href'] ?? '').trim().isNotEmpty)
              .toList();
          if (links.isEmpty) {
            break;
          }

          var pageAdded = 0;
          for (final link in links) {
            final rawTitle = link.text.replaceAll(RegExp(r'\s+'), ' ').trim();
            if (rawTitle.isEmpty) continue;

            final titleLower = rawTitle.toLowerCase();
            if (titleLower == 'apply' || titleLower.startsWith('apply now')) {
              continue;
            }

            var contextText = rawTitle;
            html_dom.Element? node = link;
            for (var i = 0; i < 5 && node != null; i++) {
              final t = node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
              if (t.length > contextText.length) {
                contextText = t;
              }
              node = node.parent;
            }

            final contextLower = contextText.toLowerCase();
            final exactWordMatch = matchTerms.any((kw) {
              final pattern = RegExp(
                '\\b${RegExp.escape(kw.toLowerCase())}\\b',
              );
              return pattern.hasMatch(titleLower) ||
                  pattern.hasMatch(contextLower);
            });
            if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
              continue;
            }

            final href = (link.attributes['href'] ?? '').trim();
            final applyLink = pageUri.resolve(href).toString();
            final key = '${rawTitle.toLowerCase()}|${applyLink.toLowerCase()}';
            if (seen.contains(key)) continue;
            seen.add(key);

            pageAdded += 1;
            rows.add(
              ScanResultRow(
                company: companyName,
                title: rawTitle,
                companyUrl: careerUri.toString(),
                applyLink: applyLink,
                location: 'Not specified',
                duration: parseDuration(contextText).$1,
                deadline: '—',
                source: 'Avature Careers HTML',
                error: '',
              ),
            );
          }

          if (pageAdded == 0) {
            break;
          }

          if (links.length < recordsPerPage) {
            break;
          }

          offset += recordsPerPage;
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('blockchain.com')) {
      try {
        final response = await _client
            .get(
              Uri.parse(
                'https://boards-api.greenhouse.io/v1/boards/blockchain/jobs?content=true',
              ),
              headers: const {'accept': 'application/json, text/plain, */*'},
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode >= 400 || response.body.trim().isEmpty) {
          return const [];
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map || decoded['jobs'] is! List) {
          return const [];
        }

        final jobs = (decoded['jobs'] as List).whereType<Map>();
        final rows = <ScanResultRow>[];
        final seen = <String>{};

        for (final item in jobs) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));

          final title = (map['title'] ?? '').toString().trim();
          final content = (map['content'] ?? '').toString().trim();
          if (title.isEmpty) continue;

          final titleLower = title.toLowerCase();
          final contentLower = content.toLowerCase();
          final exactWordMatch = keywords.any((kw) {
            final pattern = RegExp('\\b${RegExp.escape(kw.toLowerCase())}\\b');
            return pattern.hasMatch(titleLower) ||
                pattern.hasMatch(contentLower);
          });
          if (!exactWordMatch && !fuzzyMatch(titleLower, keywords)) continue;

          final applyLink = (map['absolute_url'] ?? careerUri.toString())
              .toString()
              .trim();
          final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
          if (seen.contains(key)) continue;
          seen.add(key);

          String location = 'Not specified';
          final locationObj = map['location'];
          if (locationObj is Map) {
            final name = (locationObj['name'] ?? '').toString().trim();
            if (name.isNotEmpty) {
              location = name;
            }
          } else {
            final name = locationObj?.toString().trim() ?? '';
            if (name.isNotEmpty) {
              location = name;
            }
          }

          rows.add(
            ScanResultRow(
              company: companyName,
              title: title,
              companyUrl: careerUri.toString(),
              applyLink: applyLink,
              location: location,
              duration: parseDuration(content).$1,
              deadline: '—',
              source: 'Blockchain.com Greenhouse API',
              error: '',
            ),
          );
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('jobs.blockchaincapital.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;

        for (final term in matchTerms) {
          final queryUri = Uri.https('jobs.blockchaincapital.com', '/jobs', {
            'q': term,
          });
          final response = await _client
              .get(
                queryUri,
                headers: {
                  'accept':
                      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                  'user-agent':
                      userAgents[DateTime.now().millisecond %
                          userAgents.length],
                },
              )
              .timeout(const Duration(seconds: 15));

          if (response.statusCode >= 400 || response.body.trim().isEmpty) {
            continue;
          }

          final doc = html_parser.parse(response.body);
          final links = doc
              .querySelectorAll('a[href*="/companies/"][href*="/jobs/"]')
              .where(
                (a) => (a.attributes['href'] ?? '').toLowerCase().contains(
                  '/jobs/',
                ),
              )
              .toList();

          for (final link in links) {
            final href = (link.attributes['href'] ?? '').trim();
            if (href.isEmpty) continue;

            final title = link.text.replaceAll(RegExp(r'\s+'), ' ').trim();
            if (title.isEmpty || title.toLowerCase().startsWith('read more')) {
              continue;
            }

            final titleLower = title.toLowerCase();
            final exactWordMatch = matchTerms.any((kw) {
              final pattern = RegExp(
                '\\b${RegExp.escape(kw.toLowerCase())}\\b',
              );
              return pattern.hasMatch(titleLower);
            });
            if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
              continue;
            }

            final applyLink = queryUri.resolve(href).toString();
            final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
            if (seen.contains(key)) continue;
            seen.add(key);

            rows.add(
              ScanResultRow(
                company: companyName,
                title: title,
                companyUrl: careerUri.toString(),
                applyLink: applyLink,
                location: 'Not specified',
                duration: 'Unknown',
                deadline: '—',
                source: 'Blockchain Capital Getro Jobs',
                error: '',
              ),
            );
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('block.xyz')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;

        var page = 1;
        while (page <= 30) {
          final apiUri = Uri.https('block.xyz', '/api/careers/jobs', {
            'page': '$page',
          });

          final response = await _client
              .get(
                apiUri,
                headers: {
                  'accept': 'application/json, text/plain, */*',
                  'user-agent':
                      userAgents[DateTime.now().millisecond %
                          userAgents.length],
                  'referer': careerUri.toString(),
                },
              )
              .timeout(const Duration(seconds: 15));
          if (response.statusCode >= 400 || response.body.trim().isEmpty) {
            break;
          }

          final decoded = jsonDecode(response.body);
          if (decoded is! Map || decoded['currentPage'] is! List) {
            break;
          }

          final jobs = (decoded['currentPage'] as List).whereType<Map>();
          if (jobs.isEmpty) {
            break;
          }

          var pageAdded = 0;
          for (final item in jobs) {
            final map = item.map((k, v) => MapEntry(k.toString(), v));
            final title = (map['title'] ?? '').toString().trim();
            if (title.isEmpty) continue;

            final jobFunction = (map['jobFunction'] ?? '').toString().trim();
            final employeeType = (map['employeeType'] ?? '').toString().trim();
            final locationObj = map['location'];
            final location = locationObj is List
                ? locationObj
                      .map((e) => e.toString().trim())
                      .where((e) => e.isNotEmpty)
                      .toSet()
                      .join(', ')
                : locationObj?.toString().trim() ?? '';

            final searchable = [
              title,
              jobFunction,
              employeeType,
              location,
            ].where((e) => e.isNotEmpty).join(' | ').toLowerCase();
            final titleLower = title.toLowerCase();
            final exactWordMatch = matchTerms.any((kw) {
              final pattern = RegExp(
                '\\b${RegExp.escape(kw.toLowerCase())}\\b',
              );
              return pattern.hasMatch(searchable);
            });
            if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
              continue;
            }

            final id = (map['id'] ?? '').toString().trim();
            final applyLink = id.isNotEmpty
                ? Uri.https('block.xyz', '/careers/jobs/$id').toString()
                : careerUri.toString();
            final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
            if (seen.contains(key)) continue;
            seen.add(key);

            pageAdded += 1;
            rows.add(
              ScanResultRow(
                company: companyName,
                title: title,
                companyUrl: careerUri.toString(),
                applyLink: applyLink,
                location: location.isEmpty ? 'Not specified' : location,
                duration: parseDuration(searchable).$1,
                deadline: '—',
                source: 'Block Careers API',
                error: '',
              ),
            );
          }

          final total = int.tryParse((decoded['total'] ?? '').toString());
          if (total != null && page * jobs.length >= total) {
            break;
          }

          if (jobs.length < 50 && pageAdded == 0) {
            break;
          }

          page += 1;
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('bitso.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;

        final apiUri = Uri.https(
          'boards-api.greenhouse.io',
          '/v1/boards/bitso/jobs',
          {'content': 'true'},
        );
        final response = await _client
            .get(
              apiUri,
              headers: {
                'accept': 'application/json, text/plain, */*',
                'user-agent':
                    userAgents[DateTime.now().millisecond % userAgents.length],
                'referer': careerUri.toString(),
              },
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode >= 400 || response.body.trim().isEmpty) {
          return const [];
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map || decoded['jobs'] is! List) {
          return const [];
        }

        final jobs = (decoded['jobs'] as List).whereType<Map>();
        for (final item in jobs) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          final title = (map['title'] ?? '').toString().trim();
          final content = (map['content'] ?? '').toString().trim();
          if (title.isEmpty) continue;

          final titleLower = title.toLowerCase();
          final exactWordMatch = matchTerms.any((kw) {
            final pattern = RegExp('\\b${RegExp.escape(kw.toLowerCase())}\\b');
            return pattern.hasMatch(titleLower);
          });
          if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
            continue;
          }

          final rawLink = (map['absolute_url'] ?? '').toString().trim();
          final applyLink = rawLink.isNotEmpty ? rawLink : careerUri.toString();
          final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
          if (seen.contains(key)) continue;
          seen.add(key);

          String location = 'Not specified';
          final locationObj = map['location'];
          if (locationObj is Map) {
            final name = (locationObj['name'] ?? '').toString().trim();
            if (name.isNotEmpty) {
              location = name;
            }
          } else {
            final name = locationObj?.toString().trim() ?? '';
            if (name.isNotEmpty) {
              location = name;
            }
          }

          rows.add(
            ScanResultRow(
              company: companyName,
              title: title,
              companyUrl: careerUri.toString(),
              applyLink: applyLink,
              location: location,
              duration: parseDuration(content).$1,
              deadline: '—',
              source: 'Bitso Greenhouse API',
              error: '',
            ),
          );
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('careers.blackline.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;

        final apiUri = Uri.https('careers.blackline.com', '/api/jobs');
        final response = await _client
            .get(
              apiUri,
              headers: {
                'accept': 'application/json, text/plain, */*',
                'user-agent':
                    userAgents[DateTime.now().millisecond % userAgents.length],
                'referer': careerUri.toString(),
              },
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode >= 400 || response.body.trim().isEmpty) {
          return const [];
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map || decoded['jobs'] is! List) {
          return const [];
        }

        final jobs = (decoded['jobs'] as List).whereType<Map>();
        for (final item in jobs) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          final dataObj = map['data'];
          final data = dataObj is Map
              ? dataObj.map((k, v) => MapEntry(k.toString(), v))
              : map;

          final title = (data['title'] ?? '').toString().trim();
          if (title.isEmpty) continue;

          final description =
              (data['descriptionPlain'] ?? data['description'] ?? '')
                  .toString()
                  .trim();
          final titleLower = title.toLowerCase();
          final exactWordMatch = matchTerms.any((kw) {
            final pattern = RegExp('\\b${RegExp.escape(kw.toLowerCase())}\\b');
            return pattern.hasMatch(titleLower);
          });
          if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
            continue;
          }

          final slug = (data['slug'] ?? data['req_id'] ?? data['id'] ?? '')
              .toString()
              .trim();
          final applyLink = slug.isNotEmpty
              ? Uri.https(
                  'careers.blackline.com',
                  '/careers-home/jobs/$slug',
                ).toString()
              : careerUri.toString();
          final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
          if (seen.contains(key)) continue;
          seen.add(key);

          String location = 'Not specified';
          final locationObj = data['location'];
          if (locationObj is Map) {
            final text = (locationObj['name'] ?? locationObj['city'] ?? '')
                .toString()
                .trim();
            if (text.isNotEmpty) {
              location = text;
            }
          } else {
            final text = locationObj?.toString().trim() ?? '';
            if (text.isNotEmpty) {
              location = text;
            }
          }

          rows.add(
            ScanResultRow(
              company: companyName,
              title: title,
              companyUrl: careerUri.toString(),
              applyLink: applyLink,
              location: location,
              duration: parseDuration(description).$1,
              deadline: '—',
              source: 'BlackLine Jobs API',
              error: '',
            ),
          );
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('binance.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;

        final apiUri = Uri.https('api.lever.co', '/v0/postings/binance', {
          'mode': 'json',
        });
        final response = await _client
            .get(
              apiUri,
              headers: {
                'user-agent':
                    userAgents[DateTime.now().millisecond % userAgents.length],
                'accept': 'application/json, text/plain, */*',
                'accept-language': 'en-US,en;q=0.9',
                'referer': careerUri.toString(),
              },
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode >= 400 || response.body.trim().isEmpty) {
          return const [];
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! List) {
          return const [];
        }

        for (final item in decoded.whereType<Map>()) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          final title = (map['text'] ?? '').toString().trim();
          if (title.isEmpty) continue;

          final categories = map['categories'] is Map
              ? (map['categories'] as Map).map(
                  (k, v) => MapEntry(k.toString(), v?.toString().trim() ?? ''),
                )
              : <String, String>{};
          final team = (categories['team'] ?? '').trim();
          final location = (categories['location'] ?? '').trim();
          final commitment = (categories['commitment'] ?? '').trim();
          final department = (categories['department'] ?? '').trim();

          final searchable = [
            title,
            team,
            location,
            commitment,
            department,
          ].where((e) => e.isNotEmpty).join(' | ').toLowerCase();
          final exactWordMatch = matchTerms.any((kw) {
            final pattern = RegExp('\b${RegExp.escape(kw.toLowerCase())}\b');
            return pattern.hasMatch(searchable);
          });
          if (!exactWordMatch && !fuzzyMatch(title.toLowerCase(), matchTerms)) {
            continue;
          }

          final rawLink = (map['hostedUrl'] ?? map['applyUrl'] ?? '')
              .toString()
              .trim();
          final applyLink = rawLink.isNotEmpty ? rawLink : careerUri.toString();
          final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
          if (seen.contains(key)) continue;
          seen.add(key);

          final detailText = [
            team,
            department,
            commitment,
          ].where((e) => e.isNotEmpty).join(' | ');
          rows.add(
            ScanResultRow(
              company: companyName,
              title: title,
              companyUrl: careerUri.toString(),
              applyLink: applyLink,
              location: location.isEmpty ? 'Not specified' : location,
              duration: parseDuration(detailText).$1,
              deadline: '—',
              source: 'Binance Lever API',
              error: '',
            ),
          );
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('bitcoinsuisse.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;

        final apiUri = Uri.https('bitcoinsuisse.com', '/api/careers');
        final response = await _client
            .get(
              apiUri,
              headers: {
                'user-agent':
                    userAgents[DateTime.now().millisecond % userAgents.length],
                'accept': 'application/json, text/plain, */*',
                'accept-language': 'en-US,en;q=0.9',
                'referer': careerUri.toString(),
              },
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode >= 400 || response.body.trim().isEmpty) {
          return const [];
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! List) {
          return const [];
        }

        for (final item in decoded.whereType<Map>()) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          final title = (map['title'] ?? '').toString().trim();
          if (title.isEmpty) continue;

          final departments = map['departments'] is List
              ? (map['departments'] as List)
                    .map((e) => e.toString().trim())
                    .where((e) => e.isNotEmpty)
                    .toList()
              : <String>[];
          final departmentText = departments.join(' | ');

          final titleLower = title.toLowerCase();
          final deptLower = departmentText.toLowerCase();
          final exactWordMatch = matchTerms.any((kw) {
            final pattern = RegExp('\b${RegExp.escape(kw.toLowerCase())}\b');
            return pattern.hasMatch(titleLower) || pattern.hasMatch(deptLower);
          });
          if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
            continue;
          }

          final rawUrl = (map['url'] ?? '').toString().trim();
          final applyLink = rawUrl.isNotEmpty ? rawUrl : careerUri.toString();
          final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
          if (seen.contains(key)) continue;
          seen.add(key);

          rows.add(
            ScanResultRow(
              company: companyName,
              title: title,
              companyUrl: careerUri.toString(),
              applyLink: applyLink,
              location: 'Not specified',
              duration: parseDuration(departmentText).$1,
              deadline: '—',
              source: 'Bitcoin Suisse Careers API',
              error: '',
            ),
          );
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('darwinbox.in')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;

        final rendered = await _fetchRendered(careerUri);
        final html = (rendered != null && rendered.trim().isNotEmpty)
            ? rendered
            : await _fetch(careerUri);
        if (html == null || html.trim().isEmpty) {
          return const [];
        }

        String normalize(String input) {
          return input.replaceAll(RegExp(r'\s+'), ' ').trim();
        }

        final doc = html_parser.parse(html);
        final ctas = doc.querySelectorAll('a,button,span,div').where((el) {
          final t = normalize(el.text).toLowerCase();
          return t == 'view and apply' || t.contains('view and apply');
        }).toList();

        for (final cta in ctas) {
          html_dom.Element? card = cta;
          String cardText = '';
          for (var i = 0; i < 7 && card != null; i++) {
            final t = normalize(card.text);
            if (t.toLowerCase().contains('view and apply') && t.length > 20) {
              cardText = t;
              break;
            }
            card = card.parent;
          }
          if (card == null || cardText.isEmpty) continue;

          final prefix = cardText
              .split(RegExp('view and apply', caseSensitive: false))
              .first;
          final titleMatch = RegExp(
            r'^\s*([A-Za-z0-9][A-Za-z0-9 &\-_/]{2,120})',
          ).firstMatch(prefix);
          final title = normalize(titleMatch?.group(1) ?? '');
          if (title.isEmpty) continue;
          final titleLower = title.toLowerCase();
          final looksLikeUiNoise =
              title.length > 90 ||
              titleLower.contains('search by role') ||
              titleLower.contains('recommended jobs') ||
              titleLower.contains('discover opportunities') ||
              titleLower.contains('drag and drop your resume') ||
              titleLower.contains('open jobs') ||
              titleLower.contains('sign in');
          if (looksLikeUiNoise) continue;

          final locationMatch = RegExp(
            r'([A-Za-z_ ]+,\s*[A-Za-z ]+,\s*[A-Za-z ]+,\s*[A-Za-z ]+)',
            caseSensitive: false,
          ).firstMatch(cardText);
          final location = normalize(locationMatch?.group(1) ?? '');

          final textLower = cardText.toLowerCase();
          final exactWordMatch = matchTerms.any((kw) {
            final pattern = RegExp('\\b${RegExp.escape(kw.toLowerCase())}\\b');
            return pattern.hasMatch(titleLower) || pattern.hasMatch(textLower);
          });
          if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
            continue;
          }

          final anchor = cta.localName == 'a'
              ? cta
              : (card.querySelector('a[href]') ?? cta.querySelector('a[href]'));
          final href = (anchor?.attributes['href'] ?? '').trim();
          final applyLink = href.isNotEmpty
              ? careerUri.resolve(href).toString()
              : careerUri.toString();

          final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
          if (seen.contains(key)) continue;
          seen.add(key);

          final durationData = parseDuration(cardText);
          rows.add(
            ScanResultRow(
              company: companyName,
              title: title,
              companyUrl: careerUri.toString(),
              applyLink: applyLink,
              location: location.isEmpty ? 'Not specified' : location,
              duration: durationData.$1,
              deadline: '—',
              source: 'Darwinbox Rendered Careers',
              error: '',
            ),
          );
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('careers.bcg.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;

        String decodePhenomText(String value) {
          return value
              .replaceAll(r'\/', '/')
              .replaceAll('&amp;', '&')
              .replaceAll(r'\"', '"')
              .replaceAll(r'\n', ' ')
              .trim();
        }

        for (final term in matchTerms) {
          final searchUri = Uri.https(
            'careers.bcg.com',
            '/global/en/search-results',
            {'keywords': term, 'from': '0', 's': '1'},
          );

          String? html;
          for (final ua in userAgents.take(3)) {
            final resp = await _client
                .get(
                  searchUri,
                  headers: {
                    'User-Agent': ua,
                    'Accept-Language': 'en-US,en;q=0.9',
                    'Accept':
                        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                    'DNT': '1',
                  },
                )
                .timeout(const Duration(seconds: 12));
            if (resp.statusCode >= 400 || resp.body.trim().isEmpty) {
              continue;
            }
            if (resp.body.contains(
              '"applyUrl":"https://experiencedtalent.bcg.com/careerhub/explore/jobs/',
            )) {
              html = resp.body;
              break;
            }
            html ??= resp.body;
          }

          if (html == null || html.trim().isEmpty) {
            continue;
          }

          final objectMatches = RegExp(
            r'"title":"([^"\\]*(?:\\.[^"\\]*)*)".{0,2500}?"applyUrl":"(https://experiencedtalent\.bcg\.com/careerhub/explore/jobs/[^"\\]+)"',
            caseSensitive: false,
            dotAll: true,
          ).allMatches(html);

          for (final match in objectMatches) {
            final title = decodePhenomText(match.group(1)?.trim() ?? '');
            if (title.isEmpty) continue;
            final applyLink = decodePhenomText(match.group(2)?.trim() ?? '');
            if (applyLink.isEmpty) continue;

            final index = match.start;
            final windowStart = (index - 400) < 0 ? 0 : index - 400;
            final windowEnd = (index + 2800) > html.length
                ? html.length
                : index + 2800;
            final window = html.substring(windowStart, windowEnd);

            final description = decodePhenomText(
              RegExp(
                    r'"descriptionTeaser":"([^"\\]*(?:\\.[^"\\]*)*)"',
                  ).firstMatch(window)?.group(1) ??
                  '',
            );
            final location = decodePhenomText(
              RegExp(
                    r'"location":"([^"\\]*(?:\\.[^"\\]*)*)"',
                  ).firstMatch(window)?.group(1) ??
                  '',
            );

            final titleLower = title.toLowerCase();
            final descLower = description.toLowerCase();
            final locLower = location.toLowerCase();
            final exactWordMatch = matchTerms.any((kw) {
              final pattern = RegExp(
                '\\b${RegExp.escape(kw.toLowerCase())}\\b',
              );
              return pattern.hasMatch(titleLower) ||
                  pattern.hasMatch(descLower) ||
                  pattern.hasMatch(locLower);
            });
            if (!exactWordMatch &&
                !fuzzyMatch(titleLower, matchTerms) &&
                !fuzzyMatch(descLower, matchTerms)) {
              continue;
            }

            final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
            if (seen.contains(key)) continue;
            seen.add(key);

            final durationData = parseDuration(description);
            rows.add(
              ScanResultRow(
                company: companyName,
                title: title,
                companyUrl: searchUri.toString(),
                applyLink: applyLink,
                location: location.isEmpty ? 'Not specified' : location,
                duration: durationData.$1,
                deadline: '—',
                source: 'BCG Phenom Search HTML',
                error: '',
              ),
            );
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('careers.breadfinancial.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;
        final searchPath =
            careerUri.path.toLowerCase().contains('/search-results')
            ? careerUri.path
            : '/us/en/search-results';

        String decodePhenomText(String value) {
          return value
              .replaceAllMapped(RegExp(r'\\u([0-9a-fA-F]{4})'), (m) {
                final code = int.tryParse(m.group(1) ?? '', radix: 16);
                return code == null ? '' : String.fromCharCode(code);
              })
              .replaceAll(r'\/', '/')
              .replaceAll('&amp;', '&')
              .replaceAll(r'\"', '"')
              .replaceAll(r'\n', ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
        }

        final pageSize = 10;
        final baseQuery = Map<String, String>.from(careerUri.queryParameters);
        final startOffset = int.tryParse(baseQuery['from'] ?? '') ?? 0;

        var maxOffset = startOffset + 90;
        for (
          var offset = startOffset;
          offset <= maxOffset && offset <= (startOffset + 200);
          offset += pageSize
        ) {
          final query = Map<String, String>.from(baseQuery)
            ..remove('from')
            ..remove('s')
            ..['from'] = '$offset'
            ..['s'] = '1';

          final pageUri = Uri.https(
            careerUri.host,
            searchPath,
            query.isEmpty ? null : query,
          );

          final resp = await _client
              .get(
                pageUri,
                headers: {
                  'User-Agent':
                      userAgents[DateTime.now().millisecond %
                          userAgents.length],
                  'Accept-Language': 'en-US,en;q=0.9',
                  'Accept':
                      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                  'DNT': '1',
                },
              )
              .timeout(const Duration(seconds: 12));

          if (resp.statusCode >= 400 || resp.body.trim().isEmpty) {
            continue;
          }

          if (offset == startOffset) {
            final totalResultsMatch = RegExp(
              r'(\d+)\s*results',
              caseSensitive: false,
            ).firstMatch(resp.body);
            final totalResults = int.tryParse(
              totalResultsMatch?.group(1) ?? '',
            );
            if (totalResults != null && totalResults > 0) {
              maxOffset = ((totalResults - 1) ~/ pageSize) * pageSize;
            }
          }

          final applyMatches = RegExp(
            r'"applyUrl":"(https?:[^"\\]+)"',
            caseSensitive: false,
            dotAll: true,
          ).allMatches(resp.body);

          if (applyMatches.isEmpty) {
            continue;
          }

          for (final match in applyMatches) {
            final applyLinkRaw = decodePhenomText(match.group(1)?.trim() ?? '');
            if (applyLinkRaw.isEmpty) continue;

            final index = match.start;
            final beforeStart = (index - 2600) < 0 ? 0 : index - 2600;
            final before = resp.body.substring(beforeStart, index);

            final titleMatches = RegExp(
              r'"title":"([^"\\]*(?:\\.[^"\\]*)*)"',
              caseSensitive: false,
              dotAll: true,
            ).allMatches(before);
            if (titleMatches.isEmpty) continue;

            final title = decodePhenomText(
              titleMatches.last.group(1)?.trim() ?? '',
            );
            if (title.isEmpty) continue;

            final windowStart = (index - 600) < 0 ? 0 : index - 600;
            final windowEnd = (index + 3000) > resp.body.length
                ? resp.body.length
                : index + 3000;
            final window = resp.body.substring(windowStart, windowEnd);

            final description = decodePhenomText(
              RegExp(
                    r'"descriptionTeaser":"([^"\\]*(?:\\.[^"\\]*)*)"',
                  ).firstMatch(window)?.group(1) ??
                  '',
            );
            final location = decodePhenomText(
              RegExp(
                    r'"location":"([^"\\]*(?:\\.[^"\\]*)*)"',
                  ).firstMatch(window)?.group(1) ??
                  '',
            );

            final titleLower = title.toLowerCase();
            final descLower = description.toLowerCase();
            final locLower = location.toLowerCase();
            final exactWordMatch = matchTerms.any((kw) {
              final pattern = RegExp(
                '\\b${RegExp.escape(kw.toLowerCase())}\\b',
              );
              return pattern.hasMatch(titleLower) ||
                  pattern.hasMatch(descLower) ||
                  pattern.hasMatch(locLower);
            });
            if (!exactWordMatch &&
                !fuzzyMatch(titleLower, matchTerms) &&
                !fuzzyMatch(descLower, matchTerms)) {
              continue;
            }

            final applyLink = applyLinkRaw.startsWith('http')
                ? applyLinkRaw
                : pageUri.resolve(applyLinkRaw).toString();
            final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
            if (seen.contains(key)) continue;
            seen.add(key);

            final durationData = parseDuration(description);
            rows.add(
              ScanResultRow(
                company: companyName,
                title: title,
                companyUrl: careerUri.toString(),
                applyLink: applyLink,
                location: location.isEmpty ? 'Not specified' : location,
                duration: durationData.$1,
                deadline: '—',
                source: 'Bread Financial Phenom Search HTML',
                error: '',
              ),
            );
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('oraclecloud.com') &&
        careerUri.path.toLowerCase().contains('/hcmui/candidateexperience/')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;

        String? siteNumber;
        final landingHtml = await _fetch(careerUri);
        if (landingHtml != null && landingHtml.isNotEmpty) {
          final siteMatch = RegExp(
            r"siteNumber\s*:\s*'([^']+)'",
            caseSensitive: false,
          ).firstMatch(landingHtml);
          siteNumber = siteMatch?.group(1)?.trim();
        }

        final siteCandidates = <String>{};
        if (siteNumber != null && siteNumber.isNotEmpty) {
          siteCandidates.add(siteNumber);
        }

        final pathSegments = careerUri.pathSegments;
        final sitesIndex = pathSegments.indexWhere(
          (s) => s.toLowerCase() == 'sites',
        );
        final siteUrlName =
            (sitesIndex >= 0 && sitesIndex + 1 < pathSegments.length)
            ? pathSegments[sitesIndex + 1].trim()
            : '';

        final sitesUri = Uri.https(
          careerUri.host,
          '/hcmRestApi/resources/latest/recruitingCESites',
          {'onlyData': 'true', 'limit': '200', 'offset': '0'},
        );
        final sitesResp = await _client
            .get(
              sitesUri,
              headers: {
                'user-agent':
                    userAgents[DateTime.now().millisecond % userAgents.length],
                'accept': 'application/json, text/plain, */*',
                'referer': careerUri.toString(),
              },
            )
            .timeout(const Duration(seconds: 12));
        if (sitesResp.statusCode < 400 && sitesResp.body.trim().isNotEmpty) {
          final decoded = jsonDecode(sitesResp.body);
          if (decoded is Map && decoded['items'] is List) {
            final items = (decoded['items'] as List).whereType<Map>();
            for (final item in items) {
              final map = item.map((k, v) => MapEntry(k.toString(), v));
              final sn = (map['SiteNumber'] ?? '').toString().trim();
              if (sn.isEmpty) continue;
              final siteName = (map['SiteName'] ?? '').toString().trim();
              final siteCode = (map['SiteCode'] ?? '').toString().trim();
              final siteUrl = (map['SiteURLName'] ?? '').toString().trim();
              if (siteUrlName.isNotEmpty &&
                  (siteUrl.toLowerCase() == siteUrlName.toLowerCase() ||
                      siteName.toLowerCase() == siteUrlName.toLowerCase() ||
                      siteCode.toLowerCase() == siteUrlName.toLowerCase())) {
                siteCandidates.add(sn);
              }
            }
          }
        }

        if (siteCandidates.isEmpty) {
          return const [];
        }

        for (final sn in siteCandidates) {
          final cleanSn = sn.replaceAll("'", '');
          for (final term in matchTerms) {
            var offset = 0;
            const limit = 24;
            var hasMore = true;

            while (hasMore && offset < 500) {
              final escapedTerm = term.replaceAll('"', r'\"');
              final finderValue =
                  'findReqs;siteNumber=$cleanSn,keyword="$escapedTerm",limit=$limit,offset=$offset';
              final reqUri = Uri.https(
                careerUri.host,
                '/hcmRestApi/resources/latest/recruitingCEJobRequisitions',
                {
                  'onlyData': 'true',
                  'expand':
                      'requisitionList.workLocation,requisitionList.otherWorkLocations,requisitionList.secondaryLocations,flexFieldsFacet.values,requisitionList.requisitionFlexFields',
                  'finder': finderValue,
                },
              );

              final reqResp = await _client
                  .get(
                    reqUri,
                    headers: {
                      'user-agent':
                          userAgents[DateTime.now().millisecond %
                              userAgents.length],
                      'accept': 'application/json, text/plain, */*',
                      'referer': careerUri.toString(),
                    },
                  )
                  .timeout(const Duration(seconds: 12));

              if (reqResp.statusCode >= 400 || reqResp.body.trim().isEmpty) {
                break;
              }

              final decoded = jsonDecode(reqResp.body);
              if (decoded is! Map) {
                break;
              }

              final items = decoded['items'];
              if (items is! List || items.isEmpty) {
                break;
              }

              final searchContainer = items.first;
              if (searchContainer is! Map) {
                break;
              }

              final requisitions = searchContainer['requisitionList'];
              if (requisitions is! List || requisitions.isEmpty) {
                break;
              }

              for (final item in requisitions.whereType<Map>()) {
                final map = item.map((k, v) => MapEntry(k.toString(), v));
                String cleanValue(dynamic value) {
                  final text = value?.toString().trim() ?? '';
                  return text.toLowerCase() == 'null' ? '' : text;
                }

                final title =
                    ((map['Title'] ?? map['JobTitle']) ??
                            map['RequisitionTitle'])
                        .toString()
                        .trim();
                if (title.isEmpty) continue;

                final desc =
                    (((map['Description'] ?? map['JobDescription']) ??
                                map['ExternalDescription']) ??
                            map['ShortDescriptionStr'])
                        .toString()
                        .trim();
                final location =
                    ((map['PrimaryLocation'] ?? map['Location']) ??
                            map['Locations'])
                        .toString()
                        .trim();

                final titleLower = title.toLowerCase();
                final descLower = desc.toLowerCase();
                final locLower = location.toLowerCase();
                final exactWordMatch = matchTerms.any((kw) {
                  final pattern = RegExp(
                    '\\b${RegExp.escape(kw.toLowerCase())}\\b',
                  );
                  return pattern.hasMatch(titleLower) ||
                      pattern.hasMatch(descLower) ||
                      pattern.hasMatch(locLower);
                });
                if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
                  continue;
                }

                final id = cleanValue(
                  (map['Id'] ?? map['RequisitionNumber']) ?? map['JobId'],
                );
                final rawLink = cleanValue(
                  (map['ExternalURL'] ?? map['JobLink']) ?? map['JobDetailURL'],
                );
                final applyLink = rawLink.isNotEmpty
                    ? rawLink
                    : (id.isEmpty
                          ? careerUri.toString()
                          : '${careerUri.scheme}://${careerUri.host}/hcmUI/CandidateExperience/en/sites/$siteUrlName/job/$id');

                final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
                if (seen.contains(key)) continue;
                seen.add(key);

                final durationData = parseDuration(desc);
                rows.add(
                  ScanResultRow(
                    company: companyName,
                    title: title,
                    companyUrl: careerUri.toString(),
                    applyLink: applyLink,
                    location: location.isEmpty ? 'Not specified' : location,
                    duration: durationData.$1,
                    deadline: '—',
                    source: 'Oracle Candidate Experience API',
                    error: '',
                  ),
                );
              }

              final totalJobsCount =
                  int.tryParse(
                    (searchContainer['TotalJobsCount'] ?? '').toString(),
                  ) ??
                  0;
              final currentOffset =
                  int.tryParse((searchContainer['Offset'] ?? '').toString()) ??
                  offset;
              final currentLimit =
                  int.tryParse((searchContainer['Limit'] ?? '').toString()) ??
                  limit;
              final nextOffset = currentOffset + currentLimit;
              hasMore = nextOffset < totalJobsCount;
              if (!hasMore) break;
              offset = nextOffset;
            }
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('careers.bankofamerica.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;
        final queryTerms = keywords.isEmpty ? const ['intern'] : keywords;
        const pageSize = 50;

        Future<void> collectFromQuery(Map<String, String> baseParams) async {
          var start = 0;
          var totalMatches = pageSize;

          while (start < totalMatches && start < 500) {
            final qp = <String, String>{
              ...baseParams,
              'start': '$start',
              'rows': '$pageSize',
            };

            final uri = Uri.https(
              'careers.bankofamerica.com',
              '/services/jobssearchservlet',
              qp,
            );

            final response = await _client
                .get(
                  uri,
                  headers: {
                    'user-agent':
                        userAgents[DateTime.now().millisecond %
                            userAgents.length],
                    'accept': 'application/json, text/plain, */*',
                    'x-requested-with': 'XMLHttpRequest',
                    'referer': careerUri.toString(),
                  },
                )
                .timeout(const Duration(seconds: 12));

            if (response.statusCode >= 400 || response.body.trim().isEmpty) {
              break;
            }

            final decoded = jsonDecode(response.body);
            if (decoded is! Map) {
              break;
            }

            final parsedTotal = int.tryParse(
              (decoded['totalMatches'] ?? '').toString(),
            );
            if (parsedTotal != null && parsedTotal > 0) {
              totalMatches = parsedTotal;
            }

            final jobs = decoded['jobsList'];
            if (jobs is! List || jobs.isEmpty) {
              break;
            }

            for (final item in jobs.whereType<Map>()) {
              final map = item.map((k, v) => MapEntry(k.toString(), v));
              final title = (map['postingTitle'] ?? '').toString().trim();
              if (title.isEmpty) continue;

              final country = (map['country'] ?? '').toString().trim();
              final city = (map['city'] ?? '').toString().trim();
              final state = (map['state'] ?? '').toString().trim();
              final division = (map['division'] ?? '').toString().trim();
              final lob = (map['lob'] ?? '').toString().trim();
              final family = (map['family'] ?? '').toString().trim();
              final locationString = (map['locationString'] ?? '')
                  .toString()
                  .trim();
              final description = [
                division,
                lob,
                family,
                city,
                state,
                country,
                locationString,
              ].where((e) => e.isNotEmpty).join(' | ');

              final rawLink = (map['jcrURL'] ?? '').toString().trim();
              final applyLink = rawLink.isEmpty
                  ? careerUri.toString()
                  : careerUri.resolve(rawLink).toString();
              final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
              if (seen.contains(key)) continue;
              seen.add(key);

              final durationData = parseDuration(description);
              final location =
                  (map['location'] ?? '').toString().trim().isNotEmpty
                  ? (map['location'] ?? '').toString().trim()
                  : [
                      city,
                      state,
                      country,
                    ].where((e) => e.isNotEmpty).join(', ').trim();

              rows.add(
                ScanResultRow(
                  company: companyName,
                  title: title,
                  companyUrl: careerUri.toString(),
                  applyLink: applyLink,
                  location: location.isEmpty ? 'Not specified' : location,
                  duration: durationData.$1,
                  deadline: '—',
                  source: 'Bank of America Jobs API',
                  error: '',
                ),
              );
            }

            if (jobs.length < pageSize) {
              break;
            }
            start += pageSize;
          }
        }

        for (final query in queryTerms) {
          await collectFromQuery({'search': 'jobsByKeyword', 'term': query});
          if (rows.length >= 300) {
            break;
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('workforcenow.adp.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;
        final cid = (careerUri.queryParameters['cid'] ?? '').trim();
        if (cid.isEmpty) {
          return const [];
        }

        final lang = (careerUri.queryParameters['lang'] ?? 'en_US').trim();
        final apiUri = Uri.https(
          'workforcenow.adp.com',
          '/mascsr/default/careercenter/public/events/staffing/v1/job-requisitions',
          {'cid': cid, 'lang': lang},
        );

        final response = await _client
            .get(
              apiUri,
              headers: {
                'user-agent':
                    userAgents[DateTime.now().millisecond % userAgents.length],
                'accept': 'application/json, text/plain, */*',
                'x-requested-with': 'XMLHttpRequest',
                'referer': careerUri.toString(),
              },
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode >= 400 || response.body.trim().isEmpty) {
          return const [];
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          return const [];
        }

        final reqs = decoded['jobRequisitions'];
        if (reqs is! List || reqs.isEmpty) {
          return const [];
        }

        for (final item in reqs.whereType<Map>()) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));
          final title = (map['requisitionTitle'] ?? '').toString().trim();
          if (title.isEmpty) continue;

          final workLevel = ((map['workLevelCode'] as Map?)?['shortName'] ?? '')
              .toString();
          final description = workLevel.trim();
          final titleLower = title.toLowerCase();
          final descLower = description.toLowerCase();
          final exactWordMatch = matchTerms.any((kw) {
            final pattern = RegExp('\\b${RegExp.escape(kw.toLowerCase())}\\b');
            return pattern.hasMatch(titleLower) || pattern.hasMatch(descLower);
          });
          if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
            continue;
          }

          final itemId = (map['itemID'] ?? '').toString().trim();
          final applyLink = itemId.isEmpty
              ? careerUri.toString()
              : Uri.https(
                  'workforcenow.adp.com',
                  '/mascsr/default/careercenter/public/events/staffing/v1/job-requisitions/$itemId',
                  {'cid': cid, 'lang': lang},
                ).toString();
          final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
          if (seen.contains(key)) continue;
          seen.add(key);

          String location = 'Not specified';
          final locations = map['requisitionLocations'];
          if (locations is List && locations.isNotEmpty) {
            final first = locations.first;
            if (first is Map) {
              final firstMap = first.map((k, v) => MapEntry(k.toString(), v));
              final addressMap = (firstMap['address'] as Map?)?.map(
                (k, v) => MapEntry(k.toString(), v),
              );
              final city = (addressMap?['cityName'] ?? '').toString().trim();
              final state =
                  ((addressMap?['countrySubdivisionLevel1']
                              as Map?)?['codeValue'] ??
                          '')
                      .toString()
                      .trim();
              final country =
                  ((firstMap['nameCode'] as Map?)?['shortName'] ?? '')
                      .toString()
                      .trim();
              final parts = [
                city,
                state,
                country,
              ].where((e) => e.isNotEmpty).toList();
              if (parts.isNotEmpty) {
                location = parts.join(', ');
              }
            }
          }

          final durationData = parseDuration(description);
          rows.add(
            ScanResultRow(
              company: companyName,
              title: title,
              companyUrl: careerUri.toString(),
              applyLink: applyLink,
              location: location,
              duration: durationData.$1,
              deadline: '—',
              source: 'ADP CareerCenter API',
              error: '',
            ),
          );
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('awign.com')) {
      try {
        final html = await _fetch(careerUri);
        if (html == null || html.trim().isEmpty) {
          return const [];
        }

        final doc = html_parser.parse(html);
        final cards = doc.querySelectorAll('div[class*="vacancies_job_card"]');
        if (cards.isEmpty) {
          return const [];
        }

        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;

        for (final card in cards) {
          final title =
              (card.querySelector('div[class*="vacancies_title"]')?.text ?? '')
                  .trim();
          if (title.isEmpty) continue;

          final description = card.text.trim();
          final titleLower = title.toLowerCase();
          final descLower = description.toLowerCase();
          final exactWordMatch = matchTerms.any((kw) {
            final pattern = RegExp('\\b${RegExp.escape(kw.toLowerCase())}\\b');
            return pattern.hasMatch(titleLower) || pattern.hasMatch(descLower);
          });
          if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
            continue;
          }

          final durationData = parseDuration(description);
          final applyLink = careerUri.toString();
          final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
          if (seen.contains(key)) continue;
          seen.add(key);

          rows.add(
            ScanResultRow(
              company: companyName,
              title: title,
              companyUrl: careerUri.toString(),
              applyLink: applyLink,
              location: 'Not specified',
              duration: durationData.$1,
              deadline: '—',
              source: 'Awign Careers HTML',
              error: '',
            ),
          );
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('bain.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;
        final queryTerms = keywords.isEmpty ? const ['intern'] : keywords;
        final filters = (careerUri.queryParameters['filters'] ?? '').trim();
        const take = 20;

        for (final query in queryTerms) {
          var totalPages = 1;

          for (var page = 1; page <= totalPages && page <= 100; page++) {
            final qp = <String, String>{
              'keyword': query,
              'page': '$page',
              'take': '$take',
            };
            if (filters.isNotEmpty) {
              qp['filters'] = filters;
            }

            final uri = Uri.https(
              'www.bain.com',
              '/en/api/jobsearch/keyword/get',
              qp,
            );

            final response = await _client
                .get(
                  uri,
                  headers: {
                    'user-agent':
                        userAgents[DateTime.now().millisecond %
                            userAgents.length],
                    'accept': 'application/json, text/plain, */*',
                    'x-requested-with': 'XMLHttpRequest',
                    'referer': careerUri.toString(),
                  },
                )
                .timeout(const Duration(seconds: 12));

            if (response.statusCode >= 400 || response.body.trim().isEmpty) {
              continue;
            }

            final decoded = jsonDecode(response.body);
            if (decoded is! Map) {
              continue;
            }

            final totalResults = int.tryParse(
              (decoded['totalResults'] ?? '').toString(),
            );
            if (totalResults != null && totalResults > 0) {
              totalPages = ((totalResults + take - 1) ~/ take);
            }

            final results = decoded['results'];
            if (results is! List || results.isEmpty) {
              continue;
            }

            for (final item in results.whereType<Map>()) {
              final map = item.map((k, v) => MapEntry(k.toString(), v));
              final title = (map['JobTitle'] ?? '').toString().trim();
              if (title.isEmpty) continue;

              final descriptionHtml = (map['JobDescription'] ?? '')
                  .toString()
                  .trim();
              final descriptionDoc = html_parser.parse(descriptionHtml);
              final description =
                  descriptionDoc.documentElement?.text.trim() ?? '';

              final titleLower = title.toLowerCase();
              final descLower = description.toLowerCase();
              final exactWordMatch = matchTerms.any((kw) {
                final pattern = RegExp(
                  '\\b${RegExp.escape(kw.toLowerCase())}\\b',
                );
                return pattern.hasMatch(titleLower) ||
                    pattern.hasMatch(descLower);
              });
              if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
                continue;
              }

              final rawLink = (map['Link'] ?? '').toString().trim();
              final applyLink = rawLink.isEmpty
                  ? careerUri.toString()
                  : careerUri.resolve(rawLink).toString();
              final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
              if (seen.contains(key)) continue;
              seen.add(key);

              final locationValue = map['Location'];
              String location = 'Not specified';
              if (locationValue is List) {
                final normalized = locationValue
                    .map((e) => e.toString().trim())
                    .where((e) => e.isNotEmpty)
                    .toSet()
                    .toList();
                if (normalized.isNotEmpty) {
                  location = normalized.take(3).join(', ');
                }
              } else {
                final text = locationValue?.toString().trim() ?? '';
                if (text.isNotEmpty) {
                  location = text;
                }
              }

              final durationData = parseDuration(description);

              rows.add(
                ScanResultRow(
                  company: companyName,
                  title: title,
                  companyUrl: careerUri.toString(),
                  applyLink: applyLink,
                  location: location,
                  duration: durationData.$1,
                  deadline: '—',
                  source: 'Bain Job Search API',
                  error: '',
                ),
              );
            }
          }

          if (rows.length >= 300) {
            break;
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('att.jobs')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;
        final queryTerms = keywords.isEmpty ? const ['intern'] : keywords;

        for (final query in queryTerms) {
          var totalPages = 162;

          for (var page = 1; page <= totalPages; page++) {
            try {
              final uri = Uri.https('www.att.jobs', '/search-jobs/results', {
                'Keywords': query,
                'Location': '',
                'Distance': '50',
                'Latitude': '',
                'Longitude': '',
                'ShowRadius': 'False',
                'CurrentPage': '$page',
                'RecordsPerPage': '12',
                'ActiveFacetID': '0',
                'CustomFacetName': '',
                'FacetTerm': '',
                'FacetType': '0',
                'SearchResultsModuleName': 'Search Results',
                'SortCriteria': '0',
                'SortDirection': '0',
                'SearchType': '5',
                'KeywordType': '',
                'LocationType': '',
                'LocationPath': '',
                'OrganizationIds': '',
                'PostalCode': '',
                'ResultsType': '0',
                'TotalContentResults': '0',
                'IsPagination': 'False',
              });

              final response = await _client
                  .get(
                    uri,
                    headers: const {
                      'accept':
                          'application/json, text/javascript, */*; q=0.01',
                      'x-requested-with': 'XMLHttpRequest',
                      'referer': 'https://www.att.jobs/search-jobs',
                    },
                  )
                  .timeout(const Duration(seconds: 12));

              if (response.statusCode >= 400 || response.body.trim().isEmpty) {
                continue;
              }

              final decoded = jsonDecode(response.body);
              if (decoded is! Map) {
                continue;
              }

              final resultsHtml = (decoded['results'] ?? '').toString();
              if (resultsHtml.trim().isEmpty) {
                continue;
              }

              final doc = html_parser.parse(resultsHtml);
              final section = doc.querySelector('section#search-results');
              final totalPagesAttr = section?.attributes['data-total-pages']
                  ?.trim();
              final parsedTotalPages = int.tryParse(totalPagesAttr ?? '');
              if (parsedTotalPages != null && parsedTotalPages > 0) {
                totalPages = parsedTotalPages;
              }

              final entries = _extractTalentBrewEntries(
                doc,
                baseUri: careerUri,
              );
              if (entries.isEmpty) {
                continue;
              }

              for (final entry in entries) {
                final title = (entry['title'] ?? '').trim();
                if (title.isEmpty) continue;

                final description = (entry['description'] ?? '').trim();
                final titleLower = title.toLowerCase();
                final descLower = description.toLowerCase();
                final exactWordMatch = matchTerms.any((kw) {
                  final pattern = RegExp(
                    '\\b${RegExp.escape(kw.toLowerCase())}\\b',
                  );
                  return pattern.hasMatch(titleLower) ||
                      pattern.hasMatch(descLower);
                });
                if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
                  continue;
                }

                final durationData = parseDuration(description);

                final applyLink = (entry['applyLink'] ?? careerUri.toString())
                    .trim();
                final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
                if (seen.contains(key)) continue;
                seen.add(key);

                final location = (entry['location'] ?? '').trim();

                rows.add(
                  ScanResultRow(
                    company: companyName,
                    title: title,
                    companyUrl: careerUri.toString(),
                    applyLink: applyLink,
                    location: location.isEmpty ? 'Not specified' : location,
                    duration: durationData.$1,
                    deadline: '—',
                    source: 'ATT TalentBrew Results API',
                    error: '',
                  ),
                );
              }
            } catch (_) {
              continue;
            }
          }

          if (rows.length >= 300) {
            break;
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('careers.astrazeneca.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;
        final queryTerms = keywords.isEmpty ? const ['intern'] : keywords;

        for (final query in queryTerms) {
          var totalPages = 75;

          for (var page = 1; page <= totalPages; page++) {
            final uri =
                Uri.https('careers.astrazeneca.com', '/search-jobs/results', {
                  'Keywords': query,
                  'Location': '',
                  'Distance': '50',
                  'Latitude': '',
                  'Longitude': '',
                  'ShowRadius': 'False',
                  'CurrentPage': '$page',
                  'RecordsPerPage': '15',
                  'ActiveFacetID': '0',
                  'CustomFacetName': '',
                  'FacetTerm': '',
                  'FacetType': '0',
                  'SearchResultsModuleName': 'Search Results',
                  'SortCriteria': '0',
                  'SortDirection': '0',
                  'SearchType': '5',
                  'KeywordType': '',
                  'LocationType': '',
                  'LocationPath': '',
                  'OrganizationIds': '',
                  'PostalCode': '',
                  'ResultsType': '0',
                  'TotalContentResults': '0',
                  'IsPagination': 'False',
                });

            final response = await _client
                .get(
                  uri,
                  headers: const {
                    'accept': 'application/json, text/javascript, */*; q=0.01',
                    'x-requested-with': 'XMLHttpRequest',
                    'referer': 'https://careers.astrazeneca.com/search-jobs',
                  },
                )
                .timeout(const Duration(seconds: 12));

            if (response.statusCode >= 400 || response.body.trim().isEmpty) {
              continue;
            }

            final decoded = jsonDecode(response.body);
            if (decoded is! Map) {
              continue;
            }

            final resultsHtml = (decoded['results'] ?? '').toString();
            if (resultsHtml.trim().isEmpty) {
              continue;
            }

            final doc = html_parser.parse(resultsHtml);
            final section = doc.querySelector('section#search-results');
            final totalPagesAttr = section?.attributes['data-total-pages']
                ?.trim();
            final parsedTotalPages = int.tryParse(totalPagesAttr ?? '');
            if (parsedTotalPages != null && parsedTotalPages > 0) {
              totalPages = parsedTotalPages;
            }

            final entries = _extractTalentBrewEntries(doc, baseUri: careerUri);
            if (entries.isEmpty) {
              continue;
            }

            for (final entry in entries) {
              final title = (entry['title'] ?? '').trim();
              if (title.isEmpty) continue;

              final description = (entry['description'] ?? '').trim();
              final titleLower = title.toLowerCase();
              final descLower = description.toLowerCase();
              final exactWordMatch = matchTerms.any((kw) {
                final pattern = RegExp(
                  '\\b${RegExp.escape(kw.toLowerCase())}\\b',
                );
                return pattern.hasMatch(titleLower) ||
                    pattern.hasMatch(descLower);
              });
              if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
                continue;
              }

              final durationData = parseDuration(description);

              final applyLink = (entry['applyLink'] ?? careerUri.toString())
                  .trim();
              final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
              if (seen.contains(key)) continue;
              seen.add(key);

              final location = (entry['location'] ?? '').trim();

              rows.add(
                ScanResultRow(
                  company: companyName,
                  title: title,
                  companyUrl: careerUri.toString(),
                  applyLink: applyLink,
                  location: location.isEmpty ? 'Not specified' : location,
                  duration: durationData.$1,
                  deadline: '—',
                  source: 'AstraZeneca TalentBrew Results API',
                  error: '',
                ),
              );
            }
          }

          if (rows.length >= 300) {
            break;
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('careers.blackrock.com') ||
        host.contains('blackrock.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;
        final queryTerms = keywords.isEmpty ? const ['intern'] : keywords;

        for (final query in queryTerms) {
          var totalPages = 1;

          for (var page = 1; page <= totalPages; page++) {
            final uri =
                Uri.https('careers.blackrock.com', '/search-jobs/results', {
                  'Keywords': query,
                  'Location': '',
                  'Distance': '50',
                  'Latitude': '',
                  'Longitude': '',
                  'ShowRadius': 'False',
                  'CurrentPage': '$page',
                  'RecordsPerPage': '10',
                  'ActiveFacetID': '0',
                  'CustomFacetName': '',
                  'FacetTerm': '',
                  'FacetType': '0',
                  'SearchResultsModuleName': 'Section 3 - Search Results',
                  'SortCriteria': '0',
                  'SortDirection': '0',
                  'SearchType': '5',
                  'KeywordType': '',
                  'LocationType': '',
                  'LocationPath': '',
                  'OrganizationIds': '',
                  'PostalCode': '',
                  'ResultsType': '0',
                  'TotalContentResults': '0',
                  'IsPagination': 'False',
                });

            final response = await _client
                .get(
                  uri,
                  headers: const {
                    'accept': 'application/json, text/javascript, */*; q=0.01',
                    'x-requested-with': 'XMLHttpRequest',
                    'referer': 'https://careers.blackrock.com/search-jobs',
                  },
                )
                .timeout(const Duration(seconds: 12));

            if (response.statusCode >= 400 || response.body.trim().isEmpty) {
              continue;
            }

            final decoded = jsonDecode(response.body);
            if (decoded is! Map) {
              continue;
            }

            final resultsHtml = (decoded['results'] ?? '').toString();
            if (resultsHtml.trim().isEmpty) {
              continue;
            }

            final doc = html_parser.parse(resultsHtml);
            final section = doc.querySelector('section#search-results');
            final totalPagesAttr = section?.attributes['data-total-pages']
                ?.trim();
            final parsedTotalPages = int.tryParse(totalPagesAttr ?? '');
            if (parsedTotalPages != null && parsedTotalPages > 0) {
              totalPages = parsedTotalPages;
            }

            final entries = _extractTalentBrewEntries(doc, baseUri: careerUri);
            if (entries.isEmpty) {
              continue;
            }

            for (final entry in entries) {
              final title = (entry['title'] ?? '').trim();
              if (title.isEmpty) continue;

              final description = (entry['description'] ?? '').trim();
              final titleLower = title.toLowerCase();
              final descLower = description.toLowerCase();
              final exactWordMatch = matchTerms.any((kw) {
                final pattern = RegExp(
                  '\\b${RegExp.escape(kw.toLowerCase())}\\b',
                );
                return pattern.hasMatch(titleLower) ||
                    pattern.hasMatch(descLower);
              });
              if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
                continue;
              }

              final applyLink = (entry['applyLink'] ?? careerUri.toString())
                  .trim();
              final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
              if (seen.contains(key)) continue;
              seen.add(key);

              final location = (entry['location'] ?? '').trim();
              final durationData = parseDuration(description);

              rows.add(
                ScanResultRow(
                  company: companyName,
                  title: title,
                  companyUrl: careerUri.toString(),
                  applyLink: applyLink,
                  location: location.isEmpty ? 'Not specified' : location,
                  duration: durationData.$1,
                  deadline: '—',
                  source: 'BlackRock TalentBrew Results API',
                  error: '',
                ),
              );
            }
          }

          if (rows.length >= 300) {
            break;
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('artivatic.ai')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;

        final manifestResp = await _client
            .get(
              Uri.parse('https://artivatic.ai/asset-manifest.json'),
              headers: const {'accept': 'application/json, text/plain, */*'},
            )
            .timeout(const Duration(seconds: 12));

        if (manifestResp.statusCode >= 400 ||
            manifestResp.body.trim().isEmpty) {
          return const [];
        }

        final manifest = jsonDecode(manifestResp.body);
        if (manifest is! Map) {
          return const [];
        }

        final files = manifest['files'];
        if (files is! Map) {
          return const [];
        }

        String? chunkPath;
        for (final entry in files.entries) {
          final key = entry.key.toString();
          final value = entry.value?.toString() ?? '';
          if (key.startsWith('static/js/118.') &&
              key.endsWith('.chunk.js') &&
              value.isNotEmpty) {
            chunkPath = value;
            break;
          }
        }

        if (chunkPath == null || chunkPath.isEmpty) {
          return const [];
        }

        final chunkUri = Uri.parse('https://artivatic.ai').resolve(chunkPath);
        final chunkResp = await _client
            .get(
              chunkUri,
              headers: const {
                'accept':
                    'text/javascript, application/javascript, application/ecmascript, */*;q=0.1',
              },
            )
            .timeout(const Duration(seconds: 12));

        if (chunkResp.statusCode >= 400 || chunkResp.body.trim().isEmpty) {
          return const [];
        }

        final script = chunkResp.body;
        final cardMatches = RegExp(
          r'jobid:"([^"]+)"\s*,\s*date:"([^"]*)"\s*,\s*head:"([^"]+)"\s*,\s*description:"([^"]*)"',
          dotAll: true,
        ).allMatches(script);

        for (final m in cardMatches) {
          final jobId = (m.group(1) ?? '').trim();
          final date = (m.group(2) ?? '').trim();
          final title = (m.group(3) ?? '').trim();
          final description = (m.group(4) ?? '').trim();

          if (title.isEmpty) continue;

          final titleLower = title.toLowerCase();
          final descLower = description.toLowerCase();
          final exactWordMatch = matchTerms.any((kw) {
            final pattern = RegExp('\\b${RegExp.escape(kw.toLowerCase())}\\b');
            return pattern.hasMatch(titleLower) || pattern.hasMatch(descLower);
          });
          if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
            continue;
          }

          final durationData = parseDuration(description);

          final applyLink = jobId.isEmpty
              ? careerUri.toString()
              : Uri.https('artivatic.ai', '/job-details/$jobId').toString();
          final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
          if (seen.contains(key)) continue;
          seen.add(key);

          rows.add(
            ScanResultRow(
              company: companyName,
              title: title,
              companyUrl: careerUri.toString(),
              applyLink: applyLink,
              location: 'Not specified',
              duration: durationData.$1,
              deadline: date.isEmpty ? '—' : date,
              source: 'Artivatic Career Chunk',
              error: '',
            ),
          );
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('jobs.apple.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;
        final baseSearchUri = _buildAppleSearchUri(careerUri);
        final locale = baseSearchUri.pathSegments.isNotEmpty
            ? baseSearchUri.pathSegments.first
            : 'en-us';

        for (var page = 1; page <= 236; page++) {
          final searchUri = _withPage(baseSearchUri, page);
          final html = await _fetch(searchUri);
          if (html == null || html.trim().isEmpty) {
            continue;
          }

          final stateJson = _extractAppleInitialStateJson(html);
          if (stateJson == null || stateJson.trim().isEmpty) {
            continue;
          }

          final decoded = jsonDecode(stateJson);
          final jobs = _extractAppleJobs(decoded);
          if (jobs.isEmpty) {
            continue;
          }

          for (final map in jobs) {
            final title = (map['postingTitle'] ?? '').toString().trim();
            final description = (map['jobSummary'] ?? '').toString().trim();
            if (title.isEmpty) continue;

            final titleLower = title.toLowerCase();
            final descLower = description.toLowerCase();
            final exactWordMatch = matchTerms.any((kw) {
              final pattern = RegExp(
                '\\b${RegExp.escape(kw.toLowerCase())}\\b',
              );
              return pattern.hasMatch(titleLower) ||
                  pattern.hasMatch(descLower);
            });
            if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
              continue;
            }

            final durationData = parseDuration(description);

            String location = 'Not specified';
            final locations = map['locations'];
            if (locations is List && locations.isNotEmpty) {
              final names = locations
                  .whereType<Map>()
                  .map((e) => (e['name'] ?? '').toString().trim())
                  .where((v) => v.isNotEmpty)
                  .toList();
              if (names.isNotEmpty) {
                location = names.join(', ');
              }
            }

            final positionId = (map['positionId'] ?? '').toString().trim();
            final slug = (map['transformedPostingTitle'] ?? '')
                .toString()
                .trim();
            final applyLink = positionId.isNotEmpty && slug.isNotEmpty
                ? Uri.https(
                    'jobs.apple.com',
                    '/$locale/details/$positionId/$slug',
                  ).toString()
                : searchUri.toString();

            final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
            if (seen.contains(key)) continue;
            seen.add(key);

            rows.add(
              ScanResultRow(
                company: companyName,
                title: title,
                companyUrl: searchUri.toString(),
                applyLink: applyLink,
                location: location,
                duration: durationData.$1,
                deadline: '—',
                source: 'Apple Search State',
                error: '',
              ),
            );
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('jobs.aon.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final queryTerms = keywords.isEmpty ? const ['intern'] : keywords;
        final locationFilter = (careerUri.queryParameters['location'] ?? '')
            .toString()
            .trim();
        final sortBy = (careerUri.queryParameters['sortBy'] ?? 'relevance')
            .toString();
        final page =
            int.tryParse(careerUri.queryParameters['page'] ?? '1') ?? 1;
        final requestedLimit =
            int.tryParse(careerUri.queryParameters['limit'] ?? '100') ?? 100;
        final limit = requestedLimit.clamp(1, 100);
        final regionCode = (careerUri.queryParameters['regionCode'] ?? '')
            .toString()
            .trim();

        for (final query in queryTerms) {
          final qp = <String, String>{
            'keywords': query,
            'sortBy': sortBy,
            'page': '$page',
            'limit': '$limit',
          };
          if (locationFilter.isNotEmpty) {
            qp['location'] = locationFilter;
          }
          if (regionCode.isNotEmpty) {
            qp['regionCode'] = regionCode;
          }

          final uri = Uri.https('jobs.aon.com', '/api/jobs', qp);
          final response = await _client
              .get(
                uri,
                headers: const {'accept': 'application/json, text/plain, */*'},
              )
              .timeout(const Duration(seconds: 12));

          if (response.statusCode >= 400 || response.body.trim().isEmpty) {
            continue;
          }

          final decoded = jsonDecode(response.body);
          if (decoded is! Map || decoded['jobs'] is! List) {
            continue;
          }

          final jobs = (decoded['jobs'] as List).whereType<Map>();
          for (final item in jobs) {
            final data = item['data'];
            if (data is! Map) continue;
            final map = data.map((k, v) => MapEntry(k.toString(), v));

            final title = (map['title'] ?? '').toString().trim();
            final description = (map['description'] ?? '').toString().trim();
            if (title.isEmpty) continue;

            final titleLower = title.toLowerCase();
            final descLower = description.toLowerCase();
            final exactWordMatch = keywords.any((kw) {
              final pattern = RegExp(
                '\\b${RegExp.escape(kw.toLowerCase())}\\b',
              );
              return pattern.hasMatch(titleLower) ||
                  pattern.hasMatch(descLower);
            });
            if (!exactWordMatch && !fuzzyMatch(titleLower, keywords)) continue;

            final durationData = parseDuration(description);

            final applyLink =
                (map['apply_url'] ?? map['url'] ?? careerUri.toString())
                    .toString()
                    .trim();
            final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
            if (seen.contains(key)) continue;
            seen.add(key);

            String location = (map['location_name'] ?? '').toString().trim();
            final locations = map['locations'];
            if (locations is List && locations.isNotEmpty) {
              final names = locations
                  .whereType<Map>()
                  .map((e) => (e['name'] ?? '').toString().trim())
                  .where((v) => v.isNotEmpty)
                  .toList();
              if (names.isNotEmpty) {
                location = names.join(', ');
              }
            }

            rows.add(
              ScanResultRow(
                company: companyName,
                title: title,
                companyUrl: careerUri.toString(),
                applyLink: applyLink.isEmpty ? careerUri.toString() : applyLink,
                location: location.isEmpty ? 'Not specified' : location,
                duration: durationData.$1,
                deadline: '—',
                source: 'Aon Jobs API',
                error: '',
              ),
            );
          }

          if (rows.length >= 200) {
            break;
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('jobs.ashbyhq.com') || host.contains('ashbyhq.com')) {
      try {
        final segments = careerUri.pathSegments
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (segments.isEmpty) {
          return const [];
        }

        final board = segments.first;
        return await _fetchAshbyRows(
          board: board,
          companyName: companyName,
          careerUri: careerUri,
          keywords: keywords,
        );
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('jobs.lever.co')) {
      try {
        final segments = careerUri.pathSegments
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        if (segments.isEmpty) {
          return const [];
        }

        final board = segments.first;
        final uri = Uri.https('api.lever.co', '/v0/postings/$board', {
          'mode': 'json',
        });

        final response = await _client
            .get(
              uri,
              headers: const {'accept': 'application/json, text/plain, */*'},
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode >= 400 || response.body.trim().isEmpty) {
          return const [];
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! List) {
          return const [];
        }

        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;

        for (final item in decoded.whereType<Map>()) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));

          final title = (map['text'] ?? '').toString().trim();
          final description =
              (map['descriptionPlain'] ?? map['description'] ?? '')
                  .toString()
                  .trim();
          if (title.isEmpty) continue;

          final titleLower = title.toLowerCase();
          final descLower = description.toLowerCase();
          final exactWordMatch = matchTerms.any((kw) {
            final pattern = RegExp('\\b${RegExp.escape(kw.toLowerCase())}\\b');
            return pattern.hasMatch(titleLower) || pattern.hasMatch(descLower);
          });
          if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) continue;

          final durationData = parseDuration(description);

          final applyLink = (map['hostedUrl'] ?? careerUri.toString())
              .toString()
              .trim();
          final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
          if (seen.contains(key)) continue;
          seen.add(key);

          String location = 'Not specified';
          final categories = map['categories'];
          if (categories is Map) {
            final loc = (categories['location'] ?? '').toString().trim();
            if (loc.isNotEmpty) {
              location = loc;
            }
          }

          rows.add(
            ScanResultRow(
              company: companyName,
              title: title,
              companyUrl: careerUri.toString(),
              applyLink: applyLink.isEmpty ? careerUri.toString() : applyLink,
              location: location,
              duration: durationData.$1,
              deadline: '—',
              source: 'Lever Postings API',
              error: '',
            ),
          );
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('careers.amgen.com') || host.contains('amgen.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final queryTerms = keywords.isEmpty ? const ['intern'] : keywords;
        final matchTerms = keywords.isEmpty ? queryTerms : keywords;

        for (final query in queryTerms) {
          final uri =
              Uri.https('careers.amgen.com', '/en/search-jobs/results', {
                'Keywords': query,
                'Location': '',
                'Distance': '50',
                'Latitude': '',
                'Longitude': '',
                'ShowRadius': 'False',
                'CurrentPage': '1',
                'RecordsPerPage': '100',
                'ActiveFacetID': '0',
                'CustomFacetName': '',
                'FacetTerm': '',
                'FacetType': '0',
                'SearchResultsModuleName': 'Search Results v2 - Module',
                'SortCriteria': '0',
                'SortDirection': '0',
                'SearchType': '5',
                'KeywordType': '',
                'LocationType': '',
                'LocationPath': '',
                'OrganizationIds': '87',
                'PostalCode': '',
                'ResultsType': '0',
                'TotalContentResults': '0',
                'IsPagination': 'False',
              });

          final response = await _client
              .get(
                uri,
                headers: const {
                  'accept': 'application/json, text/javascript, */*; q=0.01',
                  'x-requested-with': 'XMLHttpRequest',
                  'referer': 'https://careers.amgen.com/en/search-jobs',
                },
              )
              .timeout(const Duration(seconds: 12));

          if (response.statusCode >= 400 || response.body.trim().isEmpty) {
            continue;
          }

          final decoded = jsonDecode(response.body);
          if (decoded is! Map) {
            continue;
          }

          final resultsHtml = (decoded['results'] ?? '').toString();
          if (resultsHtml.trim().isEmpty) {
            continue;
          }

          final doc = html_parser.parse(resultsHtml);
          final cards = doc.querySelectorAll(
            'ul#search-results-jobs li > a[href]',
          );

          for (final card in cards) {
            final title =
                card.querySelector('h3')?.text.trim() ?? card.text.trim();
            if (title.isEmpty) continue;

            final description = card.text.trim();
            final titleLower = title.toLowerCase();
            final descLower = description.toLowerCase();
            final exactWordMatch = matchTerms.any((kw) {
              final pattern = RegExp(
                '\\b${RegExp.escape(kw.toLowerCase())}\\b',
              );
              return pattern.hasMatch(titleLower) ||
                  pattern.hasMatch(descLower);
            });
            if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) {
              continue;
            }

            final durationData = parseDuration(description);

            final href = card.attributes['href'] ?? '';
            final applyLink = href.isEmpty
                ? careerUri.toString()
                : Uri.https('careers.amgen.com', href).toString();
            final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
            if (seen.contains(key)) continue;
            seen.add(key);

            final location =
                card.querySelector('.job-location')?.text.trim() ?? '';

            rows.add(
              ScanResultRow(
                company: companyName,
                title: title,
                companyUrl: careerUri.toString(),
                applyLink: applyLink,
                location: location.isEmpty ? 'Not specified' : location,
                duration: durationData.$1,
                deadline: '—',
                source: 'Amgen TalentBrew API',
                error: '',
              ),
            );
          }

          if (rows.length >= 200) {
            break;
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('careers.amd.com') || host.contains('amd.com')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};

        final country = (careerUri.queryParameters['country'] ?? 'India')
            .toString()
            .trim();
        final page =
            int.tryParse(careerUri.queryParameters['page'] ?? '1') ?? 1;
        final requestedLimit =
            int.tryParse(careerUri.queryParameters['limit'] ?? '30') ?? 30;
        final limit = requestedLimit.clamp(1, 100);

        final queryTerms = keywords.isEmpty ? const ['intern'] : keywords;
        for (final query in queryTerms) {
          final uri = Uri.https('careers.amd.com', '/api/jobs', {
            'country': country,
            'keywords': query,
            'page': '$page',
            'limit': '$limit',
          });

          final response = await _client
              .get(
                uri,
                headers: const {'accept': 'application/json, text/plain, */*'},
              )
              .timeout(const Duration(seconds: 12));

          if (response.statusCode >= 400 || response.body.trim().isEmpty) {
            continue;
          }

          final decoded = jsonDecode(response.body);
          if (decoded is! Map || decoded['jobs'] is! List) {
            continue;
          }

          final jobs = (decoded['jobs'] as List).whereType<Map>();
          for (final item in jobs) {
            final data = item['data'];
            if (data is! Map) continue;
            final map = data.map((k, v) => MapEntry(k.toString(), v));

            final title = (map['title'] ?? '').toString().trim();
            final description =
                (map['description'] ?? map['qualifications'] ?? '')
                    .toString()
                    .trim();
            if (title.isEmpty) continue;

            final titleLower = title.toLowerCase();
            final descLower = description.toLowerCase();
            final exactWordMatch = keywords.any((kw) {
              final pattern = RegExp(
                '\\b${RegExp.escape(kw.toLowerCase())}\\b',
              );
              return pattern.hasMatch(titleLower) ||
                  pattern.hasMatch(descLower);
            });
            if (!exactWordMatch && !fuzzyMatch(titleLower, keywords)) continue;

            final durationData = parseDuration(description);

            final applyLink =
                (map['apply_url'] ??
                        map['url_next_step'] ??
                        map['external'] ??
                        careerUri.toString())
                    .toString()
                    .trim();
            final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
            if (seen.contains(key)) continue;
            seen.add(key);

            final location =
                (map['location_name'] ??
                        map['full_location'] ??
                        map['city'] ??
                        map['country'] ??
                        '')
                    .toString()
                    .trim();

            rows.add(
              ScanResultRow(
                company: companyName,
                title: title,
                companyUrl: careerUri.toString(),
                applyLink: applyLink.isEmpty ? careerUri.toString() : applyLink,
                location: location.isEmpty ? 'Not specified' : location,
                duration: durationData.$1,
                deadline: '—',
                source: 'AMD Jobs API',
                error: '',
              ),
            );
          }

          if (rows.length >= 200) {
            break;
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('amazon.jobs')) {
      try {
        final rows = <ScanResultRow>[];
        final seen = <String>{};

        final countryFilters = <String>[];
        for (final entry in careerUri.queryParametersAll.entries) {
          if (entry.key.toLowerCase() == 'country[]') {
            for (final v in entry.value) {
              final trimmed = v.trim();
              if (trimmed.isNotEmpty) {
                countryFilters.add(trimmed);
              }
            }
          }
        }

        final queryTerms = keywords.isEmpty ? const ['intern'] : keywords;
        for (final query in queryTerms) {
          final qp = <String, dynamic>{
            'base_query': query,
            'offset': '0',
            'result_limit': '30',
          };
          if (countryFilters.isNotEmpty) {
            qp['country[]'] = countryFilters;
          }

          final uri = Uri.https('www.amazon.jobs', '/en/search.json', qp);
          final response = await _client
              .get(
                uri,
                headers: const {'accept': 'application/json, text/plain, */*'},
              )
              .timeout(const Duration(seconds: 12));

          if (response.statusCode >= 400 || response.body.trim().isEmpty) {
            continue;
          }

          final decoded = jsonDecode(response.body);
          if (decoded is! Map || decoded['jobs'] is! List) {
            continue;
          }

          final jobs = (decoded['jobs'] as List).whereType<Map>();
          for (final item in jobs) {
            final map = item.map((k, v) => MapEntry(k.toString(), v));

            final title = (map['title'] ?? '').toString().trim();
            final description = (map['description'] ?? '').toString().trim();
            if (title.isEmpty) continue;

            final titleLower = title.toLowerCase();
            final descLower = description.toLowerCase();
            final exactWordMatch = keywords.any((kw) {
              final pattern = RegExp(
                '\\b${RegExp.escape(kw.toLowerCase())}\\b',
              );
              return pattern.hasMatch(titleLower) ||
                  pattern.hasMatch(descLower);
            });
            if (!exactWordMatch && !fuzzyMatch(titleLower, keywords)) continue;

            final durationData = parseDuration(description);

            final jobPath = (map['job_path'] ?? '').toString().trim();
            final applyLink = jobPath.isNotEmpty
                ? Uri.https('www.amazon.jobs', jobPath).toString()
                : careerUri.toString();
            final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
            if (seen.contains(key)) continue;
            seen.add(key);

            final location =
                (map['normalized_location'] ?? map['location'] ?? '')
                    .toString()
                    .trim();

            rows.add(
              ScanResultRow(
                company: companyName,
                title: title,
                companyUrl: careerUri.toString(),
                applyLink: applyLink,
                location: location.isEmpty ? 'Not specified' : location,
                duration: durationData.$1,
                deadline: '—',
                source: 'Amazon Search JSON',
                error: '',
              ),
            );
          }

          if (rows.length >= 200) {
            break;
          }
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('0x.org')) {
      try {
        final response = await _client
            .get(
              Uri.parse(
                'https://api.ashbyhq.com/posting-api/job-board/0x?includeCompensation=true',
              ),
              headers: const {'accept': 'application/json, text/plain, */*'},
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode >= 400) {
          return const [];
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map || decoded['jobs'] is! List) {
          return const [];
        }

        final jobs = (decoded['jobs'] as List).whereType<Map>();
        final rows = <ScanResultRow>[];
        final seen = <String>{};

        for (final item in jobs) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));

          final title = (map['title'] ?? '').toString().trim();
          final description = (map['descriptionPlain'] ?? '').toString().trim();
          if (title.isEmpty) continue;

          final titleLower = title.toLowerCase();
          final descLower = description.toLowerCase();
          final exactWordMatch = keywords.any((kw) {
            final pattern = RegExp('\\b${RegExp.escape(kw.toLowerCase())}\\b');
            return pattern.hasMatch(titleLower) || pattern.hasMatch(descLower);
          });
          if (!exactWordMatch && !fuzzyMatch(titleLower, keywords)) continue;

          final durationData = parseDuration(description);

          final applyLink =
              (map['applyUrl'] ?? map['jobUrl'] ?? careerUri.toString())
                  .toString()
                  .trim();
          final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
          if (seen.contains(key)) continue;
          seen.add(key);

          final location = (map['location'] ?? '').toString().trim();

          rows.add(
            ScanResultRow(
              company: companyName,
              title: title,
              companyUrl: careerUri.toString(),
              applyLink: applyLink,
              location: location.isEmpty ? 'Not specified' : location,
              duration: durationData.$1,
              deadline: '—',
              source: 'Ashby API',
              error: '',
            ),
          );
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('acko.com') || host.contains('cashfree.com')) {
      try {
        final source = host.contains('cashfree.com')
            ? Uri.parse('https://careers.kula.ai/cashfree?jobs=true')
            : Uri.parse('https://careers.kula.ai/acko?jobs=true');
        final response = await _client
            .get(
              source,
              headers: const {
                'accept':
                    'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              },
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode >= 400 || response.body.trim().isEmpty) {
          return const [];
        }

        final doc = html_parser.parse(response.body);
        final rows = <ScanResultRow>[];
        final seen = <String>{};
        final cards = doc.querySelectorAll('div.chakra-card');

        for (final card in cards) {
          final title =
              card.querySelector('p.css-f8zk62')?.text.trim() ??
              card.querySelector('p.chakra-text')?.text.trim() ??
              '';
          if (title.isEmpty) continue;

          final titleLower = title.toLowerCase();
          final context = card.text;
          final contextLower = context.toLowerCase();
          final exactWordMatch = keywords.any((kw) {
            final pattern = RegExp('\\b${RegExp.escape(kw.toLowerCase())}\\b');
            return pattern.hasMatch(titleLower) ||
                pattern.hasMatch(contextLower);
          });
          if (!exactWordMatch && !fuzzyMatch(titleLower, keywords)) continue;

          final durationData = parseDuration(context);

          final href = card.querySelector('a[href]')?.attributes['href'];
          final applyLink = href == null
              ? source.toString()
              : source.resolve(href).toString();
          final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
          if (seen.contains(key)) continue;
          seen.add(key);

          final location =
              card.querySelector('p.css-de2tee')?.text.trim() ??
              parseLocation(context);

          rows.add(
            ScanResultRow(
              company: companyName,
              title: title,
              companyUrl: careerUri.toString(),
              applyLink: applyLink,
              location: location.isEmpty ? 'Not specified' : location,
              duration: durationData.$1,
              deadline: '—',
              source: 'Kula Careers HTML',
              error: '',
            ),
          );
        }

        if (rows.isNotEmpty) {
          return rows;
        }
      } catch (_) {
        return const [];
      }
    }

    if (host.contains('careers.adyen.com') || host.contains('greenhouse.io')) {
      try {
        var board = 'adyen';
        if (!host.contains('careers.adyen.com')) {
          final segments = careerUri.pathSegments
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (segments.isEmpty) {
            return const [];
          }
          board = segments.first;
        }

        final response = await _client
            .get(
              Uri.parse(
                'https://boards-api.greenhouse.io/v1/boards/$board/jobs?content=true',
              ),
              headers: const {'accept': 'application/json, text/plain, */*'},
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode >= 400) {
          return const [];
        }

        final decoded = jsonDecode(response.body);
        if (decoded is! Map || decoded['jobs'] is! List) {
          return const [];
        }

        final jobs = (decoded['jobs'] as List).whereType<Map>();
        final rows = <ScanResultRow>[];
        final seen = <String>{};

        for (final item in jobs) {
          final map = item.map((k, v) => MapEntry(k.toString(), v));

          final title = (map['title'] ?? '').toString().trim();
          final content = (map['content'] ?? '').toString().trim();
          if (title.isEmpty) continue;

          final titleLower = title.toLowerCase();
          final contentLower = content.toLowerCase();
          final exactWordMatch = keywords.any((kw) {
            final pattern = RegExp('\\b${RegExp.escape(kw.toLowerCase())}\\b');
            return pattern.hasMatch(titleLower) ||
                pattern.hasMatch(contentLower);
          });
          if (!exactWordMatch && !fuzzyMatch(titleLower, keywords)) continue;

          final durationData = parseDuration(content);

          final applyLink = (map['absolute_url'] ?? careerUri.toString())
              .toString()
              .trim();
          final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
          if (seen.contains(key)) continue;
          seen.add(key);

          String location = 'Not specified';
          final locationObj = map['location'];
          if (locationObj is Map) {
            final name = (locationObj['name'] ?? '').toString().trim();
            if (name.isNotEmpty) {
              location = name;
            }
          } else {
            final name = locationObj?.toString().trim() ?? '';
            if (name.isNotEmpty) {
              location = name;
            }
          }

          rows.add(
            ScanResultRow(
              company: companyName,
              title: title,
              companyUrl: careerUri.toString(),
              applyLink: applyLink,
              location: location,
              duration: durationData.$1,
              deadline: '—',
              source: 'Greenhouse API',
              error: '',
            ),
          );
        }

        return rows;
      } catch (_) {
        return const [];
      }
    }

    if (!host.contains('aeonsoftware.net')) {
      return const [];
    }

    try {
      final response = await _client
          .post(
            Uri.parse('https://hrdeskbkv2.aeontechhub.com/Jobs/GetJobOpenings'),
            headers: {
              'content-type': 'application/json',
              'accept': 'application/json, text/plain, */*',
            },
            body: jsonEncode({'Status': '1'}),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode >= 400) {
        return const [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return const [];
      }

      final rows = <ScanResultRow>[];
      final seen = <String>{};
      for (final item in decoded.whereType<Map>()) {
        final map = item.map(
          (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
        );

        final title = map['job_Title']?.trim() ?? '';
        final description = map['job_desc']?.trim() ?? '';
        if (title.isEmpty) continue;

        final titleLower = title.toLowerCase();
        final descLower = description.toLowerCase();
        final exactWordMatch = keywords.any((kw) {
          final pattern = RegExp('\\b${RegExp.escape(kw.toLowerCase())}\\b');
          return pattern.hasMatch(titleLower) || pattern.hasMatch(descLower);
        });
        if (!exactWordMatch && !fuzzyMatch(titleLower, keywords)) continue;

        final durationData = parseDuration(description);

        final postId = map['post_id']?.trim() ?? '';
        final key = '${title.toLowerCase()}|$postId';
        if (seen.contains(key)) continue;
        seen.add(key);

        final location = (map['loc']?.trim().isNotEmpty ?? false)
            ? map['loc']!.trim()
            : 'Not specified';

        rows.add(
          ScanResultRow(
            company: companyName,
            title: title,
            companyUrl: careerUri.toString(),
            applyLink: careerUri.toString(),
            location: location,
            duration: durationData.$1,
            deadline: '—',
            source: 'JSON API',
            error: '',
          ),
        );
      }

      return rows;
    } catch (_) {
      return const [];
    }
  }

  Future<List<ScanResultRow>> _fetchAshbyRows({
    required String board,
    required String companyName,
    required Uri careerUri,
    required List<String> keywords,
  }) async {
    List<Map<String, dynamic>> jobs = const [];

    try {
      final response = await _client
          .get(
            Uri.parse(
              'https://api.ashbyhq.com/posting-api/job-board/$board?includeCompensation=true',
            ),
            headers: const {'accept': 'application/json, text/plain, */*'},
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode < 400 && response.body.trim().isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['jobs'] is List) {
          jobs = (decoded['jobs'] as List)
              .whereType<Map>()
              .map(
                (e) =>
                    e.map((k, v) => MapEntry(k.toString(), v))
                      ..cast<String, dynamic>(),
              )
              .toList();
        }
      }
    } catch (_) {}

    if (jobs.isEmpty) {
      try {
        final gqlResponse = await _client
            .post(
              Uri.parse(
                'https://jobs.ashbyhq.com/api/non-user-graphql?op=ApiJobBoardWithTeams',
              ),
              headers: const {
                'content-type': 'application/json',
                'accept': 'application/json, text/plain, */*',
              },
              body: jsonEncode({
                'operationName': 'ApiJobBoardWithTeams',
                'query': r'''
query ApiJobBoardWithTeams($organizationHostedJobsPageName: String!) {
  jobBoard: jobBoardWithTeams(
    organizationHostedJobsPageName: $organizationHostedJobsPageName
  ) {
    jobPostings {
      id
      title
      locationName
    }
  }
}
''',
                'variables': {'organizationHostedJobsPageName': board},
              }),
            )
            .timeout(const Duration(seconds: 12));

        if (gqlResponse.statusCode < 400 &&
            gqlResponse.body.trim().isNotEmpty) {
          final decoded = jsonDecode(gqlResponse.body);
          final data = decoded is Map ? decoded['data'] : null;
          final root = data is Map ? data : const {};

          final candidates = <dynamic>[
            root['jobBoard'],
            root['jobBoardWithTeams'],
            root,
          ];

          for (final candidate in candidates) {
            if (candidate is! Map) continue;
            final postings = candidate['jobPostings'];
            if (postings is List && postings.isNotEmpty) {
              jobs = postings
                  .whereType<Map>()
                  .map(
                    (e) =>
                        e.map((k, v) => MapEntry(k.toString(), v))
                          ..cast<String, dynamic>(),
                  )
                  .toList();
              break;
            }
          }
        }
      } catch (_) {}
    }

    if (jobs.isEmpty) {
      return const [];
    }

    final rows = <ScanResultRow>[];
    final seen = <String>{};
    final matchTerms = keywords.isEmpty ? const ['intern'] : keywords;

    for (final map in jobs) {
      final title = (map['title'] ?? '').toString().trim();
      final description =
          (map['descriptionPlain'] ?? map['descriptionHtml'] ?? '')
              .toString()
              .trim();
      final postingId = (map['id'] ?? '').toString().trim();
      if (title.isEmpty) continue;

      final titleLower = title.toLowerCase();
      final descLower = description.toLowerCase();
      final exactWordMatch = matchTerms.any((kw) {
        final pattern = RegExp('\\b${RegExp.escape(kw.toLowerCase())}\\b');
        return pattern.hasMatch(titleLower) || pattern.hasMatch(descLower);
      });
      if (!exactWordMatch && !fuzzyMatch(titleLower, matchTerms)) continue;

      final durationData = parseDuration(description);

      final applyLink =
          (map['applyUrl'] ?? map['jobUrl'] ?? '').toString().trim().isNotEmpty
          ? (map['applyUrl'] ?? map['jobUrl']).toString().trim()
          : postingId.isNotEmpty
          ? 'https://jobs.ashbyhq.com/$board/$postingId'
          : careerUri.toString();
      final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
      if (seen.contains(key)) continue;
      seen.add(key);

      final location = (map['location'] ?? map['locationName'] ?? '')
          .toString()
          .trim();

      rows.add(
        ScanResultRow(
          company: companyName,
          title: title,
          companyUrl: careerUri.toString(),
          applyLink: applyLink,
          location: location.isEmpty ? 'Not specified' : location,
          duration: durationData.$1,
          deadline: '—',
          source: 'Ashby API',
          error: '',
        ),
      );
    }

    return rows;
  }

  List<Map<String, String>> _extractTalentBrewEntries(
    html_dom.Document doc, {
    required Uri baseUri,
  }) {
    var links = doc.querySelectorAll('a.search-results-link[href]');
    if (links.isEmpty) {
      links = doc.querySelectorAll('section#search-results-list h2 a[href]');
    }
    if (links.isEmpty) {
      links = doc.querySelectorAll(
        'section#search-results-list a.section3__search-results-a[href]',
      );
    }
    if (links.isEmpty) {
      links = doc.querySelectorAll('section#search-results-list a[href]');
    }

    if (links.isEmpty) {
      return const [];
    }

    final out = <Map<String, String>>[];
    final seen = <String>{};

    for (final link in links) {
      final href = (link.attributes['href'] ?? '').trim();
      if (href.isEmpty) continue;

      final title = link.querySelector('h2')?.text.trim() ?? link.text.trim();
      if (title.isEmpty) continue;

      final applyLink = baseUri.resolve(href).toString();
      final key = '${title.toLowerCase()}|${applyLink.toLowerCase()}';
      if (seen.contains(key)) continue;
      seen.add(key);

      var description = link.parent?.text.trim() ?? link.text.trim();
      if (description.isEmpty) {
        description = title;
      }

      String location = '';
      html_dom.Element? node = link;
      for (var i = 0; i < 6 && node != null; i++) {
        final loc = node.querySelector('.job-location')?.text.trim() ?? '';
        if (loc.isNotEmpty) {
          location = loc;
          break;
        }
        node = node.parent;
      }

      out.add({
        'title': title,
        'description': description,
        'applyLink': applyLink,
        'location': location,
      });
    }

    return out;
  }

  Uri _buildAppleSearchUri(Uri seedUri) {
    final segments = seedUri.pathSegments
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (segments.length >= 2 && segments[1].toLowerCase() == 'search') {
      return seedUri;
    }

    final locale = segments.isNotEmpty && segments.first.contains('-')
        ? segments.first.toLowerCase()
        : 'en-us';
    final qp = <String, String>{};
    final location = (seedUri.queryParameters['location'] ?? '').toString();
    final page = (seedUri.queryParameters['page'] ?? '1').toString();
    if (location.isNotEmpty) {
      qp['location'] = location;
    }
    qp['page'] = page;

    return Uri.https('jobs.apple.com', '/$locale/search', qp);
  }

  Uri _withPage(Uri uri, int page) {
    final qp = <String, String>{
      ...uri.queryParameters.map((k, v) => MapEntry(k, v.toString())),
      'page': '$page',
    };
    return uri.replace(queryParameters: qp);
  }

  String? _extractAppleInitialStateJson(String html) {
    final parsedMatch = RegExp(
      r'window\.(?:__staticRouterHydrationData|__INITIAL_STATE__)\s*=\s*JSON\.parse\("(.+?)"\);',
      dotAll: true,
    ).firstMatch(html);
    if (parsedMatch != null) {
      final escaped = parsedMatch.group(1);
      if (escaped == null || escaped.isEmpty) return null;
      final unescaped = jsonDecode('"$escaped"');
      return unescaped is String ? unescaped : null;
    }

    final objectMatch = RegExp(
      r'window\.(?:__staticRouterHydrationData|__INITIAL_STATE__)\s*=\s*(\{.+?\});',
      dotAll: true,
    ).firstMatch(html);
    return objectMatch?.group(1);
  }

  List<Map<String, dynamic>> _extractAppleJobs(dynamic root) {
    final stack = <dynamic>[root];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (node is Map) {
        final jobs = node['jobs'];
        if (jobs is List && jobs.isNotEmpty) {
          final asMaps = jobs
              .whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .toList();
          if (asMaps.isNotEmpty &&
              (asMaps.first.containsKey('postingTitle') ||
                  asMaps.first.containsKey('positionId'))) {
            return asMaps;
          }
        }
        stack.addAll(node.values);
      } else if (node is List) {
        stack.addAll(node);
      }
    }
    return const [];
  }

  String _normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }
}
