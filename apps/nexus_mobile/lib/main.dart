import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'src/models/company_row.dart';
import 'src/services/nexus_api_client.dart';
import 'src/state/scan_controller.dart';
import 'src/theme/nexus_theme.dart';

void main() {
  runApp(const NexusApp());
}

class NexusApp extends StatelessWidget {
  const NexusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ScanController(),
      child: Consumer<ScanController>(
        builder: (context, state, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'NEXUS',
            themeMode: state.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            darkTheme: nexusTheme(Brightness.dark),
            theme: nexusTheme(Brightness.light),
            home: const NexusHomePage(),
          );
        },
      ),
    );
  }
}

class NexusHomePage extends StatelessWidget {
  const NexusHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ScanController>();
    final isCompactTopBar = MediaQuery.sizeOf(context).width < 430;
    final isDark = state.isDarkMode;
    final textColor = isDark ? NexusPalette.darkBody : NexusPalette.lightBody;
    final bright = isDark ? NexusPalette.darkBright : NexusPalette.lightBright;
    final panel = isDark ? NexusPalette.darkPanel : NexusPalette.lightPanel;
    final surface = isDark
        ? NexusPalette.darkSurface
        : NexusPalette.lightSurface;
    final border = isDark ? NexusPalette.darkBorder : NexusPalette.lightBorder;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        drawer: _NexusDrawer(state: state),
        appBar: AppBar(
          backgroundColor: surface,
          scrolledUnderElevation: 0,
          titleSpacing: 8,
          title: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: NexusPalette.cyan,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '? NEXUS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.syne(fontWeight: FontWeight.w800),
                ),
              ),
              if (!isCompactTopBar) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '/ Web3 Radar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmMono(
                      fontSize: 12,
                      color: NexusPalette.dim,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            if (!isCompactTopBar)
              _Badge(
                text: state.isScanning ? 'LIVE' : 'IDLE',
                fg: state.isScanning ? NexusPalette.green : NexusPalette.dim,
              ),
            if (!isCompactTopBar) const SizedBox(width: 8),
            if (!isCompactTopBar)
              const _Badge(text: 'v4.1.0', fg: NexusPalette.cyan),
            IconButton(
              onPressed: state.toggleTheme,
              icon: Icon(state.isDarkMode ? Icons.light_mode : Icons.dark_mode),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TALENT RADAR - WEB3 EDITION',
                      style: GoogleFonts.dmMono(
                        color: NexusPalette.cyan,
                        fontSize: 12,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'Find every '),
                          TextSpan(
                            text: 'open internship',
                            style: TextStyle(
                              foreground: Paint()
                                ..shader =
                                    const LinearGradient(
                                      colors: [
                                        NexusPalette.cyan,
                                        NexusPalette.violet,
                                      ],
                                    ).createShader(
                                      const Rect.fromLTWH(0, 0, 240, 20),
                                    ),
                            ),
                          ),
                          const TextSpan(text: ' in Web3.'),
                        ],
                      ),
                      style: GoogleFonts.syne(
                        color: bright,
                        fontSize: 30,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Upload your company list and NEXUS auto-discovers career pages, runs 3-layer extraction, and returns structured internship results.',
                      style: TextStyle(color: textColor),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 20,
                      children: const [
                        _HeroStat(value: '3x', label: 'Detection layers'),
                        _HeroStat(value: '12', label: 'User-Agent strings'),
                        _HeroStat(value: '8', label: 'Companies'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _StepIndicator(active: state.activeStep),
              const SizedBox(height: 14),
              _ActionBar(state: state),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricCard(
                    label: 'Scanned',
                    value: '${state.metrics['scanned'] ?? 0}',
                    color: NexusPalette.cyan,
                    icon: '?',
                  ),
                  _MetricCard(
                    label: 'Found',
                    value: '${state.metrics['hits'] ?? 0}',
                    color: NexusPalette.violet,
                    icon: '?',
                  ),
                  _MetricCard(
                    label: 'Errors',
                    value: '${state.metrics['errors'] ?? 0}',
                    color: NexusPalette.amber,
                    icon: '?',
                  ),
                  _MetricCard(
                    label: 'Remote',
                    value: '${state.metrics['remote'] ?? 0}',
                    color: NexusPalette.green,
                    icon: '?',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _TrackerCard(state: state),
              const SizedBox(height: 14),
              _TerminalCard(state: state),
              const SizedBox(height: 14),
              if (state.uploadedCompanies.isEmpty)
                _FeatureGrid(
                  panel: panel,
                  border: border,
                  textColor: textColor,
                ),
              if (state.uploadedCompanies.isNotEmpty) ...[
                const TabBar(
                  tabs: [
                    Tab(text: '? Internships'),
                    Tab(text: '? No Listings'),
                    Tab(text: '? Errors'),
                  ],
                ),
                SizedBox(
                  height: 380,
                  child: TabBarView(
                    children: [
                      _ResultsList(rows: state.hits, enableSeenFilter: true),
                      _ResultsList(rows: state.misses),
                      _ResultsList(rows: state.errors),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _ExportBar(state: state),
              ],
              const SizedBox(height: 12),
              Text(
                'NEXUS v4.1.0 - Web3 Talent Intelligence � ${DateTime.now()}',
                style: GoogleFonts.dmMono(
                  fontSize: 11,
                  color: NexusPalette.dim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.state});

  final ScanController state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: state.pickFile,
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload CSV/XLSX'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: state.isScanning || state.uploadedCompanies.isEmpty
                ? null
                : state.startScan,
            icon: const Icon(Icons.play_arrow),
            label: Text(state.isScanning ? 'Scanning...' : 'Launch Scan'),
          ),
        ),
      ],
    );
  }
}

class _TrackerCard extends StatelessWidget {
  const _TrackerCard({required this.state});

  final ScanController state;

  @override
  Widget build(BuildContext context) {
    if (state.scanTargets.isEmpty) return const SizedBox.shrink();

    final isDark = state.isDarkMode;
    final panel = isDark ? NexusPalette.darkPanel : NexusPalette.lightPanel;
    final border = isDark ? NexusPalette.darkBorder : NexusPalette.lightBorder;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Company Scan Status',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: state.scanProgress),
          const SizedBox(height: 6),
          Text(
            '${state.doneCount + state.errorCount}/${state.scanTargets.length} done � current: ${state.currentCompany.isEmpty ? '�' : state.currentCompany}',
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 170,
            child: ListView.builder(
              itemCount: state.scanTargets.length,
              itemBuilder: (context, index) {
                final company = state.scanTargets[index];
                final s =
                    state.companyStatus[company.trim().toLowerCase()] ??
                    'pending';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(company),
                  leading: Icon(
                    s == 'done'
                        ? Icons.check_circle
                        : s == 'no-listing'
                        ? Icons.remove_circle
                        : s == 'error'
                        ? Icons.error
                        : Icons.schedule,
                    color: s == 'done'
                        ? NexusPalette.green
                        : s == 'no-listing'
                        ? NexusPalette.dim
                        : s == 'error'
                        ? NexusPalette.rose
                        : NexusPalette.cyan,
                  ),
                  trailing: _Badge(
                    text: s == 'no-listing' ? 'NO LISTING' : s.toUpperCase(),
                    fg: s == 'done'
                        ? NexusPalette.green
                        : s == 'error'
                        ? NexusPalette.rose
                        : s == 'no-listing'
                        ? NexusPalette.dim
                        : NexusPalette.cyan,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalCard extends StatelessWidget {
  const _TerminalCard({required this.state});

  final ScanController state;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF030508),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexusPalette.darkBorder),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Color(0xFF161B2E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                _dot(const Color(0xFFFF5F57)),
                const SizedBox(width: 6),
                _dot(const Color(0xFFFFBD2E)),
                const SizedBox(width: 6),
                _dot(const Color(0xFF28C940)),
                const SizedBox(width: 10),
                Text(
                  'nexus-scanner // stdout',
                  style: GoogleFonts.dmMono(
                    color: NexusPalette.dim,
                    fontSize: 11,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 150,
            child: ListView.builder(
              itemCount: state.logLines.length,
              itemBuilder: (context, index) {
                final e = state.logLines[index];
                final kind = (e['kind'] ?? '').toString();
                var color = NexusPalette.darkBody;
                if (kind == 'hit') color = NexusPalette.green;
                if (kind == 'error') color = NexusPalette.rose;
                if (kind == 'miss') color = NexusPalette.dim;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  child: Text(
                    '${e['message'] ?? ''}',
                    style: GoogleFonts.dmMono(color: color, fontSize: 12),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Widget _dot(Color c) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );
}

class _ResultsList extends StatefulWidget {
  const _ResultsList({required this.rows, this.enableSeenFilter = false});

  final List<ScanResultRow> rows;
  final bool enableSeenFilter;

  @override
  State<_ResultsList> createState() => _ResultsListState();
}

enum _SeenFilter { all, newOnly, seenOnly }

class _ResultsListState extends State<_ResultsList> {
  _SeenFilter _filter = _SeenFilter.all;

  List<ScanResultRow> _visibleRows() {
    if (!widget.enableSeenFilter) return widget.rows;
    switch (_filter) {
      case _SeenFilter.newOnly:
        return widget.rows.where((r) => r.isNew).toList(growable: false);
      case _SeenFilter.seenOnly:
        return widget.rows.where((r) => r.isSeenBefore).toList(growable: false);
      case _SeenFilter.all:
        return widget.rows;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) return const Center(child: Text('No data'));
    final visible = _visibleRows();

    return Column(
      children: [
        if (widget.enableSeenFilter)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: _filter == _SeenFilter.all,
                  onSelected: (_) => setState(() => _filter = _SeenFilter.all),
                ),
                ChoiceChip(
                  label: const Text('New'),
                  selected: _filter == _SeenFilter.newOnly,
                  onSelected: (_) =>
                      setState(() => _filter = _SeenFilter.newOnly),
                ),
                ChoiceChip(
                  label: const Text('Seen'),
                  selected: _filter == _SeenFilter.seenOnly,
                  onSelected: (_) =>
                      setState(() => _filter = _SeenFilter.seenOnly),
                ),
              ],
            ),
          ),
        if (visible.isEmpty)
          const Expanded(child: Center(child: Text('No data for this filter')))
        else
          Expanded(
            child: ListView.separated(
              itemCount: visible.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final r = visible[i];
                return ListTile(
                  onTap: r.applyLink.isEmpty ? null : () => _open(r.applyLink),
                  title: Row(
                    children: [
                      Expanded(child: Text(r.title)),
                      if (r.isNew)
                        const _Badge(text: 'NEW', fg: NexusPalette.green),
                      if (r.isSeenBefore)
                        const _Badge(text: 'SEEN', fg: NexusPalette.dim),
                    ],
                  ),
                  subtitle: Text('${r.company} � ${r.location} � ${r.source}'),
                  trailing: Text(r.duration),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _open(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({
    required this.panel,
    required this.border,
    required this.textColor,
  });

  final Color panel;
  final Color border;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final items = const [
      (
        '?',
        'Career Page Discovery',
        'Finds likely career URLs and homepage job links.',
      ),
      (
        '?',
        '3-Layer Extraction',
        'schema.org -> ATS HTML -> Text scan fallback.',
      ),
      ('?', 'Parallel Scanning', 'Scans many companies concurrently.'),
      ('??', 'Polite Crawling', 'robots-aware with per-domain backoff.'),
      ('?', 'Smart Matching', 'Fuzzy match with typo tolerance.'),
      ('?', 'Actionable Results', 'Tabs for hits, misses, and errors.'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 760 ? 1 : 2;
        final aspect = crossAxisCount == 1 ? 2.15 : 1.45;

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: aspect,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemBuilder: (context, i) {
            final item = items[i];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.$1, style: const TextStyle(fontSize: 20)),
                  const SizedBox(height: 4),
                  Text(
                    item.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.syne(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Text(
                      item.$3,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: textColor, fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _NexusDrawer extends StatelessWidget {
  const _NexusDrawer({required this.state});

  final ScanController state;

  @override
  Widget build(BuildContext context) {
    final kwCtrl = TextEditingController(text: state.keywords);
    final exCtrl = TextEditingController(text: state.excludes);

    return Drawer(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '? NEXUS',
            style: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 20),
          ),
          Text(
            'Talent Intelligence Platform',
            style: GoogleFonts.dmMono(fontSize: 11, color: NexusPalette.dim),
          ),
          const SizedBox(height: 12),
          const Text('Appearance'),
          const SizedBox(height: 6),
          FilledButton(
            onPressed: state.toggleTheme,
            child: Text(
              state.isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            ),
          ),
          const SizedBox(height: 10),
          const Text('Search Parameters'),
          const SizedBox(height: 6),
          TextField(
            controller: kwCtrl,
            onChanged: state.setKeywords,
            decoration: const InputDecoration(labelText: 'Keywords'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: exCtrl,
            onChanged: state.setExcludes,
            decoration: const InputDecoration(labelText: 'Exclude Keywords'),
          ),
          const SizedBox(height: 10),
          const Text('Scan Configuration'),
          const SizedBox(height: 6),
          Text(
            'Engine: In-app local mode (no backend server required)',
            style: GoogleFonts.dmMono(fontSize: 11, color: NexusPalette.dim),
          ),
          const SizedBox(height: 8),
          Text('Max Duration: ${state.maxDuration} months'),
          Slider(
            value: state.maxDuration.toDouble(),
            min: 0,
            max: 18,
            divisions: 18,
            onChanged: state.setMaxDuration,
          ),
          Text('Companies to Scan: ${state.scanLimit}'),
          Slider(
            value: state.scanLimit.toDouble(),
            min: 1,
            max: 200,
            divisions: 199,
            onChanged: state.setScanLimit,
          ),
          Text('Parallel Workers: ${state.workers}'),
          Slider(
            value: state.workers.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            onChanged: state.setWorkers,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: state.pickFile,
            icon: const Icon(Icons.file_open),
            label: const Text('Choose Data File'),
          ),
        ],
      ),
    );
  }
}

class _ExportBar extends StatelessWidget {
  const _ExportBar({required this.state});

  final ScanController state;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton(
          onPressed: () => _shareAll(state),
          child: const Text('All Results (CSV)'),
        ),
        OutlinedButton(
          onPressed: () => _shareHits(state),
          child: const Text('Hits Only (CSV)'),
        ),
      ],
    );
  }

  Future<void> _shareAll(ScanController state) async {
    final runId = state.runId;
    if (runId == null) return;
    final client = NexusApiClient(state.apiUrl.trim());
    final csv = await client.downloadAllCsv(runId);
    await _shareTextFile(csv, 'nexus_all.csv');
  }

  Future<void> _shareHits(ScanController state) async {
    final rows = [
      ['Company', 'Title', 'Location', 'Duration', 'Source', 'Apply Link'],
      ...state.hits.map(
        (r) => [
          r.company,
          r.title,
          r.location,
          r.duration,
          r.source,
          r.applyLink,
        ],
      ),
    ];
    final csv = const ListToCsvConverter().convert(rows);
    await _shareTextFile(csv, 'nexus_hits.csv');
  }

  Future<void> _shareTextFile(String content, String filename) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content, encoding: utf8);
    await Share.shareXFiles([XFile(file.path)]);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.fg});

  final String text;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: GoogleFonts.dmMono(
          fontSize: 11,
          color: fg,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.active});

  final int active;

  @override
  Widget build(BuildContext context) {
    final labels = ['Upload list', 'Configure', 'Launch scan', 'Export'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          _StepNode(index: i + 1, active: active, label: labels[i]),
          if (i < labels.length - 1)
            Expanded(
              child: Divider(
                color: Theme.of(context).dividerColor,
                thickness: 1,
              ),
            ),
        ],
      ],
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({
    required this.index,
    required this.active,
    required this.label,
  });

  final int index;
  final int active;
  final String label;

  @override
  Widget build(BuildContext context) {
    final done = index < active;
    final isActive = index == active;
    return Column(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? NexusPalette.cyan
                : done
                ? NexusPalette.green.withValues(alpha: 0.2)
                : Colors.transparent,
            border: Border.all(
              color: done
                  ? NexusPalette.green
                  : isActive
                  ? NexusPalette.cyan
                  : NexusPalette.dim,
            ),
          ),
          child: Text(
            done ? '?' : '$index',
            style: TextStyle(
              color: isActive
                  ? Colors.black
                  : (done ? NexusPalette.green : NexusPalette.dim),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.dmSans(fontSize: 12)),
      ],
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: GoogleFonts.syne(fontWeight: FontWeight.w800, fontSize: 26),
        ),
        Text(
          label,
          style: GoogleFonts.dmMono(fontSize: 11, color: NexusPalette.dim),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? NexusPalette.darkPanel : NexusPalette.lightPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? NexusPalette.darkBorder : NexusPalette.lightBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 2, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.syne(
              fontWeight: FontWeight.w800,
              fontSize: 28,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.dmMono(fontSize: 11, color: NexusPalette.dim),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              icon,
              style: TextStyle(
                color: color.withValues(alpha: 0.25),
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
