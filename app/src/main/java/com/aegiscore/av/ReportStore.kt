package com.aegiscore.av

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Process-wide scan results, persisted to filesDir so Install Guard alerts survive process death. */
object ReportStore {
    private val _reports = MutableStateFlow<List<AppReport>>(emptyList())
    val reports: StateFlow<List<AppReport>> = _reports.asStateFlow()

    private val _lastScan = MutableStateFlow(0L)
    val lastScan: StateFlow<Long> = _lastScan.asStateFlow()

    private val lock = Any()

    fun load(ctx: Context) {
        val f = File(ctx.filesDir, "reports.json")
        if (!f.exists()) return
        try {
            val o = JSONObject(f.readText())
            val arr = o.getJSONArray("reports")
            _reports.value = (0 until arr.length()).map { AppReport.fromJson(arr.getJSONObject(it)) }
            _lastScan.value = o.optLong("time")
        } catch (e: Exception) {
            // corrupt file: start clean
        }
    }

    fun replaceAll(ctx: Context, list: List<AppReport>) {
        _reports.value = list
        _lastScan.value = System.currentTimeMillis()
        persist(ctx)
    }

    fun upsert(ctx: Context, r: AppReport) {
        _reports.update { cur -> cur.filter { it.packageName != r.packageName } + r }
        persist(ctx)
    }

    fun remove(ctx: Context, packages: Set<String>) {
        _reports.update { cur -> cur.filter { it.packageName !in packages } }
        persist(ctx)
    }

    private fun persist(ctx: Context) {
        synchronized(lock) {
            try {
                val arr = JSONArray()
                _reports.value.forEach { arr.put(it.toJson()) }
                val o = JSONObject().put("time", _lastScan.value).put("reports", arr)
                File(ctx.filesDir, "reports.json").writeText(o.toString())
            } catch (e: Exception) {
                // best effort
            }
        }
    }
}
