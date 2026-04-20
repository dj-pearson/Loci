package app.lociate.android.ui.screen.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.lociate.android.domain.model.Locus
import app.lociate.android.domain.repository.LocusRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

@OptIn(FlowPreview::class)
@HiltViewModel
class SearchViewModel @Inject constructor(
    private val locusRepository: LocusRepository
) : ViewModel() {

    private val _query = MutableStateFlow("")

    val results: StateFlow<List<Locus>> = _query
        .debounce(300)
        .flatMapLatest { query ->
            if (query.length >= 2) {
                locusRepository.search(query)
            } else {
                flowOf(emptyList())
            }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun search(query: String) {
        _query.value = query
    }
}
