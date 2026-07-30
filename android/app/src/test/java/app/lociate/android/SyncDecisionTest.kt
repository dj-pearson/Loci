package app.lociate.android

import app.lociate.android.data.remote.api.SyncRepository
import app.lociate.android.data.remote.api.SyncUploadResult
import app.lociate.android.service.SyncDecision
import app.lociate.android.service.SyncWorker
import com.google.common.truth.Truth.assertThat
import org.junit.Test

/**
 * US-194: the sync worker used to mark every pending locus SYNCED without
 * uploading anything, so a paying user's notes never left the device while the
 * app said they were backed up. These cover the retry policy that replaced it.
 */
class SyncDecisionTest {

    @Test
    fun `nothing pending succeeds without a retry`() {
        val outcome = SyncUploadResult(uploaded = 0, failed = 0, retryable = false)

        assertThat(SyncDecision.from(outcome, runAttemptCount = 0))
            .isEqualTo(SyncDecision.SUCCESS)
    }

    @Test
    fun `a clean pass succeeds`() {
        val outcome = SyncUploadResult(uploaded = 5, failed = 0, retryable = false)

        assertThat(SyncDecision.from(outcome, runAttemptCount = 0))
            .isEqualTo(SyncDecision.SUCCESS)
    }

    @Test
    fun `a partial failure retries so the outstanding loci are not abandoned`() {
        val outcome = SyncUploadResult(uploaded = 3, failed = 2, retryable = true)

        assertThat(SyncDecision.from(outcome, runAttemptCount = 0))
            .isEqualTo(SyncDecision.RETRY)
    }

    @Test
    fun `a thrown pass retries rather than reporting success`() {
        // The critical regression guard: a failed upload must never look like a
        // completed sync.
        assertThat(SyncDecision.from(null, runAttemptCount = 0))
            .isEqualTo(SyncDecision.RETRY)
    }

    @Test
    fun `retries stop at the attempt cap`() {
        val outcome = SyncUploadResult(uploaded = 0, failed = 1, retryable = true)

        assertThat(SyncDecision.from(outcome, runAttemptCount = SyncWorker.MAX_ATTEMPTS - 1))
            .isEqualTo(SyncDecision.RETRY)
        assertThat(SyncDecision.from(outcome, runAttemptCount = SyncWorker.MAX_ATTEMPTS))
            .isEqualTo(SyncDecision.FAILURE)
        assertThat(SyncDecision.from(null, runAttemptCount = SyncWorker.MAX_ATTEMPTS))
            .isEqualTo(SyncDecision.FAILURE)
    }

    @Test
    fun `a non-retryable failure fails immediately`() {
        val outcome = SyncUploadResult(uploaded = 0, failed = 1, retryable = false)

        assertThat(SyncDecision.from(outcome, runAttemptCount = 0))
            .isEqualTo(SyncDecision.FAILURE)
    }
}

/**
 * US-194: the storage bucket and object path have to match what iOS writes and
 * what the RLS policy in backend/migrations/005_storage_bucket.sql enforces.
 * Android previously used bucket "audio" (which does not exist) and a
 * `loci/<id>/<file>` layout whose first path segment is not the user id, so every
 * upload would have been rejected even once the worker started calling it.
 */
class SyncStoragePathTest {

    @Test
    fun `bucket matches the one created by migration 005`() {
        assertThat(SyncRepository.AUDIO_BUCKET).isEqualTo("loci-audio")
    }

    @Test
    fun `object path starts with the user id so storage RLS permits the insert`() {
        val userId = "11111111-2222-3333-4444-555555555555"
        val locusId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

        val path = SyncRepository.remoteAudioPath(userId, locusId)

        assertThat(path).isEqualTo("$userId/$locusId.m4a")
        assertThat(path.substringBefore('/')).isEqualTo(userId)
    }

    @Test
    fun `object path matches the iOS AudioSyncService layout`() {
        // iOS builds "\(userId)/\(locus.id.uuidString).m4a" — a household member
        // on the other platform must resolve the same object.
        val userId = "user-1"
        val locusId = "locus-1"

        assertThat(SyncRepository.remoteAudioPath(userId, locusId)).isEqualTo("user-1/locus-1.m4a")
    }
}
