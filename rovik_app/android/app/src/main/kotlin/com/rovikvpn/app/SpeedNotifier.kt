package com.rovikvpn.app

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.net.TrafficStats
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import java.util.Locale

/**
 * سرعت زنده دانلود/آپلود داخل «همان» اعلان دائمی VPN.
 *
 * هیچ اعلان جدیدی ساخته نمی‌شود: اعلان فورگراندِ همین اپ (اعلان سرویس VPN
 * پلاگین، همراه دکمه «قطع اتصال») پیدا می‌شود و با همان شناسه/کانال و همان
 * اکشن‌ها فقط متنش عوض می‌شود. اگر چنین اعلانی پیدا نشود هیچ کاری نمی‌کند.
 *
 * محاسبه کاملاً نیتیو است و به زنده بودن UI فلاتر وابسته نیست (فرایند
 * اپ تا وقتی VPN وصل است زنده می‌ماند).
 */
object SpeedNotifier {
    private const val TICK_MS = 1000L

    private val handler = Handler(Looper.getMainLooper())
    private var running = false
    private var appCtx: Context? = null
    private var prevRx = -1L
    private var prevTx = -1L
    private var prevAt = 0L
    private var missed = 0

    private val tick = object : Runnable {
        override fun run() {
            if (!running) return
            try {
                doTick()
            } catch (_: Throwable) {
            }
            if (running) handler.postDelayed(this, TICK_MS)
        }
    }

    fun start(context: Context) {
        appCtx = context.applicationContext
        if (running) return
        running = true
        prevRx = -1L
        missed = 0
        handler.postDelayed(tick, TICK_MS)
    }

    fun stop() {
        running = false
        handler.removeCallbacks(tick)
    }

    private fun doTick() {
        val ctx = appCtx ?: return
        val uid = Process.myUid()
        val rx = TrafficStats.getUidRxBytes(uid)
        val tx = TrafficStats.getUidTxBytes(uid)
        if (rx < 0 || tx < 0) return
        val now = SystemClock.elapsedRealtime()
        val first = prevRx < 0
        val dtMs = now - prevAt
        val dRx = rx - prevRx
        val dTx = tx - prevTx
        prevRx = rx
        prevTx = tx
        prevAt = now
        if (first || dtMs < 200) return
        val down = maxOf(0L, dRx * 8 * 1000 / dtMs)
        val up = maxOf(0L, dTx * 8 * 1000 / dtMs)
        post(ctx, "↓ ${format(down)}  ↑ ${format(up)}")
    }

    private fun post(ctx: Context, text: String) {
        if (Build.VERSION.SDK_INT < 24) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        val sbn = nm.activeNotifications.firstOrNull {
            it.packageName == ctx.packageName &&
                (it.notification.flags and Notification.FLAG_FOREGROUND_SERVICE) != 0
        }
        if (sbn == null) {
            // اعلان VPN نیست (قطع شده یا اعلان‌ها خاموش‌اند): چیزی نمی‌سازیم.
            missed++
            if (missed >= 5) stop()
            return
        }
        missed = 0
        val rebuilt = Notification.Builder.recoverBuilder(ctx, sbn.notification)
            .setContentText(text)
            .setOnlyAlertOnce(true)
            .build()
        nm.notify(sbn.tag, sbn.id, rebuilt)
    }

    private fun fa(s: String): String {
        val sb = StringBuilder()
        for (ch in s) sb.append(if (ch in '0'..'9') ('۰' + (ch - '0')) else ch)
        return sb.toString()
    }

    /** بیت بر ثانیه → «۲٫۴ مگابیت/ثانیه» و … */
    fun format(bitsPerSecond: Long): String = when {
        bitsPerSecond >= 1_000_000 ->
            fa(String.format(Locale.US, "%.1f", bitsPerSecond / 1_000_000.0))
                .replace('.', '٫') + " مگابیت/ثانیه"
        bitsPerSecond >= 1_000 -> fa((bitsPerSecond / 1_000).toString()) + " کیلوبیت/ثانیه"
        else -> fa(bitsPerSecond.toString()) + " بیت/ثانیه"
    }
}
