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
