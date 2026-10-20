package com.aegiscore.av

import android.Manifest
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.view.accessibility.AccessibilityManager
import androidx.core.app.NotificationManagerCompat

/**
 * Device-state audit. Build one instance per scan: it snapshots the launcher set, enabled
 * accessibility services, enabled notification listeners and active device admins once.
 */
class BehavioralScanner(private val ctx: Context) {

    private val pm: PackageManager = ctx.packageManager
    private val appOps: AppOpsManager? = ctx.getSystemService(AppOpsManager::class.java)

    private val launcherPkgs: Set<String> =
        runCatching { PmCompat.launcherPackages(pm) }.getOrDefault(emptySet())

    /** package -> description of its enabled accessibility service */
    private val a11y: Map<String, String> = loadAccessibility()

    private val listeners: Set<String> =
        runCatching { NotificationManagerCompat.getEnabledListenerPackages(ctx) }.getOrDefault(emptySet())

    private val admins: Set<String> = runCatching {
        ctx.getSystemService(DevicePolicyManager::class.java)
            ?.activeAdmins?.map { it.packageName }?.toSet() ?: emptySet()
    }.getOrDefault(emptySet())

    private fun loadAccessibility(): Map<String, String> = try {
        val am = ctx.getSystemService(AccessibilityManager::class.java)
        val map = HashMap<String, String>()
        for (info in am.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)) {
            val si = info.resolveInfo?.serviceInfo ?: continue
            val readsScreen =
                (info.capabilities and AccessibilityServiceInfo.CAPABILITY_CAN_RETRIEVE_WINDOW_CONTENT) != 0
            val caps = if (readsScreen) "can read screen content" else "limited capabilities"
            map[si.packageName] = "${si.name.substringAfterLast('.')} ($caps)"
        }
        map
    } catch (e: Exception) {
        emptyMap()
    }

    private fun grantedPerm(pi: PackageInfo, perm: String): Boolean {
        val perms = pi.requestedPermissions ?: return false
        val flags = pi.requestedPermissionsFlags ?: return false
        val i = perms.indexOf(perm)
        return i >= 0 && i < flags.size && (flags[i] and PackageInfo.REQUESTED_PERMISSION_GRANTED) != 0
    }

    @Suppress("DEPRECATION")
    private fun overlayAllowed(pi: PackageInfo): Boolean {
        val uid = pi.applicationInfo?.uid ?: return false
        val mode = try {
            val ops = appOps
            if (ops == null) AppOpsManager.MODE_DEFAULT
            else if (Build.VERSION.SDK_INT >= 29)
                ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW, uid, pi.packageName)
            else
                ops.checkOpNoThrow(AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW, uid, pi.packageName)
        } catch (e: Exception) {
            AppOpsManager.MODE_DEFAULT
        }
        return mode == AppOpsManager.MODE_ALLOWED ||
            pm.checkPermission(Manifest.permission.SYSTEM_ALERT_WINDOW, pi.packageName) ==
            PackageManager.PERMISSION_GRANTED
    }

    fun audit(pi: PackageInfo): List<Indicator> {
        val out = ArrayList<Indicator>()
        val ai = pi.applicationInfo ?: return out
        val pkg = pi.packageName
        val isSystem = (ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0
        val requested = pi.requestedPermissions?.toSet() ?: emptySet()

        val ghost = !isSystem && pkg !in launcherPkgs
        val a11yDesc = a11y[pkg]
        val hasListener = pkg in listeners
        val isAdmin = pkg in admins
        val installer = PmCompat.installer(pm, pkg)
        val sideloaded = !isSystem && installer != PLAY_STORE && (installer == null || installer !in ALT_STORES)

        // 1. Ghost apps
        if (ghost) {
            out += Indicator(
                "Ghost app (no launcher icon)",
                "A user-installed app with no CATEGORY_LAUNCHER activity is invisible in the app drawer. " +
                    "Stalkerware hides this way; some legitimate keyboards, widgets and companion apps do too.",
                Severity.LOW, 8
            )
        }

        // 2. Install source
        if (!isSystem) {
            if (installer == PLAY_STORE) {
                // trusted channel, nothing to report
            } else if (installer != null && installer in ALT_STORES) {
                out += Indicator(
                    "Installed from an alternative store",
                    "Installer of record: $installer. It was not distributed through Google Play, so Play Protect never vetted it.",
                    Severity.LOW, 5
                )
            } else {
                out += Indicator(
                    "Sideloaded app",
                    "Install source is ${installer ?: "unknown (ADB or direct file install)"}, not $PLAY_STORE. " +
                        "Sideloading is the dominant infection route for banking trojans and stalkerware.",
                    Severity.MEDIUM, 15
                )
            }
        }

        // 3. Accessibility service cross-reference
        if (a11yDesc != null && !isSystem) {
            out += Indicator(
                "Accessibility service enabled",
                "$a11yDesc. An enabled accessibility service can read the screen, capture taps and keystrokes and click on the user's behalf.",
                Severity.MEDIUM, 15
            )
            if (Manifest.permission.SYSTEM_ALERT_WINDOW in requested) {
                val allowed = overlayAllowed(pi)
                out += Indicator(
                    "Banking-overlay trojan profile",
                    "BIND_ACCESSIBILITY_SERVICE (enabled) + SYSTEM_ALERT_WINDOW (${if (allowed) "granted" else "requested"}). " +
                        "This pairing lets malware draw a fake login screen over a banking app while the accessibility service reads and injects input.",
                    if (allowed) Severity.CRITICAL else Severity.HIGH,
                    if (allowed) 65 else 45
                )
            }
            if (sideloaded) {
                out += Indicator(
                    "Sideloaded app controls accessibility",
                    "An app that did not come from a store holds an active accessibility service. Dropper families ask victims to enable exactly this right after install.",
                    Severity.HIGH, 30
                )
            }
        }

        // 4. Notification listener cross-reference
        if (hasListener && !isSystem) {
            out += Indicator(
                "Notification access enabled",
                "The app can read every notification, including one-time codes and chat previews.",
                Severity.MEDIUM, 12
            )
            val sms = listOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS).filter { it in requested }
            if (sms.isNotEmpty()) {
                val granted = sms.any { grantedPerm(pi, it) }
                out += Indicator(
                    "OTP-stealer profile",
                    "BIND_NOTIFICATION_LISTENER_SERVICE (enabled) + ${sms.joinToString { it.substringAfterLast('.') }} " +
                        "(${if (granted) "granted" else "requested"}). Reading both notifications and SMS lets malware capture 2FA codes and hide them from the victim.",
                    if (granted) Severity.CRITICAL else Severity.HIGH,
                    if (granted) 60 else 40
                )
            }
        }

        // 5. Device administrator
        if (isAdmin && !isSystem) {
            out += Indicator(
                "Active device administrator",
                "This app is an enabled device admin, so it can resist uninstall, lock the screen and wipe data. Stalkerware and ransomware abuse this for persistence.",
                if (ghost) Severity.HIGH else Severity.MEDIUM,
                if (ghost) 40 else 20
            )
        }

        // 6. Stalkerware composite
        val surveillance = SURVEILLANCE_PERMS.filter { grantedPerm(pi, it) }
        val persistent = a11yDesc != null || hasListener || isAdmin
        if (ghost && surveillance.size >= 3) {
            out += Indicator(
                "Stalkerware permission set on a hidden app",
                "No launcher icon and ${surveillance.size} surveillance permissions granted: " +
                    surveillance.joinToString { it.substringAfterLast('.') } + ".",
                Severity.HIGH, 40
            )
        }
        if (ghost && persistent && surveillance.size >= 2) {
            out += Indicator(
                "Stalkerware profile: hidden + persistent + surveillance",
                "Hidden from the launcher, holds an accessibility/notification/admin foothold and has granted access to ${surveillance.joinToString { it.substringAfterLast('.') }}. This is the textbook stalkerware footprint.",
                Severity.CRITICAL, 60
            )
        }
        return out
    }

    companion object {
        const val PLAY_STORE = "com.android.vending"

        private val ALT_STORES = setOf(
            "com.sec.android.app.samsungapps", "com.amazon.venezia", "com.huawei.appmarket",
            "org.fdroid.fdroid", "com.xiaomi.mipicks", "com.heytap.market", "com.vivo.appstore",
            "com.aurora.store"
        )

        private val SURVEILLANCE_PERMS = listOf(
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.CAMERA,
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION,
            Manifest.permission.READ_SMS,
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.READ_CALL_LOG,
            Manifest.permission.READ_CONTACTS
        )
    }
}
