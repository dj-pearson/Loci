package app.lociate.android.service

import android.content.Context
import timber.log.Timber
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * LRU cache manager for audio files.
 * Evicts least-recently-used files when cache exceeds max size.
 */
@Singleton
class AudioCacheManager @Inject constructor(
    private val context: Context
) {
    companion object {
        private const val CACHE_DIR_NAME = "audio_cache"
        private const val MAX_CACHE_SIZE_BYTES = 100L * 1024 * 1024 // 100 MB
    }

    private val cacheDir: File
        get() = File(context.cacheDir, CACHE_DIR_NAME).also { it.mkdirs() }

    fun getCachedFile(fileName: String): File? {
        val file = File(cacheDir, fileName)
        if (file.exists()) {
            // Update last modified to mark as recently used
            file.setLastModified(System.currentTimeMillis())
            return file
        }
        return null
    }

    fun cacheFile(fileName: String, data: ByteArray): File {
        evictIfNeeded(data.size.toLong())
        val file = File(cacheDir, fileName)
        file.writeBytes(data)
        Timber.d("Cached audio file: $fileName (${data.size} bytes)")
        return file
    }

    fun removeCachedFile(fileName: String) {
        val file = File(cacheDir, fileName)
        if (file.exists()) {
            file.delete()
            Timber.d("Removed cached audio: $fileName")
        }
    }

    fun getCacheSize(): Long {
        return cacheDir.walkTopDown()
            .filter { it.isFile }
            .sumOf { it.length() }
    }

    fun clearCache() {
        cacheDir.listFiles()?.forEach { it.delete() }
        Timber.d("Audio cache cleared")
    }

    private fun evictIfNeeded(incomingSize: Long) {
        var currentSize = getCacheSize()
        if (currentSize + incomingSize <= MAX_CACHE_SIZE_BYTES) return

        // Sort by last modified (oldest first) for LRU eviction
        val files = cacheDir.listFiles()
            ?.sortedBy { it.lastModified() }
            ?: return

        for (file in files) {
            if (currentSize + incomingSize <= MAX_CACHE_SIZE_BYTES) break
            val fileSize = file.length()
            file.delete()
            currentSize -= fileSize
            Timber.d("Evicted cached audio: ${file.name} (${fileSize} bytes)")
        }
    }
}
