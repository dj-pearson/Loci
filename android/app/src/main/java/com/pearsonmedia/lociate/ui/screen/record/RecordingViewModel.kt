package com.pearsonmedia.lociate.ui.screen.record

import android.location.Location
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pearsonmedia.lociate.domain.model.Locus
import com.pearsonmedia.lociate.domain.model.LocusCategory
import com.pearsonmedia.lociate.domain.repository.LocusRepository
import com.pearsonmedia.lociate.service.AudioRecorderService
import com.pearsonmedia.lociate.service.LocationService
import com.pearsonmedia.lociate.service.SpeechRecognitionService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class RecordingViewModel @Inject constructor(
    private val audioRecorder: AudioRecorderService,
    private val speechRecognition: SpeechRecognitionService,
    private val locationService: LocationService,
    private val locusRepository: LocusRepository
) : ViewModel() {

    val isRecording = audioRecorder.isRecording
    val amplitude = audioRecorder.amplitude
    val transcription = speechRecognition.transcription
    val partialResult = speechRecognition.partialResult

    private val _currentFilePath = MutableStateFlow<String?>(null)
    val currentFilePath: StateFlow<String?> = _currentFilePath.asStateFlow()

    private val _currentLocation = MutableStateFlow<Location?>(null)
    val currentLocation: StateFlow<Location?> = _currentLocation.asStateFlow()

    private val _selectedCategory = MutableStateFlow(LocusCategory.GENERAL)
    val selectedCategory: StateFlow<LocusCategory> = _selectedCategory.asStateFlow()

    private val _isShared = MutableStateFlow(false)
    val isShared: StateFlow<Boolean> = _isShared.asStateFlow()

    private val _showPostRecording = MutableStateFlow(false)
    val showPostRecording: StateFlow<Boolean> = _showPostRecording.asStateFlow()

    private val _isSaving = MutableStateFlow(false)
    val isSaving: StateFlow<Boolean> = _isSaving.asStateFlow()

    private var amplitudeJob: Job? = null

    fun startRecording() {
        viewModelScope.launch {
            _currentLocation.value = locationService.getLastLocation()
        }

        val filePath = audioRecorder.startRecording()
        _currentFilePath.value = filePath

        speechRecognition.startListening()

        amplitudeJob = viewModelScope.launch {
            while (isActive) {
                audioRecorder.getAmplitude()
                delay(100)
            }
        }
    }

    fun stopRecording() {
        amplitudeJob?.cancel()
        audioRecorder.stopRecording()
        speechRecognition.stopListening()
        _showPostRecording.value = true
    }

    fun selectCategory(category: LocusCategory) {
        _selectedCategory.value = category
    }

    fun setShared(shared: Boolean) {
        _isShared.value = shared
    }

    fun saveLocus(onSaved: () -> Unit) {
        val filePath = _currentFilePath.value ?: return
        val location = _currentLocation.value ?: return

        _isSaving.value = true

        viewModelScope.launch {
            val locationName = locationService.reverseGeocode(
                location.latitude, location.longitude
            )

            val locus = Locus(
                latitude = location.latitude,
                longitude = location.longitude,
                locationName = locationName,
                audioFilePath = filePath,
                transcription = transcription.value,
                category = _selectedCategory.value,
                isShared = _isShared.value
            )

            locusRepository.save(locus)
            _isSaving.value = false
            onSaved()
        }
    }

    fun discardRecording() {
        _currentFilePath.value?.let { audioRecorder.deleteRecording(it) }
        _currentFilePath.value = null
        _showPostRecording.value = false
    }

    override fun onCleared() {
        super.onCleared()
        amplitudeJob?.cancel()
        speechRecognition.destroy()
    }
}
