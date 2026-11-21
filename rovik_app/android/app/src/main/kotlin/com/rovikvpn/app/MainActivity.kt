package com.rovikvpn.app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.net.TrafficStats
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var lastForeground: String? = null
    private var lastQueryAt: Long = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.rovikvpn.app/native"
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "trafficBytes" -> {
                        val uid = Process.myUid()
                        result.success(
                            listOf(
                                TrafficStats.getUidRxBytes(uid),
                                TrafficStats.getUidTxBytes(uid)
                            )
                        )
                    }
                    "hasUsageAccess" -> result.success(hasUsageAccess())
                    "openUsageAccessSettings" -> {
                        val i = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(null)
                    }
                    "foregroundPackage" -> result.success(foregroundPackage())
                    "installedApps" -> result.success(installedApps())
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("NATIVE_ERROR", e.message, null)
            }
        }
    }

    private fun hasUsageAccess(): Boolean {
        val ops = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        @Suppress("DEPRECATION")
        val mode = ops.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** آخرین اپی که جلوی صفحه آمده (از UsageEvents). */
    private fun foregroundPackage(): String? {
        if (!hasUsageAccess()) return null
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val from = if (lastQueryAt == 0L) now - 60_000L else lastQueryAt - 1_000L
        val events = usm.queryEvents(from, now)
        val e = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(e)
            // 1 = ACTIVITY_RESUMED (= MOVE_TO_FOREGROUND قدیمی)
            if (e.eventType == 1) {
                lastForeground = e.packageName
            }
        }
        lastQueryAt = now
        return lastForeground
    }

    private fun installedApps(): List<Map<String, String>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val seen = HashSet<String>()
        val out = ArrayList<Map<String, String>>()
        for (ri in pm.queryIntentActivities(intent, 0)) {
            val pkg = ri.activityInfo.packageName
            if (pkg == packageName || !seen.add(pkg)) continue
            out.add(mapOf("package" to pkg, "label" to ri.loadLabel(pm).toString()))
        }
        out.sortBy { it["label"]?.lowercase() ?: "" }
        return out
    }
}
