package com.pearsonmedia.lociate.service

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import timber.log.Timber
import java.io.File
import java.util.UUID

class AudioRecorderService(private val context: Context) {

    private var recorder: MediaRecorder? = null
    private var currentFile: File? = null

    private val _isRecording = MutableStateFlow(false)
    val isRecording: StateFlow<Boolean> = _isRecording.asStateFlow()

    private val _amplitude = MutableStateFlow(0f)
    val amplitude: StateFlow<Float> = _amplitude.asStateFlow()

    private val audioDir: File
        get() = File(context.filesDir, "audio").also { it.mkdirs() }

    fun startRecording(): String {
        val fileName = "${UUID.randomUUID()}.m4a"
        val file = File(audioDir, fileName)
        currentFile = file

        recorder = createMediaRecorder().apply {
            setAudioSource(MediaRecorder.AudioSource.MIC)
            setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            setAudioSamplingRate(44100)
            setAudioEncodingBitRate(64000) // 64kbps mono — matches iOS
            setAudioChannels(1)
            setOutputFile(file.absolutePath)

            try {
                prepare()
                start()
                _isRecording.value = true
                Timber.d("Recording started: ${file.absolutePath}")
            } catch (e: Exception) {
                Timber.e(e, "Failed to start recording")
                throw e
            }
        }

        return file.absolutePath
    }

    fun stopRecording(): String? {
        return try {
            recorder?.apply {
                stop()
                release()
            }
            recorder = null
            _isRecording.value = false
            _amplitude.value = 0f
            Timber.d("Recording stopped: ${currentFile?.absolutePath}")
            currentFile?.absolutePath
        } catch (e: Exception) {
            Timber.e(e, "Failed to stop recording")
            recorder?.release()
            recorder = null
            _isRecording.value = false
            null
        }
    }

    fun getAmplitude(): Float {
        return try {
            val maxAmplitude = recorder?.maxAmplitude ?: 0
            val normalized = maxAmplitude.toFloat() / 32767f
            _amplitude.value = normalized
            normalized
        } catch (e: Exception) {
            0f
        }
    }

    fun deleteRecording(filePath: String) {
        try {
            File(filePath).delete()
        } catch (e: Exception) {
            Timber.e(e, "Failed to delete recording")
        }
    }

    fun getAudioFileSize(filePath: String): Long {
        return try {
            File(filePath).length()
        } catch (e: Exception) {
            0L
        }
    }

    private fun createMediaRecorder(): MediaRecorder {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
    }
}
