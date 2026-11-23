package com.rovikvpn.app

import android.app.PendingIntent
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * کاشی تنظیمات سریع «RovikVpn»: با یک لمس VPN را روشن/خاموش می‌کند، بدون
 * باز شدن اپ. وضعیت کاشی از وضعیت واقعی شبکه‌ی VPN سیستم خوانده می‌شود و
 * با هر تغییر به‌روز می‌شود.
 *
 * تنها استثنا: اگر مجوز VPN هنوز هیچ‌وقت داده نشده باشد (اولین استفاده)،
 * اندروید فقط از داخل یک اکتیویتی اجازه می‌دهد؛ در آن حالت یک بار اپ باز
 * می‌شود تا کاربر مجوز را بدهد.
 */
class RovikTileService : TileService() {

    private val main = Handler(Looper.getMainLooper())
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var connecting = false

    override fun onStartListening() {
        super.onStartListening()
        registerCallback()
        refreshTile()
    }

    override fun onStopListening() {
        unregisterCallback()
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        if (HeadlessVpn.isRunning) return
        if (isVpnUp()) {
            connecting = true
            setTile(Tile.STATE_INACTIVE, "در حال قطع…")
            HeadlessVpn.run(applicationContext, "disconnect")
            return
        }
        if (VpnService.prepare(this) != null) {
            openApp()
            return
        }
        connecting = true
        setTile(Tile.STATE_ACTIVE, "در حال اتصال…")
        HeadlessVpn.run(applicationContext, "connect")
    }

    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (Build.VERSION.SDK_INT >= 34) {
            val pi = PendingIntent.getActivity(
                this, 0, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            startActivityAndCollapse(pi)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun isVpnUp(): Boolean {
        val cm = getSystemService(CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        @Suppress("DEPRECATION")
        for (n in cm.allNetworks) {
            val c = cm.getNetworkCapabilities(n) ?: continue
            if (c.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) return true
        }
        return false
    }

    private fun refreshTile() {
        connecting = false
        if (isVpnUp()) setTile(Tile.STATE_ACTIVE, "متصل")
        else setTile(Tile.STATE_INACTIVE, "قطع")
    }

    private fun setTile(state: Int, subtitle: String) {
        val tile = qsTile ?: return
        tile.state = state
        tile.label = "RovikVpn"
        if (Build.VERSION.SDK_INT >= 29) tile.subtitle = subtitle
        tile.updateTile()
    }

    private fun registerCallback() {
        if (callback != null) return
        val cm = getSystemService(CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                main.post { refreshTile() }
            }

            override fun onLost(network: Network) {
                main.post { refreshTile() }
            }
        }
        val req = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_VPN)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        try {
            cm.registerNetworkCallback(req, cb)
            callback = cb
        } catch (_: Throwable) {
        }
    }

    private fun unregisterCallback() {
        val cb = callback ?: return
        callback = null
        try {
            (getSystemService(CONNECTIVITY_SERVICE) as? ConnectivityManager)
                ?.unregisterNetworkCallback(cb)
        } catch (_: Throwable) {
        }
    }
}
