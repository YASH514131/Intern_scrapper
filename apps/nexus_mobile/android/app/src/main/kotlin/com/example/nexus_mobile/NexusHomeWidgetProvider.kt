package com.nexus.jobscanner

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class NexusHomeWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.home_widget_layout)

            val newCount = widgetData.getInt("newCount", 0)
            val seenCount = widgetData.getInt("seenCount", 0)

            views.setTextViewText(R.id.widget_new_count, newCount.toString())
            views.setTextViewText(R.id.widget_seen_count, seenCount.toString())

            if (newCount > 0) {
                views.setInt(
                    R.id.widget_scan_button,
                    "setBackgroundResource",
                    R.drawable.home_widget_scan_bg_alert
                )
                views.setTextViewText(R.id.widget_scan_button, "Start Scan  •  $newCount New")
            } else {
                views.setInt(
                    R.id.widget_scan_button,
                    "setBackgroundResource",
                    R.drawable.home_widget_scan_bg
                )
                views.setTextViewText(R.id.widget_scan_button, "Start Scan")
            }

            val launchIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java
            )
            val scanIntent = HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("nexus://scan")
            )
            views.setOnClickPendingIntent(R.id.widget_root, launchIntent)
            views.setOnClickPendingIntent(R.id.widget_scan_button, scanIntent)

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
