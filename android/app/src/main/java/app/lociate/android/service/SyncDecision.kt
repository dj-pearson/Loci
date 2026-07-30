package app.lociate.android.service

import app.lociate.android.data.remote.api.SyncUploadResult

/**
 * What [SyncWorker] should tell WorkManager after an upload pass.
 *
 * US-194: kept as a pure function so the retry policy is unit-testable on the
 * JVM. Deciding this inline in `doWork()` would make it reachable only from an
 * instrumented test with a real `Context`, which is why the previous behaviour —
 * marking every locus SYNCED without uploading — went unnoticed.
 */
enum class SyncDecision {
    SUCCESS,
    RETRY,
    FAILURE;

    companion object {
        /**
         * @param outcome the upload result, or null when the pass threw or the
         *   repository returned a failed [Result].
         * @param runAttemptCount WorkManager's zero-based attempt counter.
         */
        fun from(outcome: SyncUploadResult?, runAttemptCount: Int): SyncDecision {
            // A pass that could not run at all is always worth retrying until the
            // cap: the usual cause is a network or session hiccup.
            if (outcome == null) {
                return retryOrFail(runAttemptCount)
            }

            // Nothing pending, or nothing uploadable yet (e.g. signed out).
            if (outcome.attempted == 0) {
                return SUCCESS
            }

            if (outcome.failed == 0) {
                return SUCCESS
            }

            // Partial failure. Loci that succeeded are already marked SYNCED, so a
            // retry only picks up what is still outstanding — no duplicate uploads.
            return if (outcome.retryable) retryOrFail(runAttemptCount) else FAILURE
        }

        private fun retryOrFail(runAttemptCount: Int): SyncDecision =
            if (runAttemptCount < SyncWorker.MAX_ATTEMPTS) RETRY else FAILURE
    }
}
