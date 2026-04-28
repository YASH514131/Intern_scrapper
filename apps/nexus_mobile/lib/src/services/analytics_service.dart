import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics? get analyticsOrNull {
    try {
      return FirebaseAnalytics.instance;
    } catch (_) {
      return null;
    }
  }

  Future<void> configureDefaultTracking() async {
    final analytics = analyticsOrNull;
    if (analytics == null) return;
    try {
      await analytics.setAnalyticsCollectionEnabled(true);
      await analytics.setSessionTimeoutDuration(const Duration(minutes: 30));
      await analytics.setUserProperty(name: 'app_name', value: 'nexus_mobile');
      await analytics.logAppOpen();
      await analytics.logScreenView(
        screenName: 'home_setup',
        screenClass: 'NexusHomePage',
      );
    } catch (_) {
      // Ignore analytics errors to avoid affecting scan flow.
    }
  }

  Future<void> logScanStarted(String companyName) async {
    await _safeLog(
      name: 'scan_started',
      parameters: <String, Object>{'company_hint': companyName},
    );
  }

  Future<void> logScanCompleted({
    required int hits,
    required int errors,
    required int misses,
    required int newOpenings,
  }) async {
    await _safeLog(
      name: 'scan_completed',
      parameters: <String, Object>{
        'hits': hits,
        'errors': errors,
        'misses': misses,
        'new_openings': newOpenings,
      },
    );
  }

  Future<void> logScanFailed(String reason) async {
    await _safeLog(
      name: 'scan_failed',
      parameters: <String, Object>{'reason': reason},
    );
  }

  Future<void> logCompaniesUploaded({
    required int count,
    required String fileType,
  }) async {
    await _safeLog(
      name: 'company_list_uploaded',
      parameters: <String, Object>{'count': count, 'file_type': fileType},
    );
  }

  Future<void> logStageViewed(String stage) async {
    final screenName = 'stage_$stage';
    await _safeLog(
      name: 'stage_viewed',
      parameters: <String, Object>{'stage': stage},
    );
    final analytics = analyticsOrNull;
    if (analytics == null) return;
    try {
      await analytics.logScreenView(
        screenName: screenName,
        screenClass: 'NexusHomePage',
      );
    } catch (_) {
      // Ignore analytics errors to avoid affecting UI flow.
    }
  }

  Future<void> logConfigurationUpdated({
    required int workers,
    required int scanLimit,
  }) async {
    await _safeLog(
      name: 'scan_config_updated',
      parameters: <String, Object>{'workers': workers, 'scan_limit': scanLimit},
    );
  }

  Future<void> logResultsExported({required String exportType}) async {
    await _safeLog(
      name: 'results_exported',
      parameters: <String, Object>{'export_type': exportType},
    );
  }

  Future<void> logJobViewed(String jobTitle, String company) async {
    await _safeLog(
      name: 'job_viewed',
      parameters: <String, Object>{
        'job_title_hint': jobTitle,
        'company_hint': company,
      },
    );
  }

  Future<void> logWidgetTapped() async {
    await _safeLog(name: 'home_widget_tapped');
  }

  Future<void> _safeLog({
    required String name,
    Map<String, Object>? parameters,
  }) async {
    final analytics = analyticsOrNull;
    if (analytics == null) return;
    try {
      await analytics.logEvent(name: name, parameters: parameters);
    } catch (_) {
      // Ignore analytics errors to avoid affecting scan flow.
    }
  }
}
