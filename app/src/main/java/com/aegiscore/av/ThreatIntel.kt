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
