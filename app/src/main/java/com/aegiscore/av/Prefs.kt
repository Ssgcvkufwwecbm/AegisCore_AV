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
