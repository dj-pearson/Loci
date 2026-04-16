package com.pearsonmedia.lociate.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import com.pearsonmedia.lociate.data.local.dao.HouseholdDao
import com.pearsonmedia.lociate.data.local.dao.LocusDao
import com.pearsonmedia.lociate.data.local.entity.HouseholdEntity
import com.pearsonmedia.lociate.data.local.entity.HouseholdMemberEntity
import com.pearsonmedia.lociate.data.local.entity.LocusEntity
import com.pearsonmedia.lociate.data.local.entity.UserProfileEntity

@Database(
    entities = [
        LocusEntity::class,
        HouseholdEntity::class,
        HouseholdMemberEntity::class,
        UserProfileEntity::class
    ],
    version = 1,
    exportSchema = true
)
abstract class LociateDatabase : RoomDatabase() {
    abstract fun locusDao(): LocusDao
    abstract fun householdDao(): HouseholdDao
}
