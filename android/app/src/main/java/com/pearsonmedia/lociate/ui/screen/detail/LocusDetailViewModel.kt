package com.pearsonmedia.lociate.ui.screen.detail

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pearsonmedia.lociate.domain.model.Locus
import com.pearsonmedia.lociate.domain.model.LocusCategory
import com.pearsonmedia.lociate.domain.repository.LocusRepository
import com.pearsonmedia.lociate.service.AudioPlayerService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.time.Instant
import javax.inject.Inject

@HiltViewModel
class LocusDetailViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val locusRepository: LocusRepository,
    val audioPlayer: AudioPlayerService
) : ViewModel() {

    private val locusId: String = savedStateHandle["locusId"] ?: ""

    val locus: StateFlow<Locus?> = locusRepository.observeById(locusId)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    val isPlaying = audioPlayer.isPlaying
    val playbackProgress = audioPlayer.progress
    val playbackDuration = audioPlayer.duration
    val playbackPosition = audioPlayer.currentPosition

    private val _showEditSheet = MutableStateFlow(false)
    val showEditSheet: StateFlow<Boolean> = _showEditSheet.asStateFlow()

    fun playPause() {
        val currentLocus = locus.value ?: return

        if (audioPlayer.isPlaying.value) {
            audioPlayer.pause()
        } else {
            audioPlayer.play(currentLocus.audioFilePath)
        }
    }

    fun seekTo(positionMs: Int) {
        audioPlayer.seekTo(positionMs)
    }

    fun showEdit() {
        _showEditSheet.value = true
    }

    fun hideEdit() {
        _showEditSheet.value = false
    }

    fun updateCategory(category: LocusCategory) {
        val current = locus.value ?: return
        viewModelScope.launch {
            locusRepository.update(
                current.copy(category = category, updatedAt = Instant.now())
            )
        }
    }

    fun archive() {
        viewModelScope.launch {
            locusRepository.archive(locusId)
        }
    }

    fun delete() {
        viewModelScope.launch {
            locusRepository.delete(locusId)
        }
    }

    override fun onCleared() {
        super.onCleared()
        audioPlayer.stop()
    }
}
