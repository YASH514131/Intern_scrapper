import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models.dart';
import 'fuzzy_matcher.dart';
import 'parser_helpers.dart';

class JobExtractor {
  List<ScanResultRow> extract({
    required String html,
    required Uri sourceUrl,
    required String company,
    required List<String> terms,
  }) {
    final document = html_parser.parse(html);
    final found = <ScanResultRow>[];
    final seen = <String>{};

    bool passes(String title) {
      final lower = title.toLowerCase();
      return fuzzyMatch(lower, terms);
    }

    void addResult({
      required String title,
      required String apply,
      required String location,
      required String duration,
      required double months,
      required String source,
      String deadline = '—',
      String error = '',
    }) {
      final key = title.toLowerCase().substring(
        0,
        title.length > 40 ? 40 : title.length,
      );
      if (seen.contains(key)) return;
      seen.add(key);
      found.add(
        ScanResultRow(
          company: company,
          title: title,
          companyUrl: sourceUrl.toString(),
          applyLink: apply,
          location: location,
          duration: duration,
          deadline: deadline,
          source: source,
          error: error,
        ),
      );
    }

    _extractJsonLd(document, sourceUrl, passes, addResult);
    if (found.isNotEmpty) return found;

    _extractAts(document, sourceUrl, passes, addResult);
    if (found.isNotEmpty) return found;

    _extractTextScan(document, sourceUrl, terms, passes, addResult);
    return found;
  }

  void _extractJsonLd(
    Document doc,
    Uri sourceUrl,
    bool Function(String) passes,
    void Function({
      required String title,
      required String apply,
      required String location,
      required String duration,
      required double months,
      required String source,
      String deadline,
      String error,
    })
    addResult,
  ) {
    final scripts = doc.querySelectorAll('script[type="application/ld+json"]');
    for (final script in scripts) {
      final raw = script.text.trim();
      if (raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        final jobs = _flattenJsonLd(decoded);
        for (final item in jobs) {
          if (item['@type']?.toString().toLowerCase() != 'jobposting') {
            continue;
          }
          final title = (item['title'] ?? '').toString().trim();
          if (title.isEmpty || !passes(title)) continue;

          final description = (item['description'] ?? '').toString();
          final employmentType = (item['employmentType'] ?? '').toString();
          final durationData = parseDuration('$description $employmentType');

          var location = 'Not specified';
          final jobLocation = item['jobLocation'];
          final locations = <Map<String, dynamic>>[];
          if (jobLocation is Map<String, dynamic>) {
            locations.add(jobLocation);
          } else if (jobLocation is List) {
            locations.addAll(jobLocation.whereType<Map<String, dynamic>>());
          }

          for (final loc in locations) {
            final address = loc['address'];
            if (address is Map<String, dynamic>) {
              final locality = (address['addressLocality'] ?? '')
                  .toString()
                  .trim();
              if (locality.isNotEmpty) {
                location = locality;
                break;
              }
            }
          }
          if (location.trim().isEmpty) {
            location = parseLocation(description);
          }

          final apply = (item['url'] ?? sourceUrl.toString()).toString();
          final deadline = (item['validThrough'] ?? '—').toString();
          addResult(
            title: title,
            apply: apply,
            location: location,
            duration: durationData.$1,
            months: durationData.$2,
            source: 'schema.org',
            deadline: deadline.length >= 10
                ? deadline.substring(0, 10)
                : deadline,
          );
        }
      } catch (_) {}
    }
  }

  void _extractAts(
    Document doc,
    Uri sourceUrl,
    bool Function(String) passes,
    void Function({
      required String title,
      required String apply,
      required String location,
      required String duration,
      required double months,
      required String source,
      String deadline,
      String error,
    })
    addResult,
  ) {
    final selectors = <Map<String, String>>[
      {'c': 'div.opening', 't': 'a', 'l': 'a'},
      {'c': 'div.posting', 't': 'h5', 'l': 'a.posting-title'},
      {'c': 'li.job-listing', 't': 'h2,h3,h4', 'l': 'a'},
      {'c': 'div.job-card', 't': 'h2,h3,h4', 'l': 'a'},
      {'c': 'tr.job-row', 't': 'td.job-title', 'l': 'a'},
      {'c': '[data-automation="job-list-item"]', 't': 'h3,h4', 'l': 'a'},
      {'c': '[class*="JobCard"]', 't': 'h3,h4', 'l': 'a'},
      {'c': '[class*="job-item"]', 't': 'h3,h4', 'l': 'a'},
    ];

    for (final sel in selectors) {
      final containers = doc.querySelectorAll(sel['c']!);
      var addedFromSelector = false;
      for (final container in containers) {
        final te = container.querySelector(sel['t']!);
        final le = container.querySelector(sel['l']!);
        final title = te?.text.trim() ?? '';
        if (title.isEmpty || !passes(title)) continue;

        final context = container.text;
        final durationData = parseDuration(context);
        final href = le?.attributes['href'];
        final apply = href == null
            ? sourceUrl.toString()
            : sourceUrl.resolve(href).toString();

        addResult(
          title: title,
          apply: apply,
          location: parseLocation(context),
          duration: durationData.$1,
          months: durationData.$2,
          source: 'ATS HTML',
        );
        addedFromSelector = true;
      }
      if (addedFromSelector) {
        return;
      }
    }
  }

  void _extractTextScan(
    Document doc,
    Uri sourceUrl,
    List<String> terms,
    bool Function(String) passes,
    void Function({
      required String title,
      required String apply,
      required String location,
      required String duration,
      required double months,
      required String source,
      String deadline,
      String error,
    })
    addResult,
  ) {
    final lines = (doc.text ?? '')
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!passes(line)) continue;

      final start = i - 2 < 0 ? 0 : i - 2;
      final end = i + 5 >= lines.length ? lines.length : i + 5;
      final context = lines.sublist(start, end).join(' ');
      final durationData = parseDuration(context);

      final anchor = doc
          .querySelectorAll('a[href]')
          .firstWhere(
            (a) => fuzzyMatch(
              '${a.text} ${a.attributes['href'] ?? ''}'.toLowerCase(),
              terms,
            ),
            orElse: () => Element.tag('a'),
          );
      final href = anchor.attributes['href'];
      final apply = href == null
          ? sourceUrl.toString()
          : sourceUrl.resolve(href).toString();

      addResult(
        title: line.length > 120 ? line.substring(0, 120) : line,
        apply: apply,
        location: parseLocation(context),
        duration: durationData.$1,
        months: durationData.$2,
        source: 'Text scan',
      );
    }
  }

  List<Map<String, dynamic>> _flattenJsonLd(dynamic node) {
    final out = <Map<String, dynamic>>[];

    void walk(dynamic n) {
      if (n is Map<String, dynamic>) {
        out.add(n);
        final graph = n['@graph'];
        if (graph is List) {
          for (final g in graph) {
            walk(g);
          }
        }
      } else if (n is List) {
        for (final item in n) {
          walk(item);
        }
      }
    }

    walk(node);
    return out;
  }
}
