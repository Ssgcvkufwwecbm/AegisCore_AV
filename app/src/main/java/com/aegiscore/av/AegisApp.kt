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
