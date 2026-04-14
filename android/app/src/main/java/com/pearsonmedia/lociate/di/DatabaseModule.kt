package com.pearsonmedia.lociate.di

import android.content.Context
import androidx.room.Room
import com.pearsonmedia.lociate.data.local.LociateDatabase
import com.pearsonmedia.lociate.data.local.dao.HouseholdDao
import com.pearsonmedia.lociate.data.local.dao.LocusDao
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
            .fallbackToDestructiveMigration()
            .build()
    }

    @Provides
    fun provideLocusDao(database: LociateDatabase): LocusDao = database.locusDao()

    @Provides
    fun provideHouseholdDao(database: LociateDatabase): HouseholdDao = database.householdDao()
}
