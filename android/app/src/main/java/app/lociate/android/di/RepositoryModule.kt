package com.pearsonmedia.lociate.di

import com.pearsonmedia.lociate.data.repository.LocusRepositoryImpl
import com.pearsonmedia.lociate.domain.repository.LocusRepository
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {

    @Binds
    @Singleton
    abstract fun bindLocusRepository(impl: LocusRepositoryImpl): LocusRepository
}
