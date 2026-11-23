package com.rovikvpn.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * اجرای اتصال/قطع VPN بدون باز شدن اپ: یک موتور Flutter هدلس بالا می‌آید و
 * تابع `tileMain` دارت (lib/main.dart) را اجرا می‌کند؛ آن همان VpnEngine اپ
 * را با همان مسیر connectWithFallback صدا می‌زند. بعد از پایان کار موتور
 * هدلس نابود می‌شود (سرویس VPN پلاگین جدا از آن زنده می‌ماند).
 */
object HeadlessVpn {
    private const val TILE_CHANNEL = "com.rovikvpn.app/tile"
    private const val TIMEOUT_MS = 60_000L

    private val handler = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var timeout: Runnable? = null

    val isRunning: Boolean get() = engine != null

    fun run(context: Context, action: String) {
        if (engine != null) return
        val app = context.applicationContext
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)

        val eng = FlutterEngine(app)
        engine = eng
        val messenger = eng.dartExecutor.binaryMessenger
        NativeChannel(app).register(messenger)
        MethodChannel(messenger, TILE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "command" -> result.success(action)
                "done" -> {
                    val ok = call.argument<Boolean>("ok") == true
                    val message = call.argument<String>("message")
                    result.success(null)
                    finish(app, action, ok, message)
                }
                else -> result.notImplemented()
            }
        }
        eng.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "tileMain")
        )
        val t = Runnable { finish(app, action, false, "اتصال زمان‌بر شد؛ از داخل اپ امتحان کن.") }
        timeout = t
        handler.postDelayed(t, TIMEOUT_MS)
    }

    private fun finish(app: Context, action: String, ok: Boolean, message: String?) {
        timeout?.let { handler.removeCallbacks(it) }
        timeout = null
        val eng = engine ?: return
        if (ok && action == "connect") SpeedNotifier.start(app)
        if (action == "disconnect") SpeedNotifier.stop()
        if (!ok && !message.isNullOrBlank()) {
            Toast.makeText(app, message, Toast.LENGTH_LONG).show()
        }
        // کمی صبر تا پلاگین کارش با موتور تمام شود، بعد موتور هدلس را ببند.
        handler.postDelayed({
            try {
                eng.destroy()
            } catch (_: Throwable) {
            }
            if (engine === eng) engine = null
        }, 600)
    }
}
