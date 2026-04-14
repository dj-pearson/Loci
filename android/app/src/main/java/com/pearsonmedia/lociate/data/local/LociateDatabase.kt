package com.pearsonmedia.loci.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import com.pearsonmedia.loci.data.local.dao.HouseholdDao
import com.pearsonmedia.loci.data.local.dao.LocusDao
import com.pearsonmedia.loci.data.local.entity.HouseholdEntity
import com.pearsonmedia.loci.data.local.entity.HouseholdMemberEntity
import com.pearsonmedia.loci.data.local.entity.LocusEntity
import com.pearsonmedia.loci.data.local.entity.UserProfileEntity

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
abstract class LociDatabase : RoomDatabase() {
    abstract fun locusDao(): LocusDao
    abstract fun householdDao(): HouseholdDao
}
