package com.pearsonmedia.loci.ui.screen.household

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pearsonmedia.loci.data.remote.SupabaseClientProvider
import com.pearsonmedia.loci.domain.model.Household
import com.pearsonmedia.loci.domain.model.HouseholdMember
import com.pearsonmedia.loci.domain.model.MemberRole
import com.pearsonmedia.loci.domain.model.SubscriptionTier
import dagger.hilt.android.lifecycle.HiltViewModel
import io.github.jan.supabase.postgrest.from
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

data class HouseholdUiState(
    val household: Household? = null,
    val members: List<HouseholdMember> = emptyList(),
    val isLoading: Boolean = false,
    val error: String? = null,
    val inviteCode: String? = null,
    val currentTier: SubscriptionTier = SubscriptionTier.FREE,
    val joinSuccess: Boolean = false,
    val createSuccess: Boolean = false
)

@HiltViewModel
class HouseholdViewModel @Inject constructor() : ViewModel() {

    private val _uiState = MutableStateFlow(HouseholdUiState())
    val uiState: StateFlow<HouseholdUiState> = _uiState.asStateFlow()

    init {
        loadHousehold()
    }

    fun loadHousehold() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                val supabase = SupabaseClientProvider.client
                val user = supabase.auth.currentUserOrNull()
                if (user == null) {
                    _uiState.update { it.copy(isLoading = false) }
                    return@launch
                }

                // Load household membership
                val memberResult = supabase.from("household_members")
                    .select { filter { eq("user_id", user.id) } }
                    .decodeList<HouseholdMemberDto>()

                if (memberResult.isNotEmpty()) {
                    val householdId = memberResult.first().householdId
                    val householdResult = supabase.from("households")
                        .select { filter { eq("id", householdId) } }
                        .decodeSingleOrNull<HouseholdDto>()

                    val allMembers = supabase.from("household_members")
                        .select { filter { eq("household_id", householdId) } }
                        .decodeList<HouseholdMemberDto>()

                    _uiState.update {
                        it.copy(
                            household = householdResult?.toDomain(),
                            members = allMembers.map { m -> m.toDomain() },
                            inviteCode = householdResult?.inviteCode,
                            isLoading = false
                        )
                    }
                } else {
                    _uiState.update { it.copy(isLoading = false) }
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }

    fun createHousehold(name: String) {
        if (_uiState.value.currentTier != SubscriptionTier.FAMILY) {
            _uiState.update { it.copy(error = "Family plan required to create a household.") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                val supabase = SupabaseClientProvider.client
                val user = supabase.auth.currentUserOrNull() ?: return@launch
                val inviteCode = UUID.randomUUID().toString().take(8).uppercase()

                val dto = CreateHouseholdDto(
                    name = name,
                    ownerId = user.id,
                    inviteCode = inviteCode
                )

                supabase.from("households").insert(dto)

                _uiState.update {
                    it.copy(
                        isLoading = false,
                        inviteCode = inviteCode,
                        createSuccess = true
                    )
                }
                loadHousehold()
            } catch (e: Exception) {
                _uiState.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }

    fun joinHousehold(code: String) {
        if (_uiState.value.currentTier == SubscriptionTier.FREE) {
            _uiState.update { it.copy(error = "Premium or Family plan required.") }
            return
        }

        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                val supabase = SupabaseClientProvider.client
                val user = supabase.auth.currentUserOrNull() ?: return@launch

                val household = supabase.from("households")
                    .select { filter { eq("invite_code", code.uppercase()) } }
                    .decodeSingleOrNull<HouseholdDto>()

                if (household == null) {
                    _uiState.update { it.copy(isLoading = false, error = "Invalid invite code.") }
                    return@launch
                }

                val memberDto = JoinHouseholdDto(
                    householdId = household.id,
                    userId = user.id,
                    displayName = user.email ?: "Member",
                    role = "member"
                )

                supabase.from("household_members").insert(memberDto)

                _uiState.update { it.copy(isLoading = false, joinSuccess = true) }
                loadHousehold()
            } catch (e: Exception) {
                _uiState.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }

    fun removeMember(memberId: UUID) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                val supabase = SupabaseClientProvider.client
                supabase.from("household_members")
                    .delete { filter { eq("id", memberId.toString()) } }
                loadHousehold()
            } catch (e: Exception) {
                _uiState.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }

    fun leaveHousehold() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                val supabase = SupabaseClientProvider.client
                val user = supabase.auth.currentUserOrNull() ?: return@launch
                supabase.from("household_members")
                    .delete { filter { eq("user_id", user.id) } }
                _uiState.update {
                    it.copy(household = null, members = emptyList(), inviteCode = null, isLoading = false)
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }
}

// DTOs for Supabase serialization
@kotlinx.serialization.Serializable
private data class HouseholdDto(
    val id: String,
    val name: String,
    @kotlinx.serialization.SerialName("owner_id") val ownerId: String,
    @kotlinx.serialization.SerialName("invite_code") val inviteCode: String,
    @kotlinx.serialization.SerialName("invite_expires_at") val inviteExpiresAt: String? = null,
    @kotlinx.serialization.SerialName("created_at") val createdAt: String? = null
) {
    fun toDomain() = Household(
        id = UUID.fromString(id),
        name = name,
        ownerId = UUID.fromString(ownerId),
        inviteCode = inviteCode,
        inviteExpiresAt = java.time.Instant.parse(inviteExpiresAt ?: java.time.Instant.now().plusSeconds(86400 * 7).toString()),
        createdAt = java.time.Instant.parse(createdAt ?: java.time.Instant.now().toString())
    )
}

@kotlinx.serialization.Serializable
private data class HouseholdMemberDto(
    val id: String = "",
    @kotlinx.serialization.SerialName("household_id") val householdId: String,
    @kotlinx.serialization.SerialName("user_id") val userId: String,
    @kotlinx.serialization.SerialName("display_name") val displayName: String = "",
    val role: String = "member"
) {
    fun toDomain() = HouseholdMember(
        id = if (id.isNotEmpty()) UUID.fromString(id) else UUID.randomUUID(),
        householdId = UUID.fromString(householdId),
        userId = UUID.fromString(userId),
        displayName = displayName,
        role = if (role == "owner") MemberRole.OWNER else MemberRole.MEMBER
    )
}

@kotlinx.serialization.Serializable
private data class CreateHouseholdDto(
    val name: String,
    @kotlinx.serialization.SerialName("owner_id") val ownerId: String,
    @kotlinx.serialization.SerialName("invite_code") val inviteCode: String
)

@kotlinx.serialization.Serializable
private data class JoinHouseholdDto(
    @kotlinx.serialization.SerialName("household_id") val householdId: String,
    @kotlinx.serialization.SerialName("user_id") val userId: String,
    @kotlinx.serialization.SerialName("display_name") val displayName: String,
    val role: String
)
