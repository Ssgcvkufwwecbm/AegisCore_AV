package com.aegiscore.av

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object Notifier {
    const val CH_THREAT = "aegis_threats"
    const val CH_GUARD = "aegis_guard"
    const val GUARD_ID = 7001

    fun createChannels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        val threat = NotificationChannel(CH_THREAT, "Threat alerts", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Critical alerts when a newly installed app looks malicious"
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        val guard = NotificationChannel(CH_GUARD, "Install Guard", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Shown while real-time install monitoring is active"
        }
        nm.createNotificationChannel(threat)
        nm.createNotificationChannel(guard)
    }

    private fun openApp(ctx: Context, reports: Boolean): PendingIntent {
        val i = Intent(ctx, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(MainActivity.EXTRA_OPEN_REPORTS, reports)
        return PendingIntent.getActivity(
            ctx, if (reports) 1 else 0, i,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    fun guardNotification(ctx: Context): Notification =
        NotificationCompat.Builder(ctx, CH_GUARD)
            .setSmallIcon(R.drawable.ic_shield)
            .setContentTitle("Install Guard active")
            .setContentText("Scanning new and updated apps in real time")
            .setOngoing(true)
            .setContentIntent(openApp(ctx, false))
            .build()

    fun threat(ctx: Context, r: AppReport) {
        val top = r.indicators.sortedByDescending { it.severity }.take(5)
        val body = top.joinToString("\n") { "\u2022 ${it.title}" }
        val uninstall = PendingIntent.getActivity(
            ctx, r.packageName.hashCode(), QuarantineController.uninstallIntent(r.packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val n = NotificationCompat.Builder(ctx, CH_THREAT)
            .setSmallIcon(R.drawable.ic_shield)
            .setContentTitle("${r.severity.name} threat: ${r.label}")
            .setContentText(top.firstOrNull()?.title ?: "Suspicious behaviour detected")
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ERROR)
            .setColor(0xFFFF1744.toInt())
            .setAutoCancel(true)
            .setContentIntent(openApp(ctx, true))
            .addAction(0, "Uninstall", uninstall)
            .build()
        try {
            NotificationManagerCompat.from(ctx).notify(r.packageName.hashCode(), n)
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS not granted
        }
    }
}
