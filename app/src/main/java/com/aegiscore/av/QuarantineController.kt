package com.aegiscore.av

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import rikka.shizuku.Shizuku

object QuarantineController {

    private const val SHIZUKU_REQUEST_CODE = 4242
    private val PKG_PATTERN = Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$")

    enum class ShizukuState { UNAVAILABLE, PERMISSION_NEEDED, READY }

    data class ShellResult(val command: String, val exitCode: Int, val output: String) {
        val ok: Boolean get() = exitCode == 0
    }

    fun isValidPackage(pkg: String): Boolean = PKG_PATTERN.matches(pkg)

    // ---- Standard (no privileges) actions ---------------------------------------------------
    private fun newTask(i: Intent): Intent = i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    fun uninstallIntent(pkg: String): Intent =
        newTask(Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg")))

    fun appInfoIntent(pkg: String): Intent =
        newTask(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg")))

    fun accessibilitySettingsIntent(): Intent =
        newTask(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))

    fun notificationListenerSettingsIntent(): Intent =
        newTask(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))

    fun overlaySettingsIntent(pkg: String): Intent =
        newTask(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$pkg")))

    /** Device-admin deactivation lives under Security settings on stock Android. */
    fun deviceAdminSettingsIntent(): Intent =
        newTask(Intent(Settings.ACTION_SECURITY_SETTINGS))

    // ---- Shizuku / ADB-level actions --------------------------------------------------------
    fun shizukuState(): ShizukuState = try {
        if (!Shizuku.pingBinder() || Shizuku.isPreV11()) ShizukuState.UNAVAILABLE
        else if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) ShizukuState.READY
        else ShizukuState.PERMISSION_NEEDED
    } catch (t: Throwable) {
        ShizukuState.UNAVAILABLE
    }

    fun requestShizukuPermission() {
        try {
            Shizuku.requestPermission(SHIZUKU_REQUEST_CODE)
        } catch (t: Throwable) {
            // Shizuku not running
        }
    }

    /** Shizuku 13 made newProcess private; it is still the supported way to run shell-uid commands. */
    private fun newProcess(cmd: Array<String>): Process {
        val m = Shizuku::class.java.getDeclaredMethod(
            "newProcess",
            Array<String>::class.java,
            Array<String>::class.java,
            String::class.java
        )
        m.isAccessible = true
        return m.invoke(null, cmd, null, null) as Process
    }

    /** Runs argv directly (no shell, so no injection surface) with Shizuku's shell/root identity. */
    fun execPrivileged(argv: List<String>): ShellResult {
        val label = argv.joinToString(" ")
        return try {
            val p = newProcess(argv.toTypedArray())
            val out = p.inputStream.bufferedReader().use { it.readText() }
            val err = p.errorStream.bufferedReader().use { it.readText() }
            val code = p.waitFor()
            ShellResult(label, code, (out + err).trim())
        } catch (t: Throwable) {
            ShellResult(label, -1, t.cause?.message ?: t.message ?: t.javaClass.simpleName)
        }
    }

    /**
     * Instantly neutralises a threat without uninstalling it:
     *   am force-stop <pkg>  ->  appops set <pkg> SYSTEM_ALERT_WINDOW ignore  ->  pm disable-user --user 0 <pkg>
     */
    fun neutralize(ctx: Context, pkg: String): List<ShellResult> {
        if (!isValidPackage(pkg)) return listOf(ShellResult("validate $pkg", -1, "invalid package name"))
        if (pkg == ctx.packageName) return listOf(ShellResult("validate $pkg", -1, "refusing to neutralise AegisCore itself"))
        if (shizukuState() != ShizukuState.READY) {
            return listOf(ShellResult("shizuku", -1, "Shizuku is not running or permission was not granted"))
        }
        return listOf(
            execPrivileged(listOf("am", "force-stop", pkg)),
            execPrivileged(listOf("appops", "set", pkg, "SYSTEM_ALERT_WINDOW", "ignore")),
            execPrivileged(listOf("pm", "disable-user", "--user", "0", pkg))
        )
    }

    /** Undo for a false positive. */
    fun restore(pkg: String): ShellResult =
        if (isValidPackage(pkg)) execPrivileged(listOf("pm", "enable", pkg))
        else ShellResult("pm enable $pkg", -1, "invalid package name")

    /** Same neutralisation as copy-paste lines for `adb shell` over wireless debugging. */
    fun adbScript(pkg: String): String {
        if (!isValidPackage(pkg)) return ""
        return listOf(
            "am force-stop $pkg",
            "appops set $pkg SYSTEM_ALERT_WINDOW ignore",
            "pm disable-user --user 0 $pkg"
        ).joinToString("\n") { "adb shell $it" }
    }
}
