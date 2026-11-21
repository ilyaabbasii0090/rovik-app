package com.rovikvpn.app

import android.content.Intent
import android.net.TrafficStats
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

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
                    "installedApps" -> result.success(installedApps())
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("NATIVE_ERROR", e.message, null)
            }
        }
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
