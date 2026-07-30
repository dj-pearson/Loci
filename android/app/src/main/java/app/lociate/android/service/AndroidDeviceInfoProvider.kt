package app.lociate.android.service

import android.os.Build
import app.lociate.android.BuildConfig
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Real device description for audit entries (US-216).
 *
 * Model and OS version only — no serial, no advertising id, nothing that
 * identifies the device across installs. The point is "which of my devices was
 * this", not fingerprinting.
 */
@Singleton
class AndroidDeviceInfoProvider @Inject constructor() : DeviceInfoProvider {
    override fun describe(): String = "${Build.MODEL} (Android ${Build.VERSION.RELEASE})"

    override fun appVersion(): String = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"
}
