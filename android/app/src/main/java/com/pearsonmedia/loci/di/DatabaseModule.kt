package com.pearsonmedia.loci.di

import android.content.Context
import androidx.room.Room
import com.pearsonmedia.loci.data.local.LociDatabase
import com.pearsonmedia.loci.data.local.dao.HouseholdDao
import com.pearsonmedia.loci.data.local.dao.LocusDao
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
    fun provideDatabase(@ApplicationContext context: Context): LociDatabase {
        return Room.databaseBuilder(
            context,
            LociDatabase::class.java,
            "loci_database"
        )
            .fallbackToDestructiveMigration()
            .build()
    }

    @Provides
    fun provideLocusDao(database: LociDatabase): LocusDao = database.locusDao()

    @Provides
    fun provideHouseholdDao(database: LociDatabase): HouseholdDao = database.householdDao()
}
