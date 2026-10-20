package com.aegiscore.av

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build

/** Version-safe PackageManager helpers (API 26..34). */
object PmCompat {

    @Suppress("DEPRECATION")
    fun installedPackages(pm: PackageManager, flags: Int): List<PackageInfo> =
        if (Build.VERSION.SDK_INT >= 33)
            pm.getInstalledPackages(PackageManager.PackageInfoFlags.of(flags.toLong()))
        else
            pm.getInstalledPackages(flags)

    @Suppress("DEPRECATION")
    fun packageInfo(pm: PackageManager, pkg: String, flags: Int): PackageInfo? = try {
        if (Build.VERSION.SDK_INT >= 33)
            pm.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(flags.toLong()))
        else
            pm.getPackageInfo(pkg, flags)
    } catch (e: Exception) {
        null
    }

    /** Every package that exposes at least one CATEGORY_LAUNCHER activity. */
    @Suppress("DEPRECATION")
    fun launcherPackages(pm: PackageManager): Set<String> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val list = if (Build.VERSION.SDK_INT >= 33)
            pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0L))
        else
            pm.queryIntentActivities(intent, 0)
        return list.mapNotNull { it.activityInfo?.packageName }.toSet()
    }

    /** Installer of record (InstallSourceInfo on API 30+, legacy call below that). */
    @Suppress("DEPRECATION")
    fun installer(pm: PackageManager, pkg: String): String? = try {
        if (Build.VERSION.SDK_INT >= 30) {
            val info = pm.getInstallSourceInfo(pkg)
            info.installingPackageName ?: info.initiatingPackageName
        } else {
            pm.getInstallerPackageName(pkg)
        }
    } catch (e: Exception) {
        null
    }
}
