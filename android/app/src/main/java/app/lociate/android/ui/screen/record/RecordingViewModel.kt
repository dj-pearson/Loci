package app.lociate.android.ui.screen.record

import android.content.Context
import android.location.Location
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.lociate.android.data.local.dao.HouseholdDao
import app.lociate.android.domain.model.Locus
import app.lociate.android.domain.model.LocusCategory
import app.lociate.android.domain.model.SubscriptionTier
import app.lociate.android.domain.repository.LocusRepository
import app.lociate.android.service.AICategoryService
import app.lociate.android.service.AudioRecorderService
import app.lociate.android.service.GeofenceRegistrationWorker
import app.lociate.android.service.LocationService
import app.lociate.android.service.SpeechRecognitionService
import app.lociate.android.widget.WidgetUpdater
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

@HiltViewModel
class RecordingViewModel @Inject constructor(
    private val audioRecorder: AudioRecorderService,
    private val speechRecognition: SpeechRecognitionService,
    private val locationService: LocationService,
    // US-213: the widget shows the nearest loci, so it is stale the moment a new
    // one is saved.
    private val widgetUpdater: WidgetUpdater,
    // US-216: categorization is a Premium feature, so the tier has to be read.
    private val householdDao: HouseholdDao,
    @ApplicationContext private val appContext: Context,
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

    /**
     * US-216: once the user picks a category we stop suggesting, so a late
     * transcription update cannot silently overwrite their choice.
     */
    private var userChoseCategory = false

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
        userChoseCategory = true
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

            // US-216: suggest from the *final* transcription — speech recognition
            // keeps refining it, so categorizing mid-stream would use partial text.
            // A user selection always wins.
            val category = if (userChoseCategory) {
                _selectedCategory.value
            } else {
                AICategoryService.categorize(
                    transcription = transcription.value,
                    tier = subscriptionTier()
                )
            }

            val locus = Locus(
                latitude = location.latitude,
                longitude = location.longitude,
                locationName = locationName,
                audioFilePath = filePath,
                transcription = transcription.value,
                category = category,
                isShared = _isShared.value
            )

            locusRepository.save(locus)

            // US-213: record the coordinate the widget reads and refresh it. Runs
            // after the save so a widget failure can never lose the recording.
            widgetUpdater.onLocationChanged(location.latitude, location.longitude)

            // US-219: a new locus needs a geofence, or the note it pins will never
            // trigger a proximity notification.
            GeofenceRegistrationWorker.enqueue(appContext)

            _isSaving.value = false
            onSaved()
        }
    }

    /**
     * The signed-in user's tier, defaulting to FREE.
     *
     * Failing closed matters: an unreadable profile must not hand out a paid
     * feature, and GENERAL is a harmless fallback for a suggestion.
     */
    private suspend fun subscriptionTier(): SubscriptionTier = runCatching {
        SubscriptionTier.valueOf(
            householdDao.getUserProfile()?.subscriptionTier ?: SubscriptionTier.FREE.name
        )
    }.getOrDefault(SubscriptionTier.FREE)

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
