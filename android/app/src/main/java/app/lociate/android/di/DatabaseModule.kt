package app.lociate.android.di

import android.content.Context
import androidx.room.Room
import app.lociate.android.data.local.LociateDatabase
import app.lociate.android.data.local.LociateDatabaseMigrations
import app.lociate.android.data.local.dao.HouseholdDao
import app.lociate.android.data.local.dao.AuditLogDao
import app.lociate.android.data.local.dao.LocusDao
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    @Provides
    @Singleton
    fun provideDatabase(@ApplicationContext context: Context): LociateDatabase {
        return Room.databaseBuilder(
            context,
            LociateDatabase::class.java,
            "loci_database"
        )
            // US-216: was fallbackToDestructiveMigration(), which drops and recreates
            // the database on ANY schema change. In an offline-first app that means
            // silently destroying voice notes that had not synced yet. Real
            // migrations only — a failed migration should crash loudly in testing
            // rather than delete a user's recordings in production.
            .addMigrations(*LociateDatabaseMigrations.ALL)
            .build()
    }

    @Provides
    fun provideLocusDao(database: LociateDatabase): LocusDao = database.locusDao()

    @Provides
    fun provideAuditLogDao(database: LociateDatabase): AuditLogDao = database.auditLogDao()

    @Provides
    fun provideHouseholdDao(database: LociateDatabase): HouseholdDao = database.householdDao()
}
