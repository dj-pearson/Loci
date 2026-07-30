package app.lociate.android

import android.app.Application
import android.content.Context
import androidx.test.runner.AndroidJUnitRunner
import dagger.hilt.android.testing.HiltTestApplication

/**
 * US-192: `build.gradle.kts` has always named this class as the
 * `testInstrumentationRunner`, but it did not exist and there was no
 * `androidTest` source set at all — so `connectedAndroidTest` could not even be
 * configured, let alone run.
 *
 * Instrumented tests need [HiltTestApplication] rather than [LociateApplication]
 * so that `@HiltAndroidTest` can swap modules per test. Substituting the
 * application class is the runner's job, hence this subclass.
 */
class HiltTestRunner : AndroidJUnitRunner() {
    override fun newApplication(
        classLoader: ClassLoader?,
        className: String?,
        context: Context?
    ): Application = super.newApplication(classLoader, HiltTestApplication::class.java.name, context)
}
