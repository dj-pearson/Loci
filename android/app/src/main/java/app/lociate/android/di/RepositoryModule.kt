package app.lociate.android.di

import app.lociate.android.data.repository.LocusRepositoryImpl
import app.lociate.android.domain.repository.LocusRepository
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
