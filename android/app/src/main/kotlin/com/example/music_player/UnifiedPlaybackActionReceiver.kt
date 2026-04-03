package com.example.music_player

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.ryanheise.audioservice.AudioService

class UnifiedPlaybackActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        AudioService.dispatchCustomAction(action, intent.extras)
    }
}
