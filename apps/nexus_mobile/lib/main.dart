import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:home_widget/home_widget.dart';
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

class NexusHomePage extends StatefulWidget {
  const NexusHomePage({super.key});

  @override
  State<NexusHomePage> createState() => _NexusHomePageState();
}

class _NexusHomePageState extends State<NexusHomePage> {
  StreamSubscription<Uri?>? _widgetClickSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _wireHomeWidgetLaunches();
    });
  }

  @override
  void dispose() {
    _widgetClickSub?.cancel();
    super.dispose();
  }

  Future<void> _wireHomeWidgetLaunches() async {
    await _handleHomeWidgetUri(
      await HomeWidget.initiallyLaunchedFromHomeWidget(),
    );
    _widgetClickSub ??= HomeWidget.widgetClicked.listen((uri) {
      unawaited(_handleHomeWidgetUri(uri));
    });
  }

  Future<void> _handleHomeWidgetUri(Uri? uri) async {
    if (!mounted || uri == null) return;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final shouldStartScan =
        host == 'scan' || path.contains('/scan') || path == 'scan';
    await context.read<ScanController>().handleHomeWidgetTap(
      startScanIfRequested: shouldStartScan,
    );
  }

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

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 8,
        title: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NexusPalette.violet.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: NexusPalette.violet),
              ),
              child: Text(
                'N',
                style: GoogleFonts.dmMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: NexusPalette.lightBright,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'NEXUS',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.syne(fontWeight: FontWeight.w800),
              ),
            ),
            if (!isCompactTopBar) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  '/ Web3 Radar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmMono(
                    fontSize: 13,
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
            const _Badge(text: 'v4.1.0', fg: NexusPalette.violet),
          const SizedBox(width: 4),
          IconButton(
            onPressed: state.toggleTheme,
            icon: Icon(state.isDarkMode ? Icons.light_mode : Icons.dark_mode),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: isDark ? const Color(0xFF04060E) : const Color(0xFFF5F7FB),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _GridBackdrop(isDark: isDark)),
            ),
          ),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const SizedBox(height: 8),
                _StageTabs(
                  active: state.activeStep,
                  onTap: state.setActiveStep,
                  scanBlinkOn: state.scanTabBlinkOn,
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (velocity < -90 && state.activeStep < 3) {
                      state.setActiveStep(state.activeStep + 1);
                    } else if (velocity > 90 && state.activeStep > 1) {
                      state.setActiveStep(state.activeStep - 1);
                    }
                  },
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey<int>(state.activeStep),
                    tween: Tween<double>(begin: 0.97, end: 1.0),
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      final forward = state.activeStep >= state.previousStep;
                      final slideFactor = (1 - value) * (forward ? 14 : -14);
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(slideFactor, 0),
                          child: child,
                        ),
                      );
                    },
                    child: IndexedStack(
                      index: state.activeStep - 1,
                      children: [
                        _SetupSection(
                          key: const ValueKey<int>(1),
                          state: state,
                          surface: surface,
                          border: border,
                          textColor: textColor,
                          bright: bright,
                        ),
                        _ScanSection(key: const ValueKey<int>(2), state: state),
                        _ResultsSection(
                          key: const ValueKey<int>(3),
                          state: state,
                          panel: panel,
                          border: border,
                          textColor: textColor,
                          resultsPanelHeight: resultsPanelHeight,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'NEXUS v4.1.0 - Web3 Talent Intelligence - ${DateTime.now()}',
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    color: NexusPalette.dim,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StageTabs extends StatelessWidget {
  const _StageTabs({
    required this.active,
    required this.onTap,
    required this.scanBlinkOn,
  });

  final int active;
  final ValueChanged<int> onTap;
  final bool scanBlinkOn;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = active.clamp(1, 3);
    final shellColor = isDark
        ? const Color(0xAA111527)
        : const Color(0xCCEAF0FB);
    final shellBorder = isDark
        ? const Color(0xFF313754)
        : const Color(0xFFC6D0EB);
    final activeBg = isDark ? const Color(0xFF000000) : const Color(0xFF04060C);
    final activeBorder = isDark
        ? const Color(0xFF5E668C)
        : const Color(0xFFC6D0EE);
    final activeText = const Color(0xFFEFF3FF);
    final inactiveText = isDark
        ? const Color(0xFFCFD6F0)
        : const Color(0xFF434C69);
    final labels = ['Setup', 'Scan', 'Results'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: shellColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: shellBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onTap(i + 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: activeColor == i + 1
                        ? activeBg
                        : (i == 1 && scanBlinkOn)
                        ? NexusPalette.violet.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: activeColor == i + 1 || (i == 1 && scanBlinkOn)
                        ? Border.all(
                            color: activeColor == i + 1
                                ? activeBorder
                                : NexusPalette.violet.withValues(alpha: 0.8),
                          )
                        : null,
                    boxShadow: activeColor == i + 1 || (i == 1 && scanBlinkOn)
                        ? [
                            BoxShadow(
                              color: (i == 1 && scanBlinkOn)
                                  ? NexusPalette.violet.withValues(alpha: 0.42)
                                  : NexusPalette.violet.withValues(alpha: 0.22),
                              blurRadius: 16,
                              spreadRadius: -8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmMono(
                      fontSize: 14,
                      fontWeight:
                          activeColor == i + 1 || (i == 1 && scanBlinkOn)
                          ? FontWeight.w600
                          : FontWeight.w500,
                      letterSpacing: 0.45,
                      color: activeColor == i + 1
                          ? activeText
                          : (i == 1 && scanBlinkOn)
                          ? NexusPalette.lightBright
                          : inactiveText,
                    ),
                  ),
                ),
              ),
            ),
            if (i < labels.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _SetupSection extends StatelessWidget {
  const _SetupSection({
    required super.key,
    required this.state,
    required this.surface,
    required this.border,
    required this.textColor,
    required this.bright,
  });

  final ScanController state;
  final Color surface;
  final Color border;
  final Color textColor;
  final Color bright;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FrostedCard(
          padding: const EdgeInsets.all(18),
          radius: 18,
          borderColor: border,
          tint: state.isDarkMode
              ? const Color(0xA3101526)
              : surface.withValues(alpha: 0.82),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 30, height: 2, color: NexusPalette.violet),
                  const SizedBox(width: 8),
                  Text(
                    'TALENT RADAR - WEB3 EDITION',
                    style: GoogleFonts.dmMono(
                      color: NexusPalette.violet,
                      fontSize: 12,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
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
                          ..shader = const LinearGradient(
                            colors: [
                              NexusPalette.lightBright,
                              NexusPalette.violet,
                            ],
                          ).createShader(const Rect.fromLTWH(0, 0, 260, 24)),
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
              const SizedBox(height: 10),
              Text(
                'Upload your company list and NEXUS auto-discovers career pages, runs 3-layer extraction, and returns structured internship results.',
                style: TextStyle(color: textColor),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: _HeroStat(value: '3x', label: 'Detection layers'),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: _HeroStat(value: '12', label: 'User-Agent strings'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _HeroStat(
                      value: '${state.uploadedCompanies.length}',
                      label: 'Companies loaded',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _StepIndicator(active: state.activeStep),
        const SizedBox(height: 14),
        _InlineConfigureCard(state: state),
        const SizedBox(height: 14),
        _ActionBar(state: state),
      ],
    );
  }
}

class _InlineConfigureCard extends StatelessWidget {
  const _InlineConfigureCard({required this.state});

  final ScanController state;

  @override
  Widget build(BuildContext context) {
    final isDark = state.isDarkMode;
    final panel = isDark ? NexusPalette.darkPanel : NexusPalette.lightPanel;
    final border = isDark ? NexusPalette.darkBorder : NexusPalette.lightBorder;

    return _FrostedCard(
      padding: const EdgeInsets.all(14),
      radius: 16,
      borderColor: border,
      tint: isDark ? const Color(0xA3121728) : panel.withValues(alpha: 0.88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Configure', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: state.keywords,
            onChanged: state.setKeywords,
            decoration: const InputDecoration(labelText: 'Include Keywords'),
          ),
          const SizedBox(height: 10),
          TextFormField(
            initialValue: state.excludes,
            onChanged: state.setExcludes,
            decoration: const InputDecoration(labelText: 'Exclude Keywords'),
          ),
          const SizedBox(height: 12),
          Text(
            'Max duration: ${state.maxDuration} months',
            style: GoogleFonts.dmMono(fontSize: 12, color: NexusPalette.dim),
          ),
          Slider(
            value: state.maxDuration.toDouble(),
            min: 0,
            max: 18,
            divisions: 18,
            onChanged: state.setMaxDuration,
          ),
          Text(
            'Companies to scan: ${state.scanLimit}',
            style: GoogleFonts.dmMono(fontSize: 12, color: NexusPalette.dim),
          ),
          Slider(
            value: state.scanLimit.toDouble(),
            min: 1,
            max: state.maxScanLimit.toDouble(),
            divisions: state.maxScanLimit > 1 ? state.maxScanLimit - 1 : null,
            onChanged: state.setScanLimit,
          ),
          Text(
            'Parallel workers: ${state.workers}',
            style: GoogleFonts.dmMono(fontSize: 12, color: NexusPalette.dim),
          ),
          Slider(
            value: state.workers.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            onChanged: state.setWorkers,
          ),
        ],
      ),
    );
  }
}

class _ScanSection extends StatelessWidget {
  const _ScanSection({required super.key, required this.state});

  final ScanController state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricCard(
              label: 'Scanned',
              value: '${state.metrics['scanned'] ?? 0}',
              color: NexusPalette.cyan,
              icon: '#',
            ),
            _MetricCard(
              label: 'Found',
              value: '${state.metrics['hits'] ?? 0}',
              color: NexusPalette.violet,
              icon: '#',
            ),
            _MetricCard(
              label: 'Errors',
              value: '${state.metrics['errors'] ?? 0}',
              color: NexusPalette.amber,
              icon: '#',
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
        _TerminalCard(state: state),
        const SizedBox(height: 14),
        _LiveBrowserCard(state: state),
      ],
    );
  }
}

class _ResultsSection extends StatelessWidget {
  const _ResultsSection({
    required super.key,
    required this.state,
    required this.panel,
    required this.border,
    required this.textColor,
    required this.resultsPanelHeight,
  });

  final ScanController state;
  final Color panel;
  final Color border;
  final Color textColor;
  final double resultsPanelHeight;

  @override
  Widget build(BuildContext context) {
    if (state.uploadedCompanies.isEmpty) {
      return _FeatureGrid(panel: panel, border: border, textColor: textColor);
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Internships'),
              Tab(text: 'No Listings'),
              Tab(text: 'Errors'),
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
      ),
    );
  }
}

class _GridBackdrop extends CustomPainter {
  const _GridBackdrop({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final major = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(
        alpha: isDark ? 0.06 : 0.04,
      )
      ..strokeWidth = 1;
    final minor = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(
        alpha: isDark ? 0.03 : 0.02,
      )
      ..strokeWidth = 1;

    const majorStep = 76.0;
    const minorStep = 19.0;

    for (var x = 0.0; x <= size.width; x += minorStep) {
      final isMajor = (x / majorStep).roundToDouble() == (x / majorStep);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        isMajor ? major : minor,
      );
    }
    for (var y = 0.0; y <= size.height; y += minorStep) {
      final isMajor = (y / majorStep).roundToDouble() == (y / majorStep);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        isMajor ? major : minor,
      );
    }

    final glowA = Paint()
      ..shader =
          RadialGradient(
            colors: [
              NexusPalette.violet.withValues(alpha: 0.13),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.75, 140),
              radius: 260,
            ),
          );
    canvas.drawCircle(Offset(size.width * 0.75, 140), 260, glowA);

    final glowB = Paint()
      ..shader =
          RadialGradient(
            colors: [
              NexusPalette.cyan.withValues(alpha: 0.09),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.18, size.height * 0.55),
              radius: 220,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.18, size.height * 0.55),
      220,
      glowB,
    );
  }

  @override
  bool shouldRepaint(covariant _GridBackdrop oldDelegate) =>
      oldDelegate.isDark != isDark;
}

class _FrostedCard extends StatelessWidget {
  const _FrostedCard({
    required this.child,
    required this.borderColor,
    required this.tint,
    this.padding,
    this.radius = 16,
    this.width,
  });

  final Widget child;
  final Color borderColor;
  final Color tint;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tint.withValues(alpha: 0.88),
                tint.withValues(alpha: 0.62),
              ],
            ),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor.withValues(alpha: 0.95)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: child,
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
    final isDark = state.isDarkMode;
    final panel = isDark ? const Color(0xFF0F1322) : NexusPalette.lightSurface;
    final border = isDark ? const Color(0xFF2A3047) : NexusPalette.lightBorder;
    final subtle = isDark ? const Color(0xFF97A2C4) : const Color(0xFF5F6785);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        if (compact) {
          return Column(
            children: [
              InkWell(
                onTap: state.pickFile,
                borderRadius: BorderRadius.circular(16),
                child: _FrostedCard(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  radius: 16,
                  borderColor: border,
                  tint: isDark
                      ? const Color(0xA3121728)
                      : panel.withValues(alpha: 0.88),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF181D30),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: border),
                        ),
                        child: const Icon(Icons.upload_file, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Upload CSV / XLSX',
                              style: GoogleFonts.dmSans(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? NexusPalette.darkBright
                                    : NexusPalette.lightBright,
                                letterSpacing: -0.3,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Drag and drop, or click to browse one company per row',
                              style: GoogleFonts.dmMono(
                                fontSize: 11,
                                color: subtle,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: state.pickFile,
                        child: const Text('Browse'),
                      ),
                    ],
                  ),
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

        return Column(
          children: [
            InkWell(
              onTap: state.pickFile,
              borderRadius: BorderRadius.circular(16),
              child: _FrostedCard(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                radius: 16,
                borderColor: border,
                tint: isDark
                    ? const Color(0xA3121728)
                    : panel.withValues(alpha: 0.88),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF181D30),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: border),
                      ),
                      child: const Icon(Icons.upload_file, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Upload CSV / XLSX',
                            style: GoogleFonts.dmSans(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? NexusPalette.darkBright
                                  : NexusPalette.lightBright,
                              letterSpacing: -0.3,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Drag and drop, or click to browse one company per row',
                            style: GoogleFonts.dmMono(
                              fontSize: 11,
                              color: subtle,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: state.pickFile,
                      child: const Text('Browse'),
                    ),
                  ],
                ),
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
      },
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

    return _FrostedCard(
      padding: const EdgeInsets.all(12),
      radius: 16,
      borderColor: border,
      tint: isDark ? const Color(0xA3121728) : panel.withValues(alpha: 0.88),
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

class _TerminalCard extends StatefulWidget {
  const _TerminalCard({required this.state});

  final ScanController state;

  @override
  State<_TerminalCard> createState() => _TerminalCardState();
}

class _TerminalCardState extends State<_TerminalCard> {
  bool _isCollapsed = true;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
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
                IconButton(
                  onPressed: () {
                    setState(() {
                      _isCollapsed = !_isCollapsed;
                    });
                  },
                  tooltip: _isCollapsed ? 'Expand logs' : 'Collapse logs',
                  icon: Icon(
                    _isCollapsed
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    color: NexusPalette.dim,
                  ),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstCurve: Curves.easeOutCubic,
            secondCurve: Curves.easeOutCubic,
            sizeCurve: Curves.easeOutCubic,
            duration: const Duration(milliseconds: 220),
            crossFadeState: _isCollapsed
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: SizedBox(
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
            secondChild: const SizedBox.shrink(),
          ),
          if (_isCollapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Logs collapsed',
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    color: NexusPalette.dim,
                  ),
                ),
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
                    ],
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
                      if (r.isNew)
                        const _Badge(text: 'NEW', fg: NexusPalette.green),
                      if (r.isSeenBefore)
                        const _Badge(text: 'SEEN', fg: NexusPalette.dim),
                    ],
                  ),
                  subtitle: Text('${r.company} - ${r.location} - ${r.source}'),
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
  bool _isCollapsed = true;

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

    return _FrostedCard(
      padding: const EdgeInsets.all(12),
      radius: 16,
      borderColor: border,
      tint: isDark ? const Color(0xA3121728) : panel.withValues(alpha: 0.88),
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
              IconButton(
                onPressed: () {
                  setState(() {
                    _isCollapsed = !_isCollapsed;
                  });
                },
                tooltip: _isCollapsed
                    ? 'Expand live browser'
                    : 'Collapse live browser',
                icon: Icon(
                  _isCollapsed
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                ),
              ),
            ],
          ),
          AnimatedCrossFade(
            firstCurve: Curves.easeOutCubic,
            secondCurve: Curves.easeOutCubic,
            sizeCurve: Curves.easeOutCubic,
            duration: const Duration(milliseconds: 220),
            crossFadeState: _isCollapsed
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Text(
                  state.currentCompany.isEmpty
                      ? 'Waiting for next company...'
                      : 'Now visiting: ${state.currentCompany}',
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    color: NexusPalette.dim,
                  ),
                ),
                const SizedBox(height: 8),
                if (target.isNotEmpty)
                  Text(
                    target,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmMono(
                      fontSize: 11,
                      color: NexusPalette.cyan,
                    ),
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
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Live browser collapsed',
                style: GoogleFonts.dmMono(
                  fontSize: 11,
                  color: NexusPalette.dim,
                ),
              ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final connector = isDark
        ? const Color(0xFF343C56)
        : const Color(0xFFC9D4F1);
    final labels = ['Upload', 'Configure', 'Launch scan', 'Export'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _StepNode(index: i + 1, active: active, label: labels[i]),
            if (i < labels.length - 1)
              SizedBox(
                width: 48,
                child: Divider(color: connector, thickness: 1),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedText = isDark
        ? const Color(0xFFAAB3D0)
        : const Color(0xFF4A5272);
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
                  ? NexusPalette.violet
                  : done
                  ? NexusPalette.violet.withValues(alpha: 0.2)
                  : Colors.transparent,
              border: Border.all(
                color: done
                    ? NexusPalette.violet
                    : isActive
                    ? NexusPalette.violet
                    : NexusPalette.dim,
              ),
            ),
            child: done
                ? Icon(
                    Icons.check,
                    size: 14,
                    color: isActive ? Colors.black : NexusPalette.violet,
                  )
                : Text(
                    '$index',
                    style: TextStyle(
                      color: isActive ? Colors.black : mutedText,
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
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: isActive || done ? null : mutedText,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            ),
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
    return _FrostedCard(
      width: 170,
      padding: const EdgeInsets.all(12),
      radius: 14,
      borderColor: isDark ? NexusPalette.darkBorder : NexusPalette.lightBorder,
      tint: isDark
          ? const Color(0xA3121728)
          : NexusPalette.lightPanel.withValues(alpha: 0.88),
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
