import 'package:home_widget/home_widget.dart';

class HomeWidgetService {
  HomeWidgetService._();

  static final HomeWidgetService instance = HomeWidgetService._();

  static const String androidWidgetName = 'NexusHomeWidgetProvider';
  static const String iOSWidgetName = 'NexusHomeWidget';

  Future<void> updateCounts({
    required int newCount,
    required int seenCount,
  }) async {
    try {
      await HomeWidget.saveWidgetData<int>('newCount', newCount);
      await HomeWidget.saveWidgetData<int>('seenCount', seenCount);
      await HomeWidget.updateWidget(
        androidName: androidWidgetName,
        iOSName: iOSWidgetName,
      );
    } catch (_) {
      // Widget updates should not crash the app.
    }
  }
}
