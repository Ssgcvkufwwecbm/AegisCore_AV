package com.aegiscore.av

import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

enum class Severity { SAFE, LOW, MEDIUM, HIGH, CRITICAL }

data class Indicator(
    val title: String,
    val detail: String,
    val severity: Severity,
    val weight: Int
)

data class AppReport(
    val packageName: String,
    val label: String,
    val versionName: String,
    val isSystem: Boolean,
    val installer: String,
    val apkSha256: String,
    val dexSha256: String,
    val maxEntropy: Double,
    val indicators: List<Indicator>,
    val scannedAt: Long
) {
    val score: Int get() = minOf(100, indicators.sumOf { it.weight })
    val severity: Severity get() = indicators.maxOfOrNull { it.severity } ?: Severity.SAFE

    fun toJson(): JSONObject {
        val arr = JSONArray()
        indicators.forEach {
            arr.put(
                JSONObject()
                    .put("t", it.title)
                    .put("d", it.detail)
                    .put("s", it.severity.name)
                    .put("w", it.weight)
            )
        }
        return JSONObject()
            .put("p", packageName)
            .put("l", label)
            .put("v", versionName)
            .put("sys", isSystem)
            .put("i", installer)
            .put("a", apkSha256)
            .put("x", dexSha256)
            .put("e", maxEntropy)
            .put("n", arr)
            .put("t", scannedAt)
    }

    companion object {
        fun fromJson(o: JSONObject): AppReport {
            val arr = o.optJSONArray("n") ?: JSONArray()
            val list = (0 until arr.length()).map { i ->
                val j = arr.getJSONObject(i)
                Indicator(
                    j.optString("t"),
                    j.optString("d"),
                    runCatching { Severity.valueOf(j.optString("s")) }.getOrDefault(Severity.LOW),
                    j.optInt("w")
                )
            }
            return AppReport(
                o.optString("p"), o.optString("l"), o.optString("v"), o.optBoolean("sys"),
                o.optString("i"), o.optString("a"), o.optString("x"), o.optDouble("e", 0.0),
                list, o.optLong("t")
            )
        }
    }
}

data class ScanProgress(
    val done: Int,
    val total: Int,
    val currentLabel: String,
    val dexBytes: Long,
    val entropyFiles: Int,
    val peakEntropy: Double,
    val peakEntropyApp: String,
    val flagged: Int
)

fun f2(d: Double): String = String.format(Locale.US, "%.2f", d)

fun fmtBytes(n: Long): String = when {
    n >= (1L shl 30) -> String.format(Locale.US, "%.2f GB", n / (1L shl 30).toDouble())
    n >= (1L shl 20) -> String.format(Locale.US, "%.1f MB", n / (1L shl 20).toDouble())
    n >= (1L shl 10) -> String.format(Locale.US, "%.0f KB", n / 1024.0)
    else -> "$n B"
}
