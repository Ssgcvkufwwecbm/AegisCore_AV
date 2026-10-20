package com.aegiscore.av

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

class MainActivity : ComponentActivity() {

    companion object {
        const val EXTRA_OPEN_REPORTS = "open_reports"
    }

    private val vm: MainViewModel by viewModels()
    private var requestedTab by mutableIntStateOf(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (intent?.getBooleanExtra(EXTRA_OPEN_REPORTS, false) == true) requestedTab = 1
        if (Prefs.guardEnabled(this)) startGuard(this)
        setContent {
            AegisTheme {
                AegisRoot(vm, requestedTab)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(EXTRA_OPEN_REPORTS, false)) requestedTab = 1
    }

    override fun onResume() {
        super.onResume()
        vm.refreshShizuku()
        vm.prune()
    }
}

@Composable
fun AegisTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(
            primary = Color(0xFF4DD0E1),
            onPrimary = Color(0xFF00363D),
            secondary = Color(0xFF80CBC4),
            background = Color(0xFF0B1117),
            onBackground = Color(0xFFE3EBF0),
            surface = Color(0xFF111A22),
            onSurface = Color(0xFFE3EBF0),
            surfaceVariant = Color(0xFF1B2833),
            onSurfaceVariant = Color(0xFF9FB3C0),
            error = Color(0xFFFF5252)
        ),
        content = content
    )
}

@Composable
fun AegisRoot(vm: MainViewModel, requestedTab: Int) {
    val ctx = LocalContext.current
    var tab by rememberSaveable { mutableIntStateOf(0) }
    LaunchedEffect(requestedTab) { if (requestedTab == 1) tab = 1 }

    val notifLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(Unit) {
        if (Build.VERSION.SDK_INT >= 33 &&
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    Scaffold(containerColor = MaterialTheme.colorScheme.background) { inner ->
        Column(Modifier.padding(inner).fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    painter = painterResource(R.drawable.ic_shield),
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(32.dp)
                )
                Spacer(Modifier.width(12.dp))
                Column {
                    Text("AegisCore AV", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                    Text(
                        "Mobile Threat Defense - Security Operations",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            TabRow(selectedTabIndex = tab, containerColor = Color.Transparent) {
                listOf(
                    "System Scan" to Icons.Filled.Search,
                    "Threat Reports" to Icons.Filled.Warning,
                    "Network Shield" to Icons.Filled.Lock
                ).forEachIndexed { i, (title, icon) ->
                    Tab(
                        selected = tab == i,
                        onClick = { tab = i },
                        text = { Text(title, maxLines = 1) },
                        icon = { Icon(icon, contentDescription = null) }
                    )
                }
            }
            Box(Modifier.weight(1f).fillMaxWidth()) {
                when (tab) {
                    0 -> ScanTab(vm)
                    1 -> ReportsTab(vm)
                    else -> ShieldTab(vm)
                }
            }
        }
    }
}
