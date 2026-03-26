import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
    final width = MediaQuery.sizeOf(context).width;
    final resultsPanelHeight = width < 440
        ? 920.0
        : width < 760
        ? 860.0
        : 760.0;
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
              _ProfileSetupCard(state: state),
              const SizedBox(height: 14),
              _AlertsCard(state: state),
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
                    label: 'New',
                    value: '${state.newOpenings}',
                    color: NexusPalette.green,
                    icon: '+',
                  ),
                  _MetricCard(
                    label: 'Seen',
                    value: '${state.metrics['seenBefore'] ?? 0}',
                    color: NexusPalette.dim,
                    icon: 'S',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _TrackerCard(state: state),
              const SizedBox(height: 14),
              _LiveBrowserCard(state: state),
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
                  height: resultsPanelHeight,
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        if (compact) {
          return Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: state.pickFile,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload CSV/XLSX'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
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
      },
    );
  }
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard({required this.state});

  final ScanController state;

  @override
  Widget build(BuildContext context) {
    if (state.alerts.isEmpty) return const SizedBox.shrink();
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
          Text('Alerts', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final a in state.alerts.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: _alertColor(a.level).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _alertColor(a.level).withValues(alpha: 0.45),
                  ),
                ),
                child: ListTile(
                  dense: true,
                  title: Text(a.title),
                  subtitle: Text(a.body),
                  trailing: IconButton(
                    onPressed: () => state.dismissAlert(a.id),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _alertColor(String level) {
    switch (level) {
      case 'success':
        return NexusPalette.green;
      case 'warning':
        return NexusPalette.amber;
      case 'error':
        return NexusPalette.rose;
      default:
        return NexusPalette.cyan;
    }
  }
}

class _ProfileSetupCard extends StatelessWidget {
  const _ProfileSetupCard({required this.state});

  final ScanController state;

  @override
  Widget build(BuildContext context) {
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
            'Role Match Profile (0-100 Score)',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'Upload/paste resume and preferences to score each role with explainable reasons.',
            style: GoogleFonts.dmMono(fontSize: 11, color: NexusPalette.dim),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: state.pickResumeFile,
                icon: const Icon(Icons.description_outlined),
                label: const Text('Upload Resume File'),
              ),
              _Badge(
                text: 'Chars: ${state.resumeText.trim().length}',
                fg: NexusPalette.cyan,
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: state.resumeText,
            minLines: 2,
            maxLines: 5,
            onChanged: state.setResumeText,
            decoration: const InputDecoration(
              labelText: 'Resume text (paste if upload not readable)',
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: state.profileSkillsInput,
            onChanged: state.setProfileSkillsInput,
            decoration: const InputDecoration(
              labelText: 'Skills (comma separated)',
              hintText: 'dart, flutter, sql, blockchain',
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: state.preferredRolesInput,
            onChanged: state.setPreferredRolesInput,
            decoration: const InputDecoration(
              labelText: 'Preferred roles (comma separated)',
              hintText: 'backend, software, mobile',
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: state.preferredLocationsInput,
            onChanged: state.setPreferredLocationsInput,
            decoration: const InputDecoration(
              labelText: 'Preferred locations (comma separated)',
              hintText: 'remote, bengaluru, pune',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: state.graduationYearInput,
                  keyboardType: TextInputType.number,
                  onChanged: state.setGraduationYearInput,
                  decoration: const InputDecoration(
                    labelText: 'Graduation year',
                    hintText: '2026',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: state.eligibleForWork,
                  onChanged: state.setEligibleForWork,
                  title: const Text('Eligible for work'),
                ),
              ),
            ],
          ),
        ],
      ),
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
            '${state.doneCount + state.errorCount}/${state.scanTargets.length} done - current: ${state.currentCompany.isEmpty ? '-' : state.currentCompany}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
                Expanded(
                  child: Text(
                    'nexus-scanner // stdout',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmMono(
                      color: NexusPalette.dim,
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
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

enum _ScoreBandFilter {
  all,
  above90,
  between70And89,
  below70,
  eligibilityIssue,
}

enum _ScoreSort { scoreHighToLow, scoreLowToHigh }

class _ResultsListState extends State<_ResultsList> {
  _SeenFilter _filter = _SeenFilter.all;
  _ScoreBandFilter _scoreBandFilter = _ScoreBandFilter.all;
  _ScoreSort _scoreSort = _ScoreSort.scoreHighToLow;
  String _query = '';
  String _source = 'All';
  String _location = 'All';
  bool _atsOnly = false;

  List<String> _sourceOptions() {
    final set = widget.rows.map((r) => r.source).toSet().toList()..sort();
    return ['All', ...set];
  }

  List<String> _locationOptions() {
    final set = widget.rows.map((r) => r.location).toSet().toList()..sort();
    return ['All', ...set];
  }

  List<ScanResultRow> _visibleRows() {
    var rows = widget.rows;
    if (widget.enableSeenFilter) {
      switch (_filter) {
        case _SeenFilter.newOnly:
          rows = rows.where((r) => r.isNew).toList(growable: false);
          break;
        case _SeenFilter.seenOnly:
          rows = rows.where((r) => r.isSeenBefore).toList(growable: false);
          break;
        case _SeenFilter.all:
          break;
      }
    }

    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      rows = rows
          .where(
            (r) =>
                r.title.toLowerCase().contains(q) ||
                r.company.toLowerCase().contains(q) ||
                r.location.toLowerCase().contains(q) ||
                r.source.toLowerCase().contains(q),
          )
          .toList(growable: false);
    }

    if (_source != 'All') {
      rows = rows.where((r) => r.source == _source).toList(growable: false);
    }
    if (_location != 'All') {
      rows = rows.where((r) => r.location == _location).toList(growable: false);
    }
    if (_atsOnly) {
      rows = rows
          .where(
            (r) =>
                r.source.contains('greenhouse') ||
                r.source.contains('lever') ||
                r.source.contains('ashby'),
          )
          .toList(growable: false);
    }

    if (widget.enableSeenFilter) {
      switch (_scoreBandFilter) {
        case _ScoreBandFilter.above90:
          rows = rows.where((r) => r.fitScore >= 90).toList(growable: false);
          break;
        case _ScoreBandFilter.between70And89:
          rows = rows
              .where((r) => r.fitScore >= 70 && r.fitScore <= 89)
              .toList(growable: false);
          break;
        case _ScoreBandFilter.below70:
          rows = rows.where((r) => r.fitScore < 70).toList(growable: false);
          break;
        case _ScoreBandFilter.eligibilityIssue:
          rows = rows.where((r) => r.eligibilityIssue).toList(growable: false);
          break;
        case _ScoreBandFilter.all:
          break;
      }

      rows = [...rows]
        ..sort((a, b) {
          if (_scoreSort == _ScoreSort.scoreLowToHigh) {
            return a.fitScore.compareTo(b.fitScore);
          }
          return b.fitScore.compareTo(a.fitScore);
        });
    }

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) return const Center(child: Text('No data'));
    final visible = _visibleRows();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dropdownText = TextStyle(
      color: isDark ? NexusPalette.darkBright : NexusPalette.lightBright,
    );
    final dropdownBg = isDark
        ? NexusPalette.darkPanel
        : NexusPalette.lightSurface;
    final dropdownIcon = isDark
        ? NexusPalette.darkBright
        : NexusPalette.lightBright;

    return Column(
      children: [
        if (widget.enableSeenFilter)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _filter == _SeenFilter.all,
                        onSelected: (_) =>
                            setState(() => _filter = _SeenFilter.all),
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
                      FilterChip(
                        label: const Text('ATS only'),
                        selected: _atsOnly,
                        onSelected: (v) => setState(() => _atsOnly = v),
                      ),
                      ChoiceChip(
                        label: const Text('90+'),
                        selected: _scoreBandFilter == _ScoreBandFilter.above90,
                        onSelected: (_) => setState(
                          () => _scoreBandFilter = _ScoreBandFilter.above90,
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('70-89'),
                        selected:
                            _scoreBandFilter == _ScoreBandFilter.between70And89,
                        onSelected: (_) => setState(
                          () => _scoreBandFilter =
                              _ScoreBandFilter.between70And89,
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('<70'),
                        selected: _scoreBandFilter == _ScoreBandFilter.below70,
                        onSelected: (_) => setState(
                          () => _scoreBandFilter = _ScoreBandFilter.below70,
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('Eligibility issue'),
                        selected:
                            _scoreBandFilter ==
                            _ScoreBandFilter.eligibilityIssue,
                        onSelected: (_) => setState(
                          () => _scoreBandFilter =
                              _ScoreBandFilter.eligibilityIssue,
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('All scores'),
                        selected: _scoreBandFilter == _ScoreBandFilter.all,
                        onSelected: (_) => setState(
                          () => _scoreBandFilter = _ScoreBandFilter.all,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<_ScoreSort>(
                    value: _scoreSort,
                    style: dropdownText,
                    dropdownColor: dropdownBg,
                    iconEnabledColor: dropdownIcon,
                    decoration: const InputDecoration(labelText: 'Score sort'),
                    items: const [
                      DropdownMenuItem<_ScoreSort>(
                        value: _ScoreSort.scoreHighToLow,
                        child: Text('Score: high to low'),
                      ),
                      DropdownMenuItem<_ScoreSort>(
                        value: _ScoreSort.scoreLowToHigh,
                        child: Text('Score: low to high'),
                      ),
                    ],
                    onChanged: (v) => setState(
                      () => _scoreSort = v ?? _ScoreSort.scoreHighToLow,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      labelText: 'Smart search (title/company/source/location)',
                      hintText: 'Try: intern, remote, coinbase, greenhouse',
                      helperText:
                          'Matches title, company, source, and location keywords.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 520;
                      if (compact) {
                        return Column(
                          children: [
                            DropdownButtonFormField<String>(
                              value: _source,
                              style: dropdownText,
                              dropdownColor: dropdownBg,
                              iconEnabledColor: dropdownIcon,
                              decoration: const InputDecoration(
                                labelText: 'Source',
                              ),
                              items: _sourceOptions()
                                  .map(
                                    (s) => DropdownMenuItem<String>(
                                      value: s,
                                      child: Text(
                                        s,
                                        style: dropdownText,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _source = v ?? 'All'),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              value: _location,
                              style: dropdownText,
                              dropdownColor: dropdownBg,
                              iconEnabledColor: dropdownIcon,
                              decoration: const InputDecoration(
                                labelText: 'Location',
                              ),
                              items: _locationOptions()
                                  .map(
                                    (s) => DropdownMenuItem<String>(
                                      value: s,
                                      child: Text(
                                        s,
                                        style: dropdownText,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _location = v ?? 'All'),
                            ),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _source,
                              style: dropdownText,
                              dropdownColor: dropdownBg,
                              iconEnabledColor: dropdownIcon,
                              decoration: const InputDecoration(
                                labelText: 'Source',
                              ),
                              items: _sourceOptions()
                                  .map(
                                    (s) => DropdownMenuItem<String>(
                                      value: s,
                                      child: Text(
                                        s,
                                        style: dropdownText,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _source = v ?? 'All'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _location,
                              style: dropdownText,
                              dropdownColor: dropdownBg,
                              iconEnabledColor: dropdownIcon,
                              decoration: const InputDecoration(
                                labelText: 'Location',
                              ),
                              items: _locationOptions()
                                  .map(
                                    (s) => DropdownMenuItem<String>(
                                      value: s,
                                      child: Text(
                                        s,
                                        style: dropdownText,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _location = v ?? 'All'),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
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
                      if (r.fitScore > 0)
                        _Badge(
                          text: '${r.fitScore}',
                          fg: r.fitScore >= 85
                              ? NexusPalette.green
                              : r.fitScore >= 70
                              ? NexusPalette.cyan
                              : r.fitScore >= 50
                              ? NexusPalette.amber
                              : NexusPalette.rose,
                        ),
                      const SizedBox(width: 6),
                      if (r.fitScore > 0)
                        IconButton(
                          onPressed: () => _showScoreWhy(context, r),
                          icon: const Icon(Icons.info_outline, size: 18),
                          tooltip: 'Why this score',
                        ),
                      if (r.isNew)
                        const _Badge(text: 'NEW', fg: NexusPalette.green),
                      if (r.isSeenBefore)
                        const _Badge(text: 'SEEN', fg: NexusPalette.dim),
                    ],
                  ),
                  subtitle: Text(
                    '${r.company} - ${r.location} - ${r.source}${r.fitLabel.isNotEmpty ? ' - ${r.fitLabel}' : ''}',
                  ),
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

  Future<void> _showScoreWhy(BuildContext context, ScanResultRow r) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Why this score? ${r.fitScore}/100',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(r.title),
                const SizedBox(height: 10),
                for (final line in r.scoreWhy)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('- $line'),
                  ),
              ],
            ),
          ),
        );
      },
    );
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
          TextFormField(
            initialValue: state.keywords,
            onChanged: state.setKeywords,
            decoration: const InputDecoration(labelText: 'Keywords'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: state.excludes,
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

class _LiveBrowserCard extends StatefulWidget {
  const _LiveBrowserCard({required this.state});

  final ScanController state;

  @override
  State<_LiveBrowserCard> createState() => _LiveBrowserCardState();
}

class _LiveBrowserCardState extends State<_LiveBrowserCard> {
  WebViewController? _web;
  String _loadedUrl = '';
  bool _isBrowserExpanded = false;

  bool get _supportsEmbeddedBrowser => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.scanTargets.isEmpty) return const SizedBox.shrink();

    final isDark = state.isDarkMode;
    final panel = isDark ? NexusPalette.darkPanel : NexusPalette.lightPanel;
    final border = isDark ? NexusPalette.darkBorder : NexusPalette.lightBorder;

    final target = state.currentCompanyUrl.trim();
    if (_supportsEmbeddedBrowser && target.isNotEmpty && target != _loadedUrl) {
      _loadedUrl = target;
      _web ??= WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              _fitPageToBox();
              Future<void>.delayed(
                const Duration(milliseconds: 350),
                _fitPageToBox,
              );
              Future<void>.delayed(
                const Duration(milliseconds: 1200),
                _fitPageToBox,
              );
            },
          ),
        );
      _web!.loadRequest(Uri.parse(target));
    }

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
          Row(
            children: [
              Expanded(
                child: Text(
                  'Live Scrape Browser',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _isBrowserExpanded = !_isBrowserExpanded;
                  });
                },
                tooltip: _isBrowserExpanded
                    ? 'Minimize to box'
                    : 'Maximize browser',
                icon: Icon(
                  _isBrowserExpanded ? Icons.fullscreen_exit : Icons.fullscreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            state.currentCompany.isEmpty
                ? 'Waiting for next company...'
                : 'Now visiting: ${state.currentCompany}',
            style: GoogleFonts.dmMono(fontSize: 11, color: NexusPalette.dim),
          ),
          const SizedBox(height: 8),
          if (target.isNotEmpty)
            Text(
              target,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmMono(fontSize: 11, color: NexusPalette.cyan),
            ),
          if (target.isNotEmpty) const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              height: _browserHeight(context),
              color: Colors.black,
              child: !_supportsEmbeddedBrowser
                  ? const Center(
                      child: Text(
                        'Mini-browser preview is available on Android/iOS runtime.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : target.isEmpty
                  ? const Center(
                      child: Text(
                        'Start scan to watch pages load step-by-step.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : WebViewWidget(controller: _web!),
            ),
          ),
        ],
      ),
    );
  }

  double _browserHeight(BuildContext context) {
    const boxed = 360.0;
    if (!_isBrowserExpanded) return boxed;

    final screen = MediaQuery.sizeOf(context).height;
    var expanded = screen * 0.72;
    if (expanded < 420) expanded = 420;
    if (expanded > 760) expanded = 760;
    return expanded;
  }

  Future<void> _fitPageToBox() async {
    if (_web == null) return;
    try {
      await _web!.runJavaScript('''
        (function() {
          var doc = document.documentElement;
          var body = document.body;
          var head = document.head || document.getElementsByTagName('head')[0];
          if (!head) return;

          var meta = document.querySelector('meta[name="viewport"]');
          if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'viewport';
            head.appendChild(meta);
          }

          meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, shrink-to-fit=yes';

          if (!doc) return;

          var viewportWidth = window.innerWidth || 360;
          var contentWidth = Math.max(
            doc.scrollWidth || 0,
            body ? body.scrollWidth || 0 : 0,
            viewportWidth
          );

          var scale = viewportWidth / contentWidth;
          if (!isFinite(scale) || scale <= 0) scale = 1;
          if (scale > 1) scale = 1;
          if (scale < 0.45) scale = 0.45;

          doc.style.transformOrigin = 'top left';
          doc.style.transform = 'scale(' + scale + ')';
          doc.style.width = (100 / scale) + '%';
          doc.style.overflowX = 'hidden';

          if (body) {
            body.style.maxWidth = '100%';
            body.style.overflowX = 'hidden';
            body.style.transformOrigin = 'top left';
          }
        })();
      ''');
    } catch (_) {
      // Some pages block script injection; fallback is native WebView scaling.
    }
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _StepNode(index: i + 1, active: active, label: labels[i]),
            if (i < labels.length - 1)
              SizedBox(
                width: 48,
                child: Divider(
                  color: Theme.of(context).dividerColor,
                  thickness: 1,
                ),
              ),
          ],
        ],
      ),
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
    return SizedBox(
      width: 90,
      child: Column(
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
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(fontSize: 12),
          ),
        ],
      ),
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
