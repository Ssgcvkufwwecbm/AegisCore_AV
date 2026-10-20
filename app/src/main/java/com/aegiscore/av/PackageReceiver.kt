package com.aegiscore.av

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap

/** Scans one package right after install/update, stores the report and alerts on HIGH/CRITICAL. */
object InstallGuard {
    fun inspect(ctx: Context, pkg: String) {
        val pi = PmCompat.packageInfo(ctx.packageManager, pkg, PackageManager.GET_PERMISSIONS) ?: return
        val report = ScanCoordinator.scanOne(ctx, pi, BehavioralScanner(ctx))
        ReportStore.upsert(ctx, report)
        if (report.severity >= Severity.HIGH) Notifier.threat(ctx, report)
    }
}

/**
 * Receives ACTION_PACKAGE_ADDED / ACTION_PACKAGE_REPLACED. Registered both in the manifest and,
 * while the Install Guard is on, dynamically from GuardService (so it keeps working when the OS
 * stops delivering package broadcasts to manifest receivers). Duplicate deliveries are collapsed.
 */
class PackageReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_PACKAGE_ADDED && action != Intent.ACTION_PACKAGE_REPLACED) return
        val pkg = intent.data?.schemeSpecificPart ?: return
        if (pkg == context.packageName) return
        // An update fires ADDED(replacing=true) followed by REPLACED: handle it once, on REPLACED.
        if (action == Intent.ACTION_PACKAGE_ADDED && intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)) return
        if (!firstSighting(pkg)) return

        val app = context.applicationContext
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                InstallGuard.inspect(app, pkg)
            } catch (t: Throwable) {
                // never crash the receiver
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        private val seen = ConcurrentHashMap<String, Long>()

        private fun firstSighting(pkg: String): Boolean {
            val now = SystemClock.elapsedRealtime()
            val prev = seen.put(pkg, now)
            return prev == null || now - prev > 10_000
        }
    }
}

/** Foreground service whose only job is to host the dynamic package receiver. */
class GuardService : Service() {

    private val receiver = PackageReceiver()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val n = Notifier.guardNotification(this)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(Notifier.GUARD_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(Notifier.GUARD_ID, n)
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REPLACED)
            addDataScheme("package")
        }
        ContextCompat.registerReceiver(this, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        try { unregisterReceiver(receiver) } catch (e: Exception) { }
        super.onDestroy()
    }
}

/** Restarts the Install Guard after a reboot when the user had it enabled. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!Prefs.guardEnabled(context)) return
        try {
            ContextCompat.startForegroundService(context, Intent(context, GuardService::class.java))
        } catch (t: Throwable) {
            // OS refused a background foreground-service start; the guard restarts when the app is opened
        }
    }
}
