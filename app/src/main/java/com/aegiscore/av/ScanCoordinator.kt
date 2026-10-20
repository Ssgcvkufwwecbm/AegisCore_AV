package com.aegiscore.av

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

object ScanCoordinator {

    fun isSystem(pi: PackageInfo): Boolean =
        ((pi.applicationInfo?.flags ?: 0) and ApplicationInfo.FLAG_SYSTEM) != 0

    fun scanOne(ctx: Context, pi: PackageInfo, behavioral: BehavioralScanner): AppReport =
        scanDetailed(ctx, pi, behavioral).first

    private fun scanDetailed(ctx: Context, pi: PackageInfo, behavioral: BehavioralScanner): Pair<AppReport, DexScanResult> {
        val pm = ctx.packageManager
        val ai = pi.applicationInfo
        val label = try {
            ai?.loadLabel(pm)?.toString() ?: pi.packageName
        } catch (e: Exception) {
            pi.packageName
        }

        val paths = ArrayList<String>()
        ai?.sourceDir?.let { paths += it }
        ai?.splitSourceDirs?.let { paths += it }

        val dex = DexScannerEngine.scan(paths)
        val indicators = ArrayList<Indicator>()
        indicators += DexScannerEngine.toIndicators(dex)
        indicators += runCatching { behavioral.audit(pi) }.getOrDefault(emptyList())

        val report = AppReport(
            packageName = pi.packageName,
            label = label,
            versionName = pi.versionName ?: "",
            isSystem = isSystem(pi),
            installer = PmCompat.installer(pm, pi.packageName) ?: "",
            apkSha256 = dex.apkSha256,
            dexSha256 = dex.dexSha256,
            maxEntropy = dex.maxEntropy,
            indicators = indicators,
            scannedAt = System.currentTimeMillis()
        )
        return report to dex
    }

    /** Scans all installed apps, 3 at a time, reporting live DEX/entropy metrics. */
    suspend fun runFullScan(
        ctx: Context,
        includeSystem: Boolean,
        onProgress: (ScanProgress) -> Unit
    ): List<AppReport> = coroutineScope {
        val pm = ctx.packageManager
        val behavioral = BehavioralScanner(ctx)
        val targets = withContext(Dispatchers.IO) {
            PmCompat.installedPackages(pm, PackageManager.GET_PERMISSIONS).filter {
                it.packageName != ctx.packageName && (includeSystem || !isSystem(it))
            }
        }

        val gate = Semaphore(3)
        val lock = Any()
        val total = targets.size
        var done = 0
        var dexBytes = 0L
        var entFiles = 0
        var peak = 0.0
        var peakApp = ""
        var flagged = 0

        targets.map { pi ->
            async(Dispatchers.IO) {
                gate.withPermit {
                    val (report, dex) = scanDetailed(ctx, pi, behavioral)
                    synchronized(lock) {
                        done++
                        dexBytes += dex.dexBytes
                        entFiles += dex.entropyFiles
                        if (dex.maxEntropy > peak) {
                            peak = dex.maxEntropy
                            peakApp = report.label
                        }
                        if (report.severity >= Severity.MEDIUM) flagged++
                        onProgress(ScanProgress(done, total, report.label, dexBytes, entFiles, peak, peakApp, flagged))
                    }
                    report
                }
            }
        }.awaitAll()
    }
}
