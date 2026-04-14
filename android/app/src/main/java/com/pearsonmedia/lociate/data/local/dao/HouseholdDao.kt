package com.pearsonmedia.lociate.data.local.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.pearsonmedia.lociate.data.local.entity.HouseholdEntity
import com.pearsonmedia.lociate.data.local.entity.HouseholdMemberEntity
import com.pearsonmedia.lociate.data.local.entity.UserProfileEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface HouseholdDao {

    @Query("SELECT * FROM households LIMIT 1")
    fun observeHousehold(): Flow<HouseholdEntity?>

    @Query("SELECT * FROM household_members WHERE household_id = :householdId")
    fun observeMembers(householdId: String): Flow<List<HouseholdMemberEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertHousehold(household: HouseholdEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertMember(member: HouseholdMemberEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertMembers(members: List<HouseholdMemberEntity>)

    @Query("DELETE FROM households WHERE id = :id")
    suspend fun deleteHousehold(id: String)

    @Query("DELETE FROM household_members WHERE id = :id")
    suspend fun deleteMember(id: String)

    // User Profile
    @Query("SELECT * FROM user_profile LIMIT 1")
    fun observeUserProfile(): Flow<UserProfileEntity?>

    @Query("SELECT * FROM user_profile LIMIT 1")
    suspend fun getUserProfile(): UserProfileEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertUserProfile(profile: UserProfileEntity)

    @Query("UPDATE user_profile SET subscription_tier = :tier WHERE id = :id")
    suspend fun updateSubscriptionTier(id: String, tier: String)

    @Query("DELETE FROM user_profile")
    suspend fun clearUserProfile()
}
