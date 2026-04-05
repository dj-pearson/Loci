package com.pearsonmedia.loci.util

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manages haptic feedback for user interactions.
 * Matches iOS HapticManager pattern.
 */
@Singleton
class HapticManager @Inject constructor(
    private val context: Context
) {
    private val vibrator: Vibrator by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            manager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }

    fun light() {
        vibrate(VibrationEffect.createOneShot(30, VibrationEffect.DEFAULT_AMPLITUDE))
    }

    fun medium() {
        vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
    }

    fun heavy() {
        vibrate(VibrationEffect.createOneShot(80, VibrationEffect.DEFAULT_AMPLITUDE))
    }

    fun success() {
        val timings = longArrayOf(0, 50, 50, 100)
        val amplitudes = intArrayOf(0, 80, 0, 160)
        vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
    }

    fun error() {
        val timings = longArrayOf(0, 100, 50, 100, 50, 100)
        val amplitudes = intArrayOf(0, 200, 0, 200, 0, 200)
        vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
    }

    fun selection() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK))
        } else {
            light()
        }
    }

    // --- Premium sequences (US-169) ---

    /**
     * Two-beat "lock-in" feel when a recording starts: medium impact
     * followed by a light tap ~90ms later.
     */
    fun recordStartSequence() {
        val timings = longArrayOf(0, 50, 40, 20)
        val amplitudes = intArrayOf(0, 180, 0, 90)
        vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
    }

    /**
     * Light tap priming the user before a success chime — used when a
     * locus is saved.
     */
    fun saveSuccessSequence() {
        val timings = longArrayOf(0, 25, 90, 40, 40, 100)
        val amplitudes = intArrayOf(0, 90, 0, 140, 0, 200)
        vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
    }

    /**
     * Selection → heavy impact → success celebration. Used when a paid
     * tier is unlocked or a household invite is accepted.
     */
    fun unlockSequence() {
        val timings = longArrayOf(0, 20, 80, 80, 120, 60, 60, 100)
        val amplitudes = intArrayOf(0, 80, 0, 220, 0, 140, 0, 200)
        vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
    }

    private fun vibrate(effect: VibrationEffect) {
        if (vibrator.hasVibrator()) {
            vibrator.vibrate(effect)
        }
    }
}
