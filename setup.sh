#!/usr/bin/env bash
# =============================================================================
#  AegisCore AV - one-shot project generator
#  Usage:   bash setup.sh [target-dir]        (default: ./AegisCoreAV)
#  Result:  complete Android Studio / Gradle project + GitHub Actions workflow
#           that compiles AegisCore-AV-debug.apk in the cloud on every push.
# =============================================================================
set -euo pipefail

ROOT="${1:-AegisCoreAV}"
SRC="$ROOT/app/src/main/java/com/aegiscore/av"
RES="$ROOT/app/src/main/res"

mkdir -p "$SRC" \
         "$RES/values" "$RES/drawable" "$RES/mipmap-anydpi-v26" \
         "$ROOT/gradle/wrapper" "$ROOT/.github/workflows"

echo "==> Generating AegisCore AV into: $ROOT"

# -----------------------------------------------------------------------------
# Gradle: settings / root build / properties / wrapper config
# -----------------------------------------------------------------------------
cat << 'EOF' > "$ROOT/settings.gradle.kts"
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "AegisCoreAV"
include(":app")
EOF

cat << 'EOF' > "$ROOT/build.gradle.kts"
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
EOF

cat << 'EOF' > "$ROOT/gradle.properties"
org.gradle.jvmargs=-Xmx3g -Dfile.encoding=UTF-8
org.gradle.caching=true
android.useAndroidX=true
android.nonTransitiveRClass=true
kotlin.code.style=official
EOF

cat << 'EOF' > "$ROOT/gradle/wrapper/gradle-wrapper.properties"
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.9-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

cat << 'EOF' > "$ROOT/.gitignore"
*.iml
.gradle/
/local.properties
/.idea/
.DS_Store
/build/
/app/build/
/captures/
.externalNativeBuild/
.cxx/
EOF

cat << 'EOF' > "$ROOT/app/build.gradle.kts"
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.aegiscore.av"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.aegiscore.av"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.14"
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    implementation(platform("androidx.compose:compose-bom:2024.06.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")

    // Shizuku: elevated (shell-level) command execution for active quarantine
    implementation("dev.rikka.shizuku:api:13.1.5")
    implementation("dev.rikka.shizuku:provider:13.1.5")
}
EOF

cat << 'EOF' > "$ROOT/app/proguard-rules.pro"
-keep class rikka.shizuku.** { *; }
-keep class com.aegiscore.av.** { *; }
EOF

# -----------------------------------------------------------------------------
# Manifest
# -----------------------------------------------------------------------------
cat << 'EOF' > "$ROOT/app/src/main/AndroidManifest.xml"
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission
        android:name="android.permission.QUERY_ALL_PACKAGES"
        tools:ignore="QueryAllPackagesPermission" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

    <application
        android:name=".AegisApp"
        android:allowBackup="false"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:label="@string/app_name"
        android:largeHeap="true"
        android:supportsRtl="true"
        android:theme="@style/Theme.AegisCoreAV">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <!-- Local loopback DNS firewall -->
        <service
            android:name=".AegisVpnService"
            android:exported="false"
            android:permission="android.permission.BIND_VPN_SERVICE">
            <intent-filter>
                <action android:name="android.net.VpnService" />
            </intent-filter>
        </service>

        <!-- Keeps a dynamic PACKAGE_ADDED/REPLACED receiver alive for the Install Guard -->
        <service
            android:name=".GuardService"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="Real-time scanning of newly installed or updated apps" />
        </service>

        <!-- exported=false: only the system can deliver these, spoofed intents from other apps are ignored -->
        <receiver
            android:name=".PackageReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.PACKAGE_ADDED" />
                <action android:name="android.intent.action.PACKAGE_REPLACED" />
                <data android:scheme="package" />
            </intent-filter>
        </receiver>

        <receiver
            android:name=".BootReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
            </intent-filter>
        </receiver>

        <!-- Shizuku binder delivery -->
        <provider
            android:name="rikka.shizuku.ShizukuProvider"
            android:authorities="${applicationId}.shizuku"
            android:enabled="true"
            android:exported="true"
            android:multiprocess="false"
            android:permission="android.permission.INTERACT_ACROSS_USERS_FULL"
            tools:ignore="ExportedContentProvider" />
    </application>
</manifest>
EOF

# -----------------------------------------------------------------------------
# Resources
# -----------------------------------------------------------------------------
cat << 'EOF' > "$RES/values/strings.xml"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">AegisCore AV</string>
</resources>
EOF

cat << 'EOF' > "$RES/values/colors.xml"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="aegis_bg">#FF0B1117</color>
    <color name="ic_launcher_background">#FF0B1117</color>
</resources>
EOF

cat << 'EOF' > "$RES/values/themes.xml"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="Theme.AegisCoreAV" parent="android:Theme.Material.NoActionBar">
        <item name="android:windowBackground">@color/aegis_bg</item>
        <item name="android:statusBarColor">@android:color/transparent</item>
        <item name="android:navigationBarColor">@android:color/transparent</item>
        <item name="android:windowLightStatusBar">false</item>
    </style>
</resources>
EOF

cat << 'EOF' > "$RES/drawable/ic_shield.xml"
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M12,1L3,5v6c0,5.55 3.84,10.74 9,12 5.16,-1.26 9,-6.45 9,-12V5l-9,-4z" />
</vector>
EOF

cat << 'EOF' > "$RES/drawable/ic_launcher_foreground.xml"
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <group
        android:scaleX="2.5"
        android:scaleY="2.5"
        android:translateX="24"
        android:translateY="24">
        <path
            android:fillColor="#FF4DD0E1"
            android:pathData="M12,1L3,5v6c0,5.55 3.84,10.74 9,12 5.16,-1.26 9,-6.45 9,-12V5l-9,-4z" />
    </group>
</vector>
EOF

cat << 'EOF' > "$RES/mipmap-anydpi-v26/ic_launcher.xml"
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
EOF

cat << 'EOF' > "$RES/mipmap-anydpi-v26/ic_launcher_round.xml"
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
EOF

# -----------------------------------------------------------------------------
# Kotlin: models, helpers, storage
# -----------------------------------------------------------------------------
cat << 'EOF' > "$SRC/Models.kt"
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
EOF

cat << 'EOF' > "$SRC/PmCompat.kt"
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
EOF

cat << 'EOF' > "$SRC/Prefs.kt"
package com.aegiscore.av

import android.content.Context

object Prefs {
    private fun sp(c: Context) = c.getSharedPreferences("aegis_prefs", Context.MODE_PRIVATE)

    fun vtKey(c: Context): String = sp(c).getString("vt_key", "") ?: ""
    fun setVtKey(c: Context, v: String) { sp(c).edit().putString("vt_key", v).apply() }

    fun includeSystem(c: Context): Boolean = sp(c).getBoolean("include_system", false)
    fun setIncludeSystem(c: Context, v: Boolean) { sp(c).edit().putBoolean("include_system", v).apply() }

    fun guardEnabled(c: Context): Boolean = sp(c).getBoolean("guard", false)
    fun setGuardEnabled(c: Context, v: Boolean) { sp(c).edit().putBoolean("guard", v).apply() }

    fun strictDns(c: Context): Boolean = sp(c).getBoolean("strict_dns", false)
    fun setStrictDns(c: Context, v: Boolean) { sp(c).edit().putBoolean("strict_dns", v).apply() }
}
EOF

cat << 'EOF' > "$SRC/ReportStore.kt"
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
EOF

# -----------------------------------------------------------------------------
# ENGINE 1: Deep DEX bytecode & entropy scanner
# -----------------------------------------------------------------------------
cat << 'EOF' > "$SRC/DexScannerEngine.kt"
package com.aegiscore.av

import android.os.Build
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import kotlin.math.ln

data class SignatureHit(
    val id: String,
    val title: String,
    val why: String,
    val severity: Severity,
    val weight: Int,
    val dexFile: String
)

data class EntropyHit(val entry: String, val entropy: Double, val size: Long)

data class DexScanResult(
    val apkSha256: String,
    val dexSha256: String,
    val signatureHits: List<SignatureHit>,
    val entropyHits: List<EntropyHit>,
    val embeddedPayloads: List<String>,
    val maxEntropy: Double,
    val maxEntropyEntry: String,
    val dexBytes: Long,
    val entropyFiles: Int,
    val errors: List<String>
)

/**
 * Static analysis of an installed APK (and its split APKs):
 *  - raw byte scan of every classes*.dex for dropper / evasion signatures
 *  - Shannon entropy (0.0 .. 8.0 bits/byte) of every file in assets/ and lib/
 *  - SHA-256 of the full APK and of classes.dex (for VirusTotal v3 lookups)
 */
object DexScannerEngine {

    const val ENTROPY_THRESHOLD = 7.2
    private const val MAX_DEX_BYTES = 96L * 1024 * 1024
    private const val SAMPLE_CAP = 8L * 1024 * 1024            // per entry
    private const val APK_SAMPLE_BUDGET = 128L * 1024 * 1024    // per APK
    private const val MIN_ENTROPY_BYTES = 4096L

    // ---- Boyer-Moore-Horspool matcher --------------------------------------------------------
    private class Needle(private val pattern: ByteArray) {
        private val shift = IntArray(256) { pattern.size }

        init {
            for (i in 0 until pattern.size - 1) {
                shift[pattern[i].toInt() and 0xFF] = pattern.size - 1 - i
            }
        }

        fun occursIn(hay: ByteArray): Boolean {
            val n = pattern.size
            if (n == 0 || hay.size < n) return false
            var pos = 0
            val limit = hay.size - n
            while (pos <= limit) {
                var j = n - 1
                while (j >= 0 && hay[pos + j] == pattern[j]) j--
                if (j < 0) return true
                pos += shift[hay[pos + n - 1].toInt() and 0xFF]
            }
            return false
        }
    }

    /** Plain substring needle (descriptors, paths, reflection strings). */
    private fun lit(s: String) = Needle(s.toByteArray(Charsets.ISO_8859_1))

    /**
     * Exact DEX string_data_item needle: uleb128 length byte + MUTF-8 bytes + NUL.
     * Lets us match a short identifier like "exec" exactly instead of any word containing it.
     */
    private fun framed(s: String) =
        Needle(byteArrayOf(s.length.toByte()) + s.toByteArray(Charsets.ISO_8859_1) + byteArrayOf(0))

    /** A signature matches when every group has at least one needle present (AND of ORs). */
    private class Sig(
        val id: String,
        val title: String,
        val why: String,
        val severity: Severity,
        val weight: Int,
        val groups: List<List<Needle>>
    ) {
        fun matches(bytes: ByteArray): Boolean = groups.all { g -> g.any { it.occursIn(bytes) } }
    }

    private val SIGNATURES: List<Sig> = listOf(
        Sig(
            "DEX_CLASS_LOADER",
            "Dynamic DEX loading (DexClassLoader)",
            "The app can load executable code from a file at runtime. Droppers use this to fetch and run a hidden stage-2 payload that never appears in the installed APK. Ad/analytics/hot-patch SDKs also do this, so weigh it together with the other indicators.",
            Severity.MEDIUM, 15,
            listOf(listOf(lit("dalvik/system/DexClassLoader"), lit("dalvik.system.DexClassLoader")))
        ),
        Sig(
            "IN_MEMORY_DEX_LOADER",
            "In-memory DEX loading (InMemoryDexClassLoader)",
            "Code is loaded straight from a ByteBuffer and never touches disk, which defeats file-based scanners. Very rare in benign apps outside protectors and SDK loaders.",
            Severity.HIGH, 25,
            listOf(listOf(lit("dalvik/system/InMemoryDexClassLoader"), lit("dalvik.system.InMemoryDexClassLoader")))
        ),
        Sig(
            "RUNTIME_EXEC",
            "Shell command execution (Runtime.getRuntime().exec)",
            "Class java.lang.Runtime plus the exact strings getRuntime and exec are present, so the app can spawn shell processes. Used by root tools, loggers and also by malware to run commands silently.",
            Severity.MEDIUM, 12,
            listOf(
                listOf(framed("Ljava/lang/Runtime;")),
                listOf(framed("getRuntime")),
                listOf(framed("exec"))
            )
        ),
        Sig(
            "SU_BINARY",
            "Root binary reference (/system/bin/su)",
            "The bytecode references the su binary. Malware uses it to escalate privileges; root-detection libraries in banking apps contain the same string, so this is context dependent.",
            Severity.MEDIUM, 18,
            listOf(listOf(lit("/system/bin/su"), lit("/system/xbin/su")))
        ),
        Sig(
            "CRYPTO_CIPHER",
            "Runtime decryption primitives (javax.crypto.Cipher)",
            "The app uses javax.crypto.Cipher. Common in legitimate apps, but it is how packed droppers decrypt a stage-2 DEX before loading it.",
            Severity.LOW, 5,
            listOf(listOf(lit("javax/crypto/Cipher"), lit("javax.crypto.Cipher")))
        )
    )

    // ---- Entropy / file classification --------------------------------------------------------
    private enum class Kind(val label: String) {
        MEDIA("media"),
        DEX("raw DEX"),
        ELF("native ELF binary"),
        ARCHIVE("APK/JAR/DEX container"),
        OTHER("blob")
    }

    private class EntryInfo(val kind: Kind, val entropy: Double, val bytes: Long)

    private val MEDIA_EXT = setOf(
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "avif", "mp3", "mp4", "m4a", "aac",
        "ogg", "opus", "webm", "mkv", "3gp", "mov", "avi", "flac", "woff", "woff2", "zip",
        "gz", "bz2", "xz", "7z", "zst", "br", "pdf"
    )
    private val PAYLOAD_EXT = setOf("apk", "jar", "dex", "odex", "vdex")

    private fun classify(name: String, ext: String, b: ByteArray, n: Int): Kind {
        fun at(off: Int, vararg sig: Int): Boolean {
            if (n < off + sig.size) return false
            for (i in sig.indices) if ((b[off + i].toInt() and 0xFF) != sig[i]) return false
            return true
        }
        if (at(0, 0x64, 0x65, 0x78, 0x0A)) return Kind.DEX
        if (at(0, 0x7F, 0x45, 0x4C, 0x46)) return if (name.startsWith("assets/")) Kind.ELF else Kind.OTHER
        if (name.startsWith("assets/") && ext in PAYLOAD_EXT) return Kind.ARCHIVE
        if (ext in MEDIA_EXT) return Kind.MEDIA
        if (at(0, 0x89, 0x50, 0x4E, 0x47) || at(0, 0xFF, 0xD8, 0xFF) || at(0, 0x47, 0x49, 0x46, 0x38) ||
            at(0, 0x50, 0x4B, 0x03, 0x04) || at(0, 0x1F, 0x8B) || at(0, 0x52, 0x49, 0x46, 0x46) ||
            at(0, 0x4F, 0x67, 0x67, 0x53) || at(0, 0x49, 0x44, 0x33) || at(0, 0x1A, 0x45, 0xDF, 0xA3) ||
            at(0, 0x77, 0x4F, 0x46, 0x46) || at(0, 0x77, 0x4F, 0x46, 0x32) || at(0, 0x25, 0x50, 0x44, 0x46) ||
            at(0, 0x42, 0x5A, 0x68) || at(0, 0xFD, 0x37, 0x7A, 0x58) || at(0, 0x37, 0x7A, 0xBC, 0xAF) ||
            at(0, 0x28, 0xB5, 0x2F, 0xFD) || at(4, 0x66, 0x74, 0x79, 0x70)
        ) return Kind.MEDIA
        return Kind.OTHER
    }

    fun shannon(counts: LongArray, total: Long): Double {
        if (total <= 0) return 0.0
        var h = 0.0
        val ln2 = ln(2.0)
        for (c in counts) {
            if (c > 0) {
                val p = c.toDouble() / total
                h -= p * (ln(p) / ln2)
            }
        }
        return h
    }

    private fun analyse(zip: ZipFile, e: ZipEntry, cap: Long): EntryInfo? =
        zip.getInputStream(e).use { ins ->
            val buf = ByteArray(65536)
            val first = ins.read(buf)
            if (first <= 0) return@use null
            val name = e.name
            val kind = classify(name, name.substringAfterLast('.', "").lowercase(), buf, first)
            if (kind == Kind.MEDIA) return@use EntryInfo(kind, 0.0, first.toLong())
            val counts = LongArray(256)
            var total = 0L
            var n = first
            while (n > 0) {
                for (i in 0 until n) counts[buf[i].toInt() and 0xFF]++
                total += n
                if (total >= cap) break
                n = ins.read(buf)
            }
            EntryInfo(kind, shannon(counts, total), total)
        }

    // ---- Hashing ----------------------------------------------------------------------------
    private fun hex(b: ByteArray): String = b.joinToString("") { "%02x".format(it) }

    fun sha256(bytes: ByteArray): String = hex(MessageDigest.getInstance("SHA-256").digest(bytes))

    fun sha256(file: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { ins ->
            val buf = ByteArray(65536)
            while (true) {
                val n = ins.read(buf)
                if (n < 0) break
                md.update(buf, 0, n)
            }
        }
        return hex(md.digest())
    }

    private fun isDexName(name: String) =
        !name.contains('/') && name.startsWith("classes") && name.endsWith(".dex")

    private fun readLimited(zip: ZipFile, e: ZipEntry): ByteArray? {
        if (e.size > MAX_DEX_BYTES) return null
        return zip.getInputStream(e).use { it.readBytes() }
    }

    // ---- Main entry point -------------------------------------------------------------------
    /** apkPaths[0] must be the base APK; the rest are optional split APKs. */
    fun scan(apkPaths: List<String>): DexScanResult {
        var apkHash = ""
        var dexHash = ""
        var dexBytes = 0L
        var examined = 0
        var maxEntropy = 0.0
        var maxEntropyEntry = ""
        var budget = APK_SAMPLE_BUDGET
        val abis = Build.SUPPORTED_ABIS.toSet()
        val sigHits = LinkedHashMap<String, SignatureHit>()
        val entropyHits = ArrayList<EntropyHit>()
        val payloads = ArrayList<String>()
        val errors = ArrayList<String>()

        if (apkPaths.isNotEmpty()) {
            try {
                apkHash = sha256(File(apkPaths[0]))
            } catch (ex: Exception) {
                errors += "APK hash failed: ${ex.message}"
            }
        }

        for ((idx, path) in apkPaths.withIndex()) {
            try {
                ZipFile(path).use { zip ->
                    val en = zip.entries()
                    while (en.hasMoreElements()) {
                        val e = en.nextElement()
                        if (e.isDirectory) continue
                        val name = e.name

                        if (isDexName(name)) {
                            val bytes = readLimited(zip, e)
                            if (bytes == null) {
                                errors += "Skipped oversized $name"
                                continue
                            }
                            dexBytes += bytes.size
                            if (idx == 0 && name == "classes.dex") dexHash = sha256(bytes)
                            for (sig in SIGNATURES) {
                                if (sig.id in sigHits) continue
                                if (sig.matches(bytes)) {
                                    sigHits[sig.id] = SignatureHit(sig.id, sig.title, sig.why, sig.severity, sig.weight, name)
                                }
                            }
                        } else if (name.startsWith("assets/") || name.startsWith("lib/")) {
                            if (name.startsWith("lib/")) {
                                val abi = name.removePrefix("lib/").substringBefore('/')
                                if (abi !in abis) continue
                            }
                            if (budget <= 0) continue
                            val info = analyse(zip, e, minOf(SAMPLE_CAP, budget)) ?: continue
                            budget -= info.bytes
                            when (info.kind) {
                                Kind.MEDIA -> Unit
                                Kind.DEX, Kind.ELF, Kind.ARCHIVE -> {
                                    examined++
                                    payloads += "$name (${info.kind.label})"
                                }
                                Kind.OTHER -> if (info.bytes >= MIN_ENTROPY_BYTES) {
                                    examined++
                                    if (info.entropy > maxEntropy) {
                                        maxEntropy = info.entropy
                                        maxEntropyEntry = name
                                    }
                                    if (info.entropy > ENTROPY_THRESHOLD) {
                                        entropyHits += EntropyHit(name, info.entropy, e.size)
                                    }
                                }
                            }
                        }
                    }
                }
            } catch (ex: Exception) {
                errors += "${File(path).name}: ${ex.message}"
            }
        }

        return DexScanResult(
            apkHash, dexHash, sigHits.values.toList(), entropyHits, payloads,
            maxEntropy, maxEntropyEntry, dexBytes, examined, errors
        )
    }

    /** Turns raw findings into explained indicators, including cross-signal correlations. */
    fun toIndicators(r: DexScanResult): List<Indicator> {
        val out = ArrayList<Indicator>()

        r.signatureHits.forEach {
            out += Indicator(it.title, "${it.why}\nFound in: ${it.dexFile}", it.severity, it.weight)
        }

        val sorted = r.entropyHits.sortedByDescending { it.entropy }
        sorted.take(4).forEach {
            out += Indicator(
                "Packed/encrypted payload: ${it.entry}",
                "Shannon entropy ${f2(it.entropy)} / 8.00 over ${fmtBytes(it.size)} (flag threshold 7.2) with no recognised media or archive header. " +
                    "Encrypted or packed blobs hidden in assets/ or lib/ are the classic container for a stage-2 payload.",
                Severity.MEDIUM, 25
            )
        }
        if (sorted.size > 4) {
            out += Indicator(
                "${sorted.size - 4} more high-entropy files",
                "Additional files in assets/ or lib/ exceed the 7.2 bits/byte entropy threshold.",
                Severity.LOW, 5
            )
        }

        r.embeddedPayloads.take(3).forEach {
            out += Indicator(
                "Embedded executable payload: $it",
                "A raw DEX, ELF binary or APK/JAR is bundled inside assets/. Apps that carry a second executable stage inside their own package are staging code for later execution.",
                Severity.HIGH, 35
            )
        }

        val ids = r.signatureHits.map { it.id }.toSet()
        val loader = "DEX_CLASS_LOADER" in ids || "IN_MEMORY_DEX_LOADER" in ids
        val packed = r.entropyHits.isNotEmpty() || r.embeddedPayloads.isNotEmpty()

        if (loader && packed) {
            out += Indicator(
                "Stage-2 dropper chain",
                "Dynamic code loading is present AND the package carries a high-entropy or embedded executable payload" +
                    (if ("CRYPTO_CIPHER" in ids) " AND decryption primitives" else "") +
                    ". Together these form the standard dropper pipeline: decrypt hidden blob, load it as DEX, run it.",
                Severity.CRITICAL, 60
            )
        }
        if ("IN_MEMORY_DEX_LOADER" in ids && "CRYPTO_CIPHER" in ids) {
            out += Indicator(
                "Decrypt-then-load-in-memory pattern",
                "InMemoryDexClassLoader combined with javax.crypto.Cipher is the fileless variant of the dropper pipeline: decrypted bytes are executed without ever being written to disk.",
                Severity.HIGH, 30
            )
        }
        if ("SU_BINARY" in ids && "RUNTIME_EXEC" in ids) {
            out += Indicator(
                "Root command execution capability",
                "The app references the su binary and can spawn shell processes, so it can run commands as root on a rooted device.",
                Severity.HIGH, 30
            )
        }
        return out
    }
}
EOF

# -----------------------------------------------------------------------------
# ENGINE 2: Behavioral & stalkerware audit
# -----------------------------------------------------------------------------
cat << 'EOF' > "$SRC/BehavioralScanner.kt"
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
EOF

# -----------------------------------------------------------------------------
# Threat intelligence for the DNS firewall + VirusTotal client
# -----------------------------------------------------------------------------
cat << 'EOF' > "$SRC/ThreatIntel.kt"
package com.aegiscore.av

import android.content.Context
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/** On-device domain threat list: built-in entries + downloadable abuse.ch URLhaus host feed. */
object ThreatIntel {

    private const val FEED_URL = "https://urlhaus.abuse.ch/downloads/hostfile/"
    private const val FEED_FILE = "threat_feed.txt"
    private val WS = Regex("\\s+")

    /** Always blocked. The .invalid canary lets you test the shield from the UI. */
    private val builtin = setOf(
        "block-test.aegiscore.invalid",
        "internetbadguys.com",
        "examplemalwaredomain.com"
    )

    /** Free dynamic-DNS / tunnel hosts that Android RATs use for C2. Blocked only in strict mode. */
    private val strictSuffixes = setOf(
        "duckdns.org", "ddns.net", "no-ip.org", "no-ip.biz", "no-ip.info", "hopto.org", "zapto.org",
        "serveo.net", "ngrok.io", "ngrok.app", "ngrok-free.app", "trycloudflare.com", "loca.lt",
        "sytes.net", "servebeer.com", "myftp.biz"
    )

    /** Big shared hosts: if a feed ever lists the bare apex we skip it instead of breaking half the internet. */
    private val neverBlockApex = setOf(
        "google.com", "googleapis.com", "gstatic.com", "github.com", "githubusercontent.com",
        "cloudflare.com", "amazonaws.com", "microsoft.com", "windows.net", "apple.com", "icloud.com",
        "facebook.com", "whatsapp.com", "whatsapp.net", "dropbox.com", "telegram.org", "t.me",
        "discord.com", "discordapp.com", "pastebin.com"
    )

    @Volatile private var feed: Set<String> = emptySet()
    @Volatile var strict: Boolean = false
    @Volatile var feedUpdatedAt: Long = 0L
        private set

    fun load(ctx: Context) {
        strict = Prefs.strictDns(ctx)
        val f = File(ctx.filesDir, FEED_FILE)
        if (f.exists()) {
            try {
                feed = f.useLines { parseLines(it) }
                feedUpdatedAt = f.lastModified()
            } catch (e: Exception) {
                // ignore corrupt feed
            }
        }
    }

    fun size(): Int = feed.size + builtin.size

    /** Returns the reason a domain is blocked, or null when it is allowed. */
    fun check(domain: String): String? {
        var candidate = domain.lowercase().trimEnd('.')
        if (candidate.isEmpty()) return null
        while (true) {
            if (candidate in builtin) return "Built-in threat list"
            if (candidate in feed) return "abuse.ch URLhaus feed"
            if (strict && candidate in strictSuffixes) return "Strict mode: dynamic-DNS/tunnel host used for RAT C2"
            val dot = candidate.indexOf('.')
            if (dot < 0 || candidate.indexOf('.', dot + 1) < 0) break // never test a bare TLD
            candidate = candidate.substring(dot + 1)
        }
        return null
    }

    private fun parseLines(lines: Sequence<String>): Set<String> {
        val out = HashSet<String>(65536)
        for (raw in lines) {
            val line = raw.trim()
            if (line.isEmpty() || line.startsWith("#")) continue
            val parts = line.split(WS)
            val host = (if (parts.size >= 2) parts[1] else parts[0]).lowercase().trimEnd('.')
            if (host.isEmpty() || host == "localhost" || !host.contains('.')) continue
            if (host in neverBlockApex) continue
            if (host.all { it.isDigit() || it == '.' }) continue // raw IPs are not DNS names
            out.add(host)
        }
        return out
    }

    /** Blocking download of the URLhaus host feed. Call from a background thread. */
    fun refresh(ctx: Context): Result<Int> = runCatching {
        val conn = URL(FEED_URL).openConnection() as HttpURLConnection
        conn.connectTimeout = 15000
        conn.readTimeout = 30000
        conn.setRequestProperty("User-Agent", "AegisCoreAV/1.0")
        if (conn.responseCode != 200) error("HTTP ${conn.responseCode}")
        val tmp = File(ctx.filesDir, "$FEED_FILE.tmp")
        conn.inputStream.use { ins -> tmp.outputStream().use { ins.copyTo(it) } }
        val parsed = tmp.useLines { parseLines(it) }
        require(parsed.isNotEmpty()) { "feed was empty" }
        tmp.copyTo(File(ctx.filesDir, FEED_FILE), overwrite = true)
        tmp.delete()
        feed = parsed
        feedUpdatedAt = System.currentTimeMillis()
        parsed.size
    }
}
EOF

cat << 'EOF' > "$SRC/VirusTotalClient.kt"
package com.aegiscore.av

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/** VirusTotal API v3 hash lookup. Only the SHA-256 leaves the device; no file is ever uploaded. */
object VirusTotalClient {

    fun guiUrl(sha256: String) = "https://www.virustotal.com/gui/file/$sha256"

    /** Blocking. Call from a background thread. */
    fun lookup(sha256: String, apiKey: String): String {
        if (sha256.isBlank()) return "no hash available"
        return try {
            val c = URL("https://www.virustotal.com/api/v3/files/$sha256").openConnection() as HttpURLConnection
            c.connectTimeout = 15000
            c.readTimeout = 20000
            c.setRequestProperty("x-apikey", apiKey)
            when (val code = c.responseCode) {
                200 -> parse(c.inputStream.bufferedReader().use { it.readText() })
                404 -> "not known to VirusTotal (never submitted: unknown, not proof of safety)"
                401, 403 -> "VirusTotal rejected the API key"
                429 -> "VirusTotal rate limit reached (free keys: 4 lookups/min)"
                else -> "VirusTotal error HTTP $code"
            }
        } catch (e: Exception) {
            "lookup failed: ${e.message}"
        }
    }

    private fun parse(body: String): String {
        val s = JSONObject(body)
            .getJSONObject("data")
            .getJSONObject("attributes")
            .getJSONObject("last_analysis_stats")
        return "${s.optInt("malicious")} malicious, ${s.optInt("suspicious")} suspicious, " +
            "${s.optInt("harmless")} harmless, ${s.optInt("undetected")} undetected engines"
    }
}
EOF

# -----------------------------------------------------------------------------
# ENGINE 3: Local loopback DNS threat firewall (VpnService)
# -----------------------------------------------------------------------------
cat << 'EOF' > "$SRC/AegisVpnService.kt"
package com.aegiscore.av

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.ParcelFileDescriptor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

data class BlockedEntry(val id: Long, val domain: String, val type: String, val reason: String, val time: Long)
data class ShieldStats(val total: Long = 0, val blocked: Long = 0)

private data class DnsQuestion(val name: String, val type: Int, val end: Int)

private fun u16(b: ByteArray, o: Int): Int = ((b[o].toInt() and 0xFF) shl 8) or (b[o + 1].toInt() and 0xFF)

private object DnsCodec {
    /** Parses the first question of a DNS query. Returns null for anything malformed. */
    fun parseQuestion(d: ByteArray): DnsQuestion? {
        if (d.size < 17) return null
        if (u16(d, 4) < 1) return null
        var i = 12
        val sb = StringBuilder()
        while (true) {
            if (i >= d.size) return null
            val l = d[i].toInt() and 0xFF
            if (l == 0) { i++; break }
            if ((l and 0xC0) != 0) return null // compression pointers are not valid in a query question
            if (i + 1 + l > d.size) return null
            if (sb.isNotEmpty()) sb.append('.')
            for (k in 0 until l) sb.append((d[i + 1 + k].toInt() and 0xFF).toChar())
            i += 1 + l
        }
        if (i + 4 > d.size) return null
        return DnsQuestion(sb.toString().lowercase(), u16(d, i), i + 4)
    }

    /** Header + question only, QR=1, RA=1, RCODE=3 (NXDOMAIN), no answers. */
    fun nxdomain(query: ByteArray, end: Int): ByteArray {
        val r = query.copyOf(end)
        r[2] = (0x80 or (query[2].toInt() and 0x01)).toByte()
        r[3] = 0x83.toByte()
        for (k in 6..11) r[k] = 0
        return r
    }

    fun typeName(t: Int): String = when (t) {
        1 -> "A"; 2 -> "NS"; 5 -> "CNAME"; 12 -> "PTR"; 15 -> "MX"
        16 -> "TXT"; 28 -> "AAAA"; 33 -> "SRV"; 65 -> "HTTPS"
        else -> "TYPE$t"
    }
}

/**
 * Local DNS sinkhole. The tunnel only claims a fake DNS server address (10.99.0.2/32), so just DNS
 * lookups enter the TUN; all other traffic keeps using the normal network. Every UDP/53 packet is
 * parsed, checked against ThreatIntel and either answered with NXDOMAIN or forwarded (via a
 * protect()ed socket) to the real resolver.
 */
class AegisVpnService : VpnService() {

    companion object {
        const val ACTION_STOP = "com.aegiscore.av.STOP_SHIELD"
        private const val VPN_ADDR = "10.99.0.1"
        private const val FAKE_DNS = "10.99.0.2"
        private const val MAX_LOG = 300

        private val _running = MutableStateFlow(false)
        val running: StateFlow<Boolean> = _running.asStateFlow()

        private val _stats = MutableStateFlow(ShieldStats())
        val stats: StateFlow<ShieldStats> = _stats.asStateFlow()

        private val _blocked = MutableStateFlow<List<BlockedEntry>>(emptyList())
        val blocked: StateFlow<List<BlockedEntry>> = _blocked.asStateFlow()

        private val idGen = AtomicLong()

        fun start(ctx: Context) {
            ctx.startService(Intent(ctx, AegisVpnService::class.java))
        }

        fun stop(ctx: Context) {
            ctx.startService(Intent(ctx, AegisVpnService::class.java).setAction(ACTION_STOP))
        }
    }

    @Volatile private var active = false
    private var tun: ParcelFileDescriptor? = null
    private var worker: Thread? = null
    private var pool: ExecutorService? = null
    private var upstreams: List<InetAddress> = emptyList()

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            teardown()
            stopSelf()
            return START_NOT_STICKY
        }
        if (!active) startShield()
        return START_STICKY
    }

    override fun onRevoke() {
        teardown()
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        teardown()
        super.onDestroy()
    }

    private fun startShield() {
        upstreams = discoverUpstreams()
        val pfd = try {
            VpnService.Builder()
                .setSession("AegisCore Shield")
                .setMtu(1500)
                .addAddress(VPN_ADDR, 24)
                .addDnsServer(FAKE_DNS)
                .addRoute(FAKE_DNS, 32)
                .setBlocking(true)
                .establish()
        } catch (e: Exception) {
            null
        }
        if (pfd == null) {
            teardown()
            stopSelf()
            return
        }
        tun = pfd
        active = true
        _running.value = true
        pool = Executors.newFixedThreadPool(6)
        worker = Thread({ packetLoop(pfd) }, "aegis-dns").also { it.start() }
    }

    private fun teardown() {
        active = false
        try { worker?.interrupt() } catch (e: Exception) { }
        try { tun?.close() } catch (e: Exception) { }
        tun = null
        worker = null
        pool?.shutdownNow()
        pool = null
        _running.value = false
    }

    /** System resolvers of the underlying network (captured before the tunnel exists), then public fallbacks. */
    private fun discoverUpstreams(): List<InetAddress> {
        val found: List<InetAddress> = try {
            val cm = getSystemService(ConnectivityManager::class.java)
            val lp = cm.getLinkProperties(cm.activeNetwork)
            lp?.dnsServers?.filter { it.hostAddress != FAKE_DNS } ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
        val fallback = listOf(
            InetAddress.getByAddress(byteArrayOf(1, 1, 1, 1)),
            InetAddress.getByAddress(byteArrayOf(9, 9, 9, 9))
        )
        return found + fallback
    }

    private fun packetLoop(pfd: ParcelFileDescriptor) {
        val input = FileInputStream(pfd.fileDescriptor)
        val output = FileOutputStream(pfd.fileDescriptor)
        val buf = ByteArray(32767)
        try {
            while (active) {
                val n = input.read(buf)
                if (n < 0) break
                if (n > 0) handlePacket(buf, n, output)
            }
        } catch (e: IOException) {
            // tunnel closed
        } finally {
            if (active) {
                teardown()
                stopSelf()
            }
        }
    }

    private fun handlePacket(p: ByteArray, len: Int, out: FileOutputStream) {
        if (len < 28) return
        if ((p[0].toInt() ushr 4) != 4) return                 // IPv4 only (tunnel has no IPv6 address)
        val ihl = (p[0].toInt() and 0x0F) * 4
        if (ihl < 20 || len < ihl + 8) return
        if ((p[9].toInt() and 0xFF) != 17) return              // UDP only
        if (u16(p, ihl + 2) != 53) return                      // DNS only
        val srcPort = u16(p, ihl)
        val total = minOf(u16(p, 2), len)
        val dnsLen = total - ihl - 8
        if (dnsLen < 12) return

        val dns = p.copyOfRange(ihl + 8, ihl + 8 + dnsLen)
        val clientIp = p.copyOfRange(12, 16)
        val serverIp = p.copyOfRange(16, 20)

        _stats.update { it.copy(total = it.total + 1) }
        val q = DnsCodec.parseQuestion(dns)
        if (q != null) {
            val reason = ThreatIntel.check(q.name)
            if (reason != null) {
                record(q, reason)
                writeUdp(out, serverIp, clientIp, srcPort, DnsCodec.nxdomain(dns, q.end))
                return
            }
        }
        try {
            pool?.execute {
                val resp = forward(dns)
                if (resp != null) writeUdp(out, serverIp, clientIp, srcPort, resp)
            }
        } catch (e: Exception) {
            // pool already shut down
        }
    }

    private fun record(q: DnsQuestion, reason: String) {
        val e = BlockedEntry(idGen.incrementAndGet(), q.name, DnsCodec.typeName(q.type), reason, System.currentTimeMillis())
        _blocked.update { (listOf(e) + it).take(MAX_LOG) }
        _stats.update { it.copy(blocked = it.blocked + 1) }
    }

    private fun forward(query: ByteArray): ByteArray? {
        for (server in upstreams) {
            val s = DatagramSocket()
            try {
                protect(s)
                s.soTimeout = 3500
                s.connect(InetSocketAddress(server, 53))
                s.send(DatagramPacket(query, query.size))
                val rb = ByteArray(4096)
                val rp = DatagramPacket(rb, rb.size)
                s.receive(rp)
                return rb.copyOf(rp.length)
            } catch (e: Exception) {
                // try the next resolver
            } finally {
                s.close()
            }
        }
        return null
    }

    private fun checksum(b: ByteArray, off: Int, len: Int): Int {
        var sum = 0L
        var i = off
        while (i < off + len - 1) {
            sum += (((b[i].toInt() and 0xFF) shl 8) or (b[i + 1].toInt() and 0xFF)).toLong()
            i += 2
        }
        while ((sum shr 16) != 0L) sum = (sum and 0xFFFF) + (sum shr 16)
        return (sum.inv() and 0xFFFF).toInt()
    }

    /** Wraps [payload] in IPv4 + UDP (source port 53) and writes it back into the tunnel. */
    private fun writeUdp(out: FileOutputStream, srcIp: ByteArray, dstIp: ByteArray, dstPort: Int, payload: ByteArray) {
        val total = 20 + 8 + payload.size
        val pkt = ByteArray(total)
        pkt[0] = 0x45
        pkt[2] = (total shr 8).toByte()
        pkt[3] = total.toByte()
        pkt[6] = 0x40                       // DF
        pkt[8] = 64                         // TTL
        pkt[9] = 17                         // UDP
        System.arraycopy(srcIp, 0, pkt, 12, 4)
        System.arraycopy(dstIp, 0, pkt, 16, 4)
        val ck = checksum(pkt, 0, 20)
        pkt[10] = (ck shr 8).toByte()
        pkt[11] = ck.toByte()
        pkt[21] = 53                        // UDP source port 53 (pkt[20] stays 0)
        pkt[22] = (dstPort shr 8).toByte()
        pkt[23] = dstPort.toByte()
        val udpLen = 8 + payload.size
        pkt[24] = (udpLen shr 8).toByte()
        pkt[25] = udpLen.toByte()           // UDP checksum 0 = none (valid over IPv4)
        System.arraycopy(payload, 0, pkt, 28, payload.size)
        try {
            synchronized(out) { out.write(pkt) }
        } catch (e: IOException) {
            // tunnel closed
        }
    }
}
EOF

# -----------------------------------------------------------------------------
# ENGINE 4: Active quarantine + Shizuku controller
# -----------------------------------------------------------------------------
cat << 'EOF' > "$SRC/QuarantineController.kt"
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
EOF

# -----------------------------------------------------------------------------
# Scan orchestration
# -----------------------------------------------------------------------------
cat << 'EOF' > "$SRC/ScanCoordinator.kt"
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
EOF

# -----------------------------------------------------------------------------
# Notifications, application class
# -----------------------------------------------------------------------------
cat << 'EOF' > "$SRC/Notifier.kt"
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
EOF

cat << 'EOF' > "$SRC/AegisApp.kt"
package com.aegiscore.av

import android.app.Application

class AegisApp : Application() {
    override fun onCreate() {
        super.onCreate()
        Notifier.createChannels(this)
        ReportStore.load(this)
        Thread { ThreatIntel.load(this) }.start()
    }
}
EOF

# -----------------------------------------------------------------------------
# ENGINE 5a: Real-time install guard
# -----------------------------------------------------------------------------
cat << 'EOF' > "$SRC/PackageReceiver.kt"
package com.aegiscore.av

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap

/** Scans one package right after install/update, stores the report and alerts on HIGH/CRITICAL. */
object InstallGuard {
    fun inspect(ctx: Context, pkg: String) {
        val pi = PmCompat.packageInfo(ctx.packageManager, pkg, PackageManager.GET_PERMISSIONS) ?: return
        val report = ScanCoordinator.scanOne(ctx, pi, BehavioralScanner(ctx))
        ReportStore.upsert(ctx, report)
        if (report.severity >= Severity.HIGH) Notifier.threat(ctx, report)
    }
}

/**
 * Receives ACTION_PACKAGE_ADDED / ACTION_PACKAGE_REPLACED. Registered both in the manifest and,
 * while the Install Guard is on, dynamically from GuardService (so it keeps working when the OS
 * stops delivering package broadcasts to manifest receivers). Duplicate deliveries are collapsed.
 */
class PackageReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_PACKAGE_ADDED && action != Intent.ACTION_PACKAGE_REPLACED) return
        val pkg = intent.data?.schemeSpecificPart ?: return
        if (pkg == context.packageName) return
        // An update fires ADDED(replacing=true) followed by REPLACED: handle it once, on REPLACED.
        if (action == Intent.ACTION_PACKAGE_ADDED && intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)) return
        if (!firstSighting(pkg)) return

        val app = context.applicationContext
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                InstallGuard.inspect(app, pkg)
            } catch (t: Throwable) {
                // never crash the receiver
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        private val seen = ConcurrentHashMap<String, Long>()

        private fun firstSighting(pkg: String): Boolean {
            val now = SystemClock.elapsedRealtime()
            val prev = seen.put(pkg, now)
            return prev == null || now - prev > 10_000
        }
    }
}

/** Foreground service whose only job is to host the dynamic package receiver. */
class GuardService : Service() {

    private val receiver = PackageReceiver()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val n = Notifier.guardNotification(this)
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(Notifier.GUARD_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(Notifier.GUARD_ID, n)
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REPLACED)
            addDataScheme("package")
        }
        ContextCompat.registerReceiver(this, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        try { unregisterReceiver(receiver) } catch (e: Exception) { }
        super.onDestroy()
    }
}

/** Restarts the Install Guard after a reboot when the user had it enabled. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!Prefs.guardEnabled(context)) return
        try {
            ContextCompat.startForegroundService(context, Intent(context, GuardService::class.java))
        } catch (t: Throwable) {
            // OS refused a background foreground-service start; the guard restarts when the app is opened
        }
    }
}
EOF

# -----------------------------------------------------------------------------
# ViewModel
# -----------------------------------------------------------------------------
cat << 'EOF' > "$SRC/MainViewModel.kt"
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
EOF

# -----------------------------------------------------------------------------
# ENGINE 5b: Compose dashboard
# -----------------------------------------------------------------------------
cat << 'EOF' > "$SRC/MainActivity.kt"
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
EOF

cat << 'EOF' > "$SRC/Screens.kt"
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
EOF

# -----------------------------------------------------------------------------
# ENGINE 6: GitHub Actions cloud APK compiler
# -----------------------------------------------------------------------------
cat << 'EOF' > "$ROOT/.github/workflows/build-apk.yml"
name: Build AegisCore AV APK

on:
  push:
    branches: [ main, master ]
  pull_request:
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - name: Check out
        uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Set up Gradle
        uses: gradle/actions/setup-gradle@v3
        with:
          gradle-version: '8.9'

      - name: Generate Gradle wrapper if missing
        run: |
          if [ ! -f gradlew ]; then
            gradle wrapper --gradle-version 8.9 --no-daemon
          fi
          chmod +x gradlew

      - name: Build debug APK
        run: ./gradlew assembleDebug --no-daemon --stacktrace

      - name: Name the APK
        run: cp app/build/outputs/apk/debug/app-debug.apk AegisCore-AV-debug.apk

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: AegisCore-AV-debug.apk
          path: AegisCore-AV-debug.apk
          if-no-files-found: error
EOF

# -----------------------------------------------------------------------------
# Optional: create the real wrapper locally if Gradle happens to be installed
# -----------------------------------------------------------------------------
if command -v gradle >/dev/null 2>&1; then
  echo "==> Gradle found locally, generating wrapper (gradlew)"
  (cd "$ROOT" && gradle wrapper --gradle-version 8.9 >/dev/null 2>&1) || echo "    (wrapper generation skipped, CI will create it)"
fi

echo
echo "==> Done. Generated files:"
(cd "$ROOT" && find . -type f -not -path './.git/*' | sort)
cat << 'DONE'

Next steps (from your phone, e.g. in Termux):
  cd AegisCoreAV
  git init -b main && git add . && git commit -m "AegisCore AV"
  git remote add origin https://github.com/<you>/<repo>.git
  git push -u origin main

Then open the repo's Actions tab -> "Build AegisCore AV APK" -> download the
AegisCore-AV-debug.apk artifact, unzip it and install it.
DONE
