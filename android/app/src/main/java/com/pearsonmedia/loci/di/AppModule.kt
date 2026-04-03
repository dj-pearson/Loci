package com.pearsonmedia.loci.di

import android.content.Context
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.GeofencingClient
import com.google.android.gms.location.LocationServices
import com.pearsonmedia.loci.service.AudioCacheManager
import com.pearsonmedia.loci.service.AudioRecorderService
import com.pearsonmedia.loci.service.AudioPlayerService
import com.pearsonmedia.loci.service.LocationService
import com.pearsonmedia.loci.service.SpeechRecognitionService
import com.pearsonmedia.loci.util.HapticManager
import com.pearsonmedia.loci.util.LoginAttemptTracker
import com.pearsonmedia.loci.util.NetworkMonitor
import com.pearsonmedia.loci.util.SecurePreferences
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {

    @Provides
    @Singleton
    fun provideFusedLocationClient(@ApplicationContext context: Context): FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context)

    @Provides
    @Singleton
    fun provideGeofencingClient(@ApplicationContext context: Context): GeofencingClient =
        LocationServices.getGeofencingClient(context)

    @Provides
    @Singleton
    fun provideLocationService(
        @ApplicationContext context: Context,
        fusedLocationClient: FusedLocationProviderClient
    ): LocationService = LocationService(context, fusedLocationClient)

    @Provides
    @Singleton
    fun provideAudioRecorderService(
        @ApplicationContext context: Context
    ): AudioRecorderService = AudioRecorderService(context)

    @Provides
    @Singleton
    fun provideAudioPlayerService(
        @ApplicationContext context: Context
    ): AudioPlayerService = AudioPlayerService(context)

    @Provides
    @Singleton
    fun provideSpeechRecognitionService(
        @ApplicationContext context: Context
    ): SpeechRecognitionService = SpeechRecognitionService(context)

    @Provides
    @Singleton
    fun provideNetworkMonitor(
        @ApplicationContext context: Context
    ): NetworkMonitor = NetworkMonitor(context)

    @Provides
    @Singleton
    fun provideSecurePreferences(
        @ApplicationContext context: Context
    ): SecurePreferences = SecurePreferences(context)

    @Provides
    @Singleton
    fun provideLoginAttemptTracker(
        securePreferences: SecurePreferences
    ): LoginAttemptTracker = LoginAttemptTracker(securePreferences)

    @Provides
    @Singleton
    fun provideHapticManager(
        @ApplicationContext context: Context
    ): HapticManager = HapticManager(context)

    @Provides
    @Singleton
    fun provideAudioCacheManager(
        @ApplicationContext context: Context
    ): AudioCacheManager = AudioCacheManager(context)
}
