package app.lociate.android.service

import android.content.Context
import android.media.MediaPlayer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import timber.log.Timber

class AudioPlayerService(private val context: Context) {

    private var mediaPlayer: MediaPlayer? = null
    private var progressJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.Main)

    private val _isPlaying = MutableStateFlow(false)
    val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    private val _progress = MutableStateFlow(0f)
    val progress: StateFlow<Float> = _progress.asStateFlow()

    private val _duration = MutableStateFlow(0)
    val duration: StateFlow<Int> = _duration.asStateFlow()

    private val _currentPosition = MutableStateFlow(0)
    val currentPosition: StateFlow<Int> = _currentPosition.asStateFlow()

    fun play(filePath: String) {
        stop()

        try {
            mediaPlayer = MediaPlayer().apply {
                setDataSource(filePath)
                prepare()
                start()

                _duration.value = duration
                _isPlaying.value = true

                setOnCompletionListener {
                    _isPlaying.value = false
                    _progress.value = 0f
                    _currentPosition.value = 0
                    progressJob?.cancel()
                }
            }

            startProgressUpdates()
        } catch (e: Exception) {
            Timber.e(e, "Failed to play audio: $filePath")
        }
    }

    fun pause() {
        mediaPlayer?.pause()
        _isPlaying.value = false
        progressJob?.cancel()
    }

    fun resume() {
        mediaPlayer?.start()
        _isPlaying.value = true
        startProgressUpdates()
    }

    fun seekTo(positionMs: Int) {
        mediaPlayer?.seekTo(positionMs)
        _currentPosition.value = positionMs
        val dur = mediaPlayer?.duration ?: 1
        _progress.value = positionMs.toFloat() / dur.toFloat()
    }

    fun stop() {
        progressJob?.cancel()
        mediaPlayer?.apply {
            if (isPlaying) stop()
            release()
        }
        mediaPlayer = null
        _isPlaying.value = false
        _progress.value = 0f
        _currentPosition.value = 0
    }

    private fun startProgressUpdates() {
        progressJob?.cancel()
        progressJob = scope.launch {
            while (isActive) {
                mediaPlayer?.let { player ->
                    if (player.isPlaying) {
                        val pos = player.currentPosition
                        val dur = player.duration.coerceAtLeast(1)
                        _currentPosition.value = pos
                        _progress.value = pos.toFloat() / dur.toFloat()
                    }
                }
                delay(100)
            }
        }
    }
}
