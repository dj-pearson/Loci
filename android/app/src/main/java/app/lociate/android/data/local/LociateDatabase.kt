package app.lociate.android.data.local

import androidx.room.Database
import androidx.room.RoomDatabase
import app.lociate.android.data.local.dao.HouseholdDao
import app.lociate.android.data.local.dao.LocusDao
import app.lociate.android.data.local.entity.HouseholdEntity
import app.lociate.android.data.local.entity.HouseholdMemberEntity
import app.lociate.android.data.local.entity.LocusEntity
import app.lociate.android.data.local.entity.UserProfileEntity

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
