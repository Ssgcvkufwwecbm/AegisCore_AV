package com.aegiscore.av

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.provider.Settings
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// ---------------------------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------------------------
fun sevColor(s: Severity): Color = when (s) {
    Severity.SAFE -> Color(0xFF4CAF50)
    Severity.LOW -> Color(0xFF9CCC65)
    Severity.MEDIUM -> Color(0xFFFFCA28)
    Severity.HIGH -> Color(0xFFFF7043)
    Severity.CRITICAL -> Color(0xFFFF1744)
}

fun safeStart(ctx: Context, intent: Intent) {
    try {
        ctx.startActivity(intent)
    } catch (e: ActivityNotFoundException) {
        Toast.makeText(ctx, "This screen is not available on your device", Toast.LENGTH_SHORT).show()
    }
}

fun startGuard(ctx: Context) {
    try {
        ContextCompat.startForegroundService(ctx, Intent(ctx, GuardService::class.java))
    } catch (e: Exception) {
        // background start refused; retried the next time the app opens
    }
}

private val timeFmt = SimpleDateFormat("HH:mm:ss", Locale.US)

@Composable
fun SectionCard(title: String, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            content()
        }
    }
}

@Composable
fun MetricTile(label: String, value: String, color: Color, modifier: Modifier = Modifier, sub: String? = null) {
    Surface(modifier = modifier, shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.padding(12.dp)) {
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.titleLarge, color = color, fontWeight = FontWeight.Bold)
            if (sub != null && sub.isNotEmpty()) {
                Text(
                    sub, style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1, overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

@Composable
fun SeverityChip(s: Severity) {
    val c = sevColor(s)
    Surface(shape = RoundedCornerShape(50), color = c.copy(alpha = 0.18f)) {
        Text(
            s.name,
            color = c,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp)
        )
    }
}

@Composable
fun RowScope.ActionButton(text: String, enabled: Boolean = true, danger: Boolean = false, onClick: () -> Unit) {
    if (danger) {
        Button(
            onClick = onClick,
            enabled = enabled,
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(horizontal = 8.dp),
            colors = ButtonDefaults.buttonColors(containerColor = sevColor(Severity.CRITICAL), contentColor = Color.White)
        ) { Text(text, fontSize = 12.sp, maxLines = 1) }
    } else {
        OutlinedButton(
            onClick = onClick,
            enabled = enabled,
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(horizontal = 8.dp)
        ) { Text(text, fontSize = 12.sp, maxLines = 1) }
    }
}

// ---------------------------------------------------------------------------------------------
// TAB 1: Deep System Scan
// ---------------------------------------------------------------------------------------------
@Composable
fun PostureCard(reports: List<AppReport>, lastScan: Long) {
    val crit = reports.count { it.severity == Severity.CRITICAL }
    val high = reports.count { it.severity == Severity.HIGH }
    val med = reports.count { it.severity == Severity.MEDIUM }
    val (headline, color) = when {
        reports.isEmpty() -> "NOT SCANNED YET" to MaterialTheme.colorScheme.onSurfaceVariant
        crit > 0 -> "CRITICAL THREATS FOUND" to sevColor(Severity.CRITICAL)
        high > 0 -> "HIGH-RISK APPS FOUND" to sevColor(Severity.HIGH)
        med > 0 -> "SUSPICIOUS APPS FOUND" to sevColor(Severity.MEDIUM)
        else -> "NO ACTIVE THREATS" to sevColor(Severity.SAFE)
    }
    SectionCard("Device posture") {
        Text(headline, color = color, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text(
            if (lastScan > 0) "Last scan: " + DateFormat.getDateTimeInstance().format(Date(lastScan))
            else "Run a deep scan to audit this device.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MetricTile("Apps", "${reports.size}", MaterialTheme.colorScheme.primary, Modifier.weight(1f))
            MetricTile("Critical", "$crit", sevColor(Severity.CRITICAL), Modifier.weight(1f))
            MetricTile("High", "$high", sevColor(Severity.HIGH), Modifier.weight(1f))
            MetricTile("Medium", "$med", sevColor(Severity.MEDIUM), Modifier.weight(1f))
        }
    }
}

@Composable
fun ScanTab(vm: MainViewModel) {
    val ctx = LocalContext.current
    val scan by vm.scan.collectAsStateWithLifecycle()
    val reports by vm.reports.collectAsStateWithLifecycle()
    val lastScan by ReportStore.lastScan.collectAsStateWithLifecycle()
    var includeSystem by remember { mutableStateOf(Prefs.includeSystem(ctx)) }
    var guard by remember { mutableStateOf(Prefs.guardEnabled(ctx)) }
    var vtKey by remember { mutableStateOf(Prefs.vtKey(ctx)) }

    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item { PostureCard(reports, lastScan) }

        item {
            SectionCard("Deep System Scan") {
                Text(
                    "Reads every APK's classes.dex for dropper and evasion signatures, measures the Shannon entropy " +
                        "of assets/ and lib/ files, hashes the APK and classes.dex, and runs the stalkerware / " +
                        "accessibility / device-admin audit. Everything runs on-device.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Switch(
                        checked = includeSystem,
                        onCheckedChange = { includeSystem = it; Prefs.setIncludeSystem(ctx, it) }
                    )
                    Spacer(Modifier.width(10.dp))
                    Text("Include system apps", style = MaterialTheme.typography.bodyMedium)
                }
                if (scan.running) {
                    OutlinedButton(onClick = { vm.cancelScan() }, modifier = Modifier.fillMaxWidth()) {
                        Text("Cancel scan")
                    }
                } else {
                    Button(onClick = { vm.startScan(includeSystem) }, modifier = Modifier.fillMaxWidth()) {
                        Text("Run deep scan")
                    }
                }
            }
        }

        scan.progress?.let { p ->
            item {
                SectionCard(if (scan.running) "Live scan metrics" else "Last scan metrics") {
                    val frac = if (p.total == 0) 0f else p.done.toFloat() / p.total
                    LinearProgressIndicator(progress = { frac }, modifier = Modifier.fillMaxWidth())
                    Text(
                        "${p.done}/${p.total}  -  ${p.currentLabel}",
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 1, overflow = TextOverflow.Ellipsis
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        MetricTile("DEX bytes scanned", fmtBytes(p.dexBytes), MaterialTheme.colorScheme.primary, Modifier.weight(1f))
                        MetricTile("assets/lib files measured", "${p.entropyFiles}", MaterialTheme.colorScheme.primary, Modifier.weight(1f))
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        MetricTile(
                            "Peak entropy", "${f2(p.peakEntropy)} / 8.00",
                            if (p.peakEntropy > DexScannerEngine.ENTROPY_THRESHOLD) sevColor(Severity.HIGH) else MaterialTheme.colorScheme.primary,
                            Modifier.weight(1f), sub = p.peakEntropyApp
                        )
                        MetricTile(
                            "Flagged apps", "${p.flagged}",
                            if (p.flagged > 0) sevColor(Severity.MEDIUM) else sevColor(Severity.SAFE),
                            Modifier.weight(1f)
                        )
                    }
                }
            }
        }

        item {
            SectionCard("Real-Time Install Guard") {
                Text(
                    "Scans every newly installed or updated app in the background and raises a critical alert " +
                        "when it finds a HIGH or CRITICAL threat.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Switch(
                        checked = guard,
                        onCheckedChange = { on ->
                            guard = on
                            Prefs.setGuardEnabled(ctx, on)
                            if (on) startGuard(ctx) else ctx.stopService(Intent(ctx, GuardService::class.java))
                        }
                    )
                    Spacer(Modifier.width(10.dp))
                    Text(if (guard) "Guard running" else "Guard off", style = MaterialTheme.typography.bodyMedium)
                }
            }
        }

        item {
            SectionCard("VirusTotal (optional)") {
                OutlinedTextField(
                    value = vtKey,
                    onValueChange = { vtKey = it; Prefs.setVtKey(ctx, it.trim()) },
                    label = { Text("VirusTotal API v3 key") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    modifier = Modifier.fillMaxWidth()
                )
                Text(
                    "Used only on demand from a report. Just the SHA-256 hash is sent, never the app. " +
                        "The key is stored in this app's private storage.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------
// TAB 2: Detailed Threat Reports
// ---------------------------------------------------------------------------------------------
@Composable
fun QuarantineCard(vm: MainViewModel, state: QuarantineController.ShizukuState, log: String) {
    SectionCard("Active Quarantine") {
        Text(
            when (state) {
                QuarantineController.ShizukuState.READY ->
                    "Shizuku connected. One-tap neutralisation (force-stop, revoke overlay, disable) is available."
                QuarantineController.ShizukuState.PERMISSION_NEEDED ->
                    "Shizuku is running but AegisCore has not been granted access yet."
                QuarantineController.ShizukuState.UNAVAILABLE ->
                    "Shizuku is not running. Start it (wireless debugging or root) for one-tap neutralisation, " +
                        "or copy the ADB commands from a report and run them yourself."
            },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            if (state == QuarantineController.ShizukuState.PERMISSION_NEEDED) {
                ActionButton("Grant Shizuku access") { vm.requestShizuku() }
            }
            ActionButton("Refresh status") { vm.refreshShizuku() }
        }
        if (log.isNotBlank()) {
            Text(log, fontFamily = FontFamily.Monospace, fontSize = 11.sp)
            TextButton(onClick = { vm.clearLog() }) { Text("Clear log") }
        }
    }
}

@Composable
fun ReportCard(r: AppReport, vm: MainViewModel, shizuku: QuarantineController.ShizukuState, vtText: String?) {
    val ctx = LocalContext.current
    val clip = LocalClipboardManager.current
    var open by rememberSaveable(r.packageName) { mutableStateOf(false) }
    val color = sevColor(r.severity)

    Card(
        modifier = Modifier.fillMaxWidth().clickable { open = !open },
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(10.dp).clip(CircleShape).background(color))
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(r.label, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(
                        r.packageName, style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1, overflow = TextOverflow.Ellipsis
                    )
                }
                SeverityChip(r.severity)
                Spacer(Modifier.width(8.dp))
                Text("${r.score}", color = color, fontWeight = FontWeight.Bold)
            }

            if (!open) {
                Text(
                    "${r.indicators.size} indicator(s) - tap for the full explanation",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                return@Column
            }

            r.indicators.sortedByDescending { it.severity }.forEach { ind ->
                Column(
                    Modifier.fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .background(MaterialTheme.colorScheme.surface)
                        .padding(10.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)
                ) {
                    Row(verticalAlignment = Alignment.Top) {
                        Text(
                            ind.severity.name, color = sevColor(ind.severity),
                            style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(ind.title, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                    }
                    Text(ind.detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            Text(
                "Version ${r.versionName.ifEmpty { "?" }}  -  installer: ${r.installer.ifEmpty { "none" }}  -  peak entropy ${f2(r.maxEntropy)}/8.00",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            if (r.apkSha256.isNotEmpty()) {
                Text("APK SHA-256", style = MaterialTheme.typography.labelSmall)
                Text(r.apkSha256, fontFamily = FontFamily.Monospace, fontSize = 10.sp)
            }
            if (r.dexSha256.isNotEmpty()) {
                Text("classes.dex SHA-256", style = MaterialTheme.typography.labelSmall)
                Text(r.dexSha256, fontFamily = FontFamily.Monospace, fontSize = 10.sp)
            }
            if (vtText != null) {
                Text(vtText, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                ActionButton("Uninstall") { safeStart(ctx, QuarantineController.uninstallIntent(r.packageName)) }
                ActionButton("App info") { safeStart(ctx, QuarantineController.appInfoIntent(r.packageName)) }
            }

            val a11y = r.indicators.any { it.title.contains("ccessibility") || it.title.contains("overlay") }
            val notif = r.indicators.any { it.title.contains("Notification") || it.title.contains("OTP") }
            val admin = r.indicators.any { it.title.contains("administrator") }
            if (a11y || notif || admin) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    if (a11y) ActionButton("Accessibility") { safeStart(ctx, QuarantineController.accessibilitySettingsIntent()) }
                    if (a11y) ActionButton("Overlay perm") { safeStart(ctx, QuarantineController.overlaySettingsIntent(r.packageName)) }
                    if (notif) ActionButton("Notif. access") { safeStart(ctx, QuarantineController.notificationListenerSettingsIntent()) }
                    if (admin) ActionButton("Device admin") { safeStart(ctx, QuarantineController.deviceAdminSettingsIntent()) }
                }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                ActionButton("VT page", enabled = r.apkSha256.isNotEmpty()) {
                    safeStart(ctx, Intent(Intent.ACTION_VIEW, Uri.parse(VirusTotalClient.guiUrl(r.apkSha256))))
                }
                ActionButton("VT API: APK", enabled = r.apkSha256.isNotEmpty()) { vm.vtCheck(r.packageName, r.apkSha256, "APK") }
                ActionButton("VT API: DEX", enabled = r.dexSha256.isNotEmpty()) { vm.vtCheck(r.packageName, r.dexSha256, "classes.dex") }
            }

            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                ActionButton(
                    "Neutralise (Shizuku)",
                    enabled = shizuku == QuarantineController.ShizukuState.READY,
                    danger = true
                ) { vm.neutralize(r.packageName) }
                ActionButton("Copy ADB commands") {
                    clip.setText(AnnotatedString(QuarantineController.adbScript(r.packageName)))
                    Toast.makeText(ctx, "ADB commands copied", Toast.LENGTH_SHORT).show()
                }
            }
        }
    }
}

@Composable
fun ReportsTab(vm: MainViewModel) {
    val reports by vm.reports.collectAsStateWithLifecycle()
    val vt by vm.vt.collectAsStateWithLifecycle()
    val shizuku by vm.shizuku.collectAsStateWithLifecycle()
    val log by vm.actionLog.collectAsStateWithLifecycle()
    var showAll by rememberSaveable { mutableStateOf(false) }

    val shown = remember(reports, showAll) {
        reports
            .filter { showAll || it.severity >= Severity.MEDIUM }
            .sortedWith(compareByDescending<AppReport> { it.severity }.thenByDescending { it.score })
    }

    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item { QuarantineCard(vm, shizuku, log) }
        item {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Switch(checked = showAll, onCheckedChange = { showAll = it })
                Spacer(Modifier.width(10.dp))
                Text("Show low-risk and clean apps (${reports.size} scanned)", style = MaterialTheme.typography.bodySmall)
            }
        }
        if (shown.isEmpty()) {
            item {
                Text(
                    if (reports.isEmpty()) "No results yet. Run a deep scan on the System Scan tab."
                    else "No medium-or-higher threats found. Flip the switch above to see every scanned app.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        items(shown, key = { it.packageName }) { r ->
            ReportCard(r, vm, shizuku, vt[r.packageName])
        }
    }
}

// ---------------------------------------------------------------------------------------------
// TAB 3: Live Network Shield
// ---------------------------------------------------------------------------------------------
@Composable
fun ShieldTab(vm: MainViewModel) {
    val ctx = LocalContext.current
    val running by AegisVpnService.running.collectAsStateWithLifecycle()
    val stats by AegisVpnService.stats.collectAsStateWithLifecycle()
    val blocked by AegisVpnService.blocked.collectAsStateWithLifecycle()
    val feed by vm.feedStatus.collectAsStateWithLifecycle()
    var strict by remember { mutableStateOf(Prefs.strictDns(ctx)) }
    val privateDns = remember { runCatching { Settings.Global.getString(ctx.contentResolver, "private_dns_mode") }.getOrNull() }

    val consent = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { res ->
        if (res.resultCode == Activity.RESULT_OK) AegisVpnService.start(ctx)
    }

    LazyColumn(
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            SectionCard("Live Network Shield") {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Switch(
                        checked = running,
                        onCheckedChange = { on ->
                            if (on) {
                                val intent = VpnService.prepare(ctx)
                                if (intent != null) consent.launch(intent) else AegisVpnService.start(ctx)
                            } else {
                                AegisVpnService.stop(ctx)
                            }
                        }
                    )
                    Spacer(Modifier.width(10.dp))
                    Column {
                        Text(
                            if (running) "Shield ACTIVE" else "Shield OFF",
                            fontWeight = FontWeight.Bold,
                            color = if (running) sevColor(Severity.SAFE) else MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Text(
                            "Local DNS firewall. Nothing leaves your device except normal DNS lookups.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                if (privateDns == "hostname") {
                    Text(
                        "Warning: Private DNS is set to a fixed provider. Android then bypasses VPN DNS, so the shield cannot see lookups. " +
                            "Set Private DNS to Automatic or Off in system settings.",
                        style = MaterialTheme.typography.bodySmall,
                        color = sevColor(Severity.HIGH)
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    MetricTile("DNS queries", "${stats.total}", MaterialTheme.colorScheme.primary, Modifier.weight(1f))
                    MetricTile("Blocked", "${stats.blocked}", sevColor(Severity.CRITICAL), Modifier.weight(1f))
                    MetricTile("Threat list", "${ThreatIntel.size()}", MaterialTheme.colorScheme.primary, Modifier.weight(1f))
                }
            }
        }

        item {
            SectionCard("Threat list") {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Switch(
                        checked = strict,
                        onCheckedChange = {
                            strict = it
                            Prefs.setStrictDns(ctx, it)
                            ThreatIntel.strict = it
                        }
                    )
                    Spacer(Modifier.width(10.dp))
                    Text(
                        "Strict mode: also block dynamic-DNS and tunnel hosts that Android RATs use for C2 (may break home servers)",
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                    ActionButton("Update feed (URLhaus)") { vm.refreshFeed() }
                    ActionButton("Send test query", enabled = running) { vm.sendTestQuery() }
                }
                if (feed.isNotEmpty()) {
                    Text(feed, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary)
                }
                if (ThreatIntel.feedUpdatedAt > 0) {
                    Text(
                        "Feed last updated " + DateFormat.getDateTimeInstance().format(Date(ThreatIntel.feedUpdatedAt)),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }

        item {
            Text("Blocked domain log (live)", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        }
        if (blocked.isEmpty()) {
            item {
                Text(
                    if (running) "Nothing blocked yet. Use Send test query to verify the firewall."
                    else "Turn the shield on to start logging.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
        items(blocked, key = { it.id }) { e ->
            Row(
                Modifier.fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .background(MaterialTheme.colorScheme.surfaceVariant)
                    .padding(10.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(Modifier.weight(1f)) {
                    Text(e.domain, fontFamily = FontFamily.Monospace, fontSize = 13.sp, color = sevColor(Severity.CRITICAL), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text("${e.type}  -  ${e.reason}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Text(timeFmt.format(Date(e.time)), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}
