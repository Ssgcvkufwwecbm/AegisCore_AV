package com.aegiscore.av

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.InetAddress

data class ScanUi(val running: Boolean = false, val progress: ScanProgress? = null)

class MainViewModel(app: Application) : AndroidViewModel(app) {

    private val ctx: Context get() = getApplication<Application>().applicationContext

    val reports: StateFlow<List<AppReport>> = ReportStore.reports

    private val _scan = MutableStateFlow(ScanUi())
    val scan: StateFlow<ScanUi> = _scan.asStateFlow()

    private val _vt = MutableStateFlow<Map<String, String>>(emptyMap())
    val vt: StateFlow<Map<String, String>> = _vt.asStateFlow()

    private val _shizuku = MutableStateFlow(QuarantineController.shizukuState())
    val shizuku: StateFlow<QuarantineController.ShizukuState> = _shizuku.asStateFlow()

    private val _log = MutableStateFlow("")
    val actionLog: StateFlow<String> = _log.asStateFlow()

    private val _feed = MutableStateFlow("")
    val feedStatus: StateFlow<String> = _feed.asStateFlow()

    private var job: Job? = null

    fun startScan(includeSystem: Boolean) {
        if (job?.isActive == true) return
        job = viewModelScope.launch {
            _scan.value = ScanUi(running = true)
            try {
                val result = ScanCoordinator.runFullScan(ctx, includeSystem) { p ->
                    _scan.update { it.copy(progress = p) }
                }
                withContext(Dispatchers.IO) { ReportStore.replaceAll(ctx, result) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _log.value = "Scan failed: ${e.message}"
            } finally {
                _scan.update { it.copy(running = false) }
            }
        }
    }

    fun cancelScan() {
        job?.cancel()
    }

    /** Drops reports of apps that have since been uninstalled. */
    fun prune() {
        viewModelScope.launch(Dispatchers.IO) {
            val pm = ctx.packageManager
            val gone = ReportStore.reports.value.map { it.packageName }
                .filter { PmCompat.packageInfo(pm, it, 0) == null }
                .toSet()
            if (gone.isNotEmpty()) ReportStore.remove(ctx, gone)
        }
    }

    // ---- VirusTotal ---------------------------------------------------------------------------
    private fun setVt(pkg: String, text: String) {
        _vt.update { it + (pkg to text) }
    }

    fun vtCheck(pkg: String, sha: String, what: String) {
        val key = Prefs.vtKey(ctx)
        if (key.isBlank()) {
            setVt(pkg, "Add your VirusTotal API key on the System Scan tab first.")
            return
        }
        setVt(pkg, "Querying VirusTotal for the $what hash...")
        viewModelScope.launch(Dispatchers.IO) {
            setVt(pkg, "VirusTotal ($what): " + VirusTotalClient.lookup(sha, key))
        }
    }

    // ---- Quarantine / Shizuku -------------------------------------------------------------------
    fun refreshShizuku() {
        _shizuku.value = QuarantineController.shizukuState()
    }

    fun requestShizuku() {
        QuarantineController.requestShizukuPermission()
    }

    fun neutralize(pkg: String) {
        viewModelScope.launch(Dispatchers.IO) {
            val res = QuarantineController.neutralize(ctx, pkg)
            _log.value = res.joinToString("\n") {
                (if (it.ok) "[ok]   " else "[fail] ") + it.command +
                    (if (it.output.isNotBlank()) "\n         ${it.output}" else "")
            }
            _shizuku.value = QuarantineController.shizukuState()
        }
    }

    fun clearLog() {
        _log.value = ""
    }

    // ---- Network shield ---------------------------------------------------------------------------
    fun refreshFeed() {
        viewModelScope.launch(Dispatchers.IO) {
            _feed.value = "Updating threat feed..."
            val r = ThreatIntel.refresh(ctx)
            _feed.value = r.fold(
                { "Loaded $it domains from abuse.ch URLhaus" },
                { "Update failed: ${it.message}" }
            )
        }
    }

    /** Resolves the built-in canary domain so you can watch it appear in the blocked log. */
    fun sendTestQuery() {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                InetAddress.getByName("block-test.aegiscore.invalid")
            } catch (e: Exception) {
                // NXDOMAIN is the expected result
            }
        }
    }
}
