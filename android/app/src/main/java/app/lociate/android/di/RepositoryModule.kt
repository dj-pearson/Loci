package app.lociate.android.di

import app.lociate.android.data.repository.LocusRepositoryImpl
import app.lociate.android.domain.repository.LocusRepository
import app.lociate.android.service.AndroidDeviceInfoProvider
import app.lociate.android.service.DeviceInfoProvider
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

    /**
     * US-216: behind an interface so SecurityAuditLogger is testable on the JVM —
     * android.os.Build is not readable outside an Android runtime.
     */
    @Binds
    @Singleton
    abstract fun bindDeviceInfoProvider(impl: AndroidDeviceInfoProvider): DeviceInfoProvider
}
