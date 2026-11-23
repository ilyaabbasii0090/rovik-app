package com.rovikvpn.app

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Process
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * کانال نیتیو مشترک بین MainActivity و موتور هدلس کاشی (RovikTileService).
 * هیچ‌کدام از متدها مجوز خطرناک نمی‌خواهند.
 */
class NativeChannel(private val context: Context) {

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
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
                    "networkInfo" -> result.success(networkInfo())
                    "speedNotifier" -> {
                        if (call.argument<Boolean>("enabled") == true) {
                            SpeedNotifier.start(context)
                        } else {
                            SpeedNotifier.stop()
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("NATIVE_ERROR", e.message, null)
            }
        }
    }

    private fun installedApps(): List<Map<String, String>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val seen = HashSet<String>()
        val out = ArrayList<Map<String, String>>()
        for (ri in pm.queryIntentActivities(intent, 0)) {
            val pkg = ri.activityInfo.packageName
            if (pkg == context.packageName || !seen.add(pkg)) continue
            out.add(mapOf("package" to pkg, "label" to ri.loadLabel(pm).toString()))
        }
        out.sortBy { it["label"]?.lowercase() ?: "" }
        return out
    }

    /**
     * شبکه فیزیکی فعلی (وای‌فای یا دیتا) برای «حافظه هوشمند سرور».
     * شبکه‌های VPN نادیده گرفته می‌شوند تا وقتی VPN وصل است هم جواب درست بدهد.
     * SSID بدون مجوز مکان در اندروید جدید در دسترس نیست؛ در آن حالت خالی
     * برمی‌گردد و سمت دارت به «wifi» برمی‌گردد (مجوز مکان درخواست نمی‌شود).
     */
    @Suppress("DEPRECATION")
    private fun networkInfo(): Map<String, String> {
        val out = HashMap<String, String>()
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        var wifi = false
        var cell = false
        if (cm != null) {
            for (n in cm.allNetworks) {
                val c = cm.getNetworkCapabilities(n) ?: continue
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
                if (c.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) wifi = true
                else if (c.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) cell = true
            }
        }
        out["transport"] = if (wifi) "wifi" else if (cell) "mobile" else "none"
        if (wifi) {
            try {
                val wm = context.applicationContext
                    .getSystemService(Context.WIFI_SERVICE) as? WifiManager
                var ssid = wm?.connectionInfo?.ssid ?: ""
                ssid = ssid.trim().removeSurrounding("\"")
                if (ssid.isNotEmpty() && ssid != "<unknown ssid>" && ssid != "0x") {
                    out["ssid"] = ssid
                }
            } catch (_: Throwable) {
            }
        }
        if (cell) {
            try {
                var tm = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                if (tm != null && Build.VERSION.SDK_INT >= 24) {
                    val id = SubscriptionManager.getDefaultDataSubscriptionId()
                    if (id != SubscriptionManager.INVALID_SUBSCRIPTION_ID) {
                        tm = tm.createForSubscriptionId(id)
                    }
                }
                var name = tm?.networkOperatorName ?: ""
                if (name.isBlank()) name = tm?.simOperatorName ?: ""
                if (name.isNotBlank()) out["operator"] = name.trim()
            } catch (_: Throwable) {
            }
        }
        return out
    }

    companion object {
        const val CHANNEL = "com.rovikvpn.app/native"
    }
}
