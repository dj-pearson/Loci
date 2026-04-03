package com.pearsonmedia.loci.di

import com.pearsonmedia.loci.data.repository.LocusRepositoryImpl
import com.pearsonmedia.loci.domain.repository.LocusRepository
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
