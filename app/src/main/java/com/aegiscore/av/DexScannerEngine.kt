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
