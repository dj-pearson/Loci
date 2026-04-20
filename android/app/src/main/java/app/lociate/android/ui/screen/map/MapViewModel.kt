package app.lociate.android.ui.screen.map

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.lociate.android.domain.model.Locus
import app.lociate.android.domain.model.LocusCategory
import app.lociate.android.domain.repository.LocusRepository
import app.lociate.android.service.LocationService
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

@HiltViewModel
class MapViewModel @Inject constructor(
    private val locusRepository: LocusRepository,
    val locationService: LocationService
) : ViewModel() {

    private val _selectedCategory = MutableStateFlow<LocusCategory?>(null)
    val selectedCategory: StateFlow<LocusCategory?> = _selectedCategory.asStateFlow()

    val loci: StateFlow<List<Locus>> = combine(
        locusRepository.observeAllActive(),
        _selectedCategory
    ) { allLoci, category ->
        if (category != null) {
            allLoci.filter { it.category == category }
        } else {
            allLoci
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val activeCount: StateFlow<Int> = locusRepository.observeActiveCount()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), 0)

    fun selectCategory(category: LocusCategory?) {
        _selectedCategory.value = category
    }
}
