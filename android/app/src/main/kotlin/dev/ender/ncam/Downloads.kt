package dev.ender.ncam

import android.content.Context
import android.content.Intent
import java.util.concurrent.CopyOnWriteArraySet

/**
 * The download queue. One file at a time: the camera's Wi-Fi link is the bottleneck, and
 * two parallel downloads measured no faster than one.
 *
 * Process-wide; the work itself runs in [DownloadService].
 */
object Downloads {
    const val QUEUED = "queued"
    const val RUNNING = "running"
    const val WAITING = "waiting" // between retries
    const val DONE = "done"
    const val FAILED = "failed"
    const val CANCELLED = "cancelled"

    class Job(val id: String, val url: String, val name: String, @Volatile var total: Long) {
        @Volatile var received: Long = 0
        @Volatile var state: String = QUEUED
        @Volatile var error: String? = null
        @Volatile var bytesPerSecond: Long = 0
        @Volatile var cancelRequested: Boolean = false

        val active get() = state == QUEUED || state == RUNNING || state == WAITING

        fun toMap(): Map<String, Any?> = mapOf(
            "id" to id, "url" to url, "name" to name, "total" to total, "received" to received,
            "state" to state, "error" to error, "bytesPerSecond" to bytesPerSecond,
        )
    }

    private val lock = Any()
    private val jobs = LinkedHashMap<String, Job>()
    private val listeners = CopyOnWriteArraySet<() -> Unit>()
    private var nextId = 1L

    /** Called by the service when a job needs to be interrupted. */
    @Volatile var onCancel: ((Job) -> Unit)? = null

    fun addListener(l: () -> Unit) = listeners.add(l)
    fun removeListener(l: () -> Unit) = listeners.remove(l)
    fun changed() = listeners.forEach { it() }

    fun snapshot(): List<Map<String, Any?>> = synchronized(lock) { jobs.values.map { it.toMap() } }

    fun activeCount(): Int = synchronized(lock) { jobs.values.count { it.active } }
    fun doneCount(): Int = synchronized(lock) { jobs.values.count { it.state == DONE } }
    fun totalCount(): Int = synchronized(lock) { jobs.size }

    /** Adds files to the queue, skipping names that are already queued or running. */
    fun enqueue(context: Context, items: List<Map<String, Any?>>) {
        var added = false
        synchronized(lock) {
            for (item in items) {
                val name = item["name"] as? String ?: continue
                val url = item["url"] as? String ?: continue
                val total = (item["total"] as? Number)?.toLong() ?: 0L
                if (jobs.values.any { it.name == name && it.active }) continue
                // A finished or failed entry for the same file is replaced.
                jobs.values.removeAll { it.name == name }
                val id = (nextId++).toString()
                jobs[id] = Job(id, url, name, total)
                added = true
            }
        }
        if (added) {
            changed()
            startService(context)
        }
    }

    fun retry(context: Context, id: String) {
        synchronized(lock) {
            val job = jobs[id] ?: return
            if (job.active || job.state == DONE) return
            job.cancelRequested = false
            job.error = null
            job.state = QUEUED
        }
        changed()
        startService(context)
    }

    /** Cancels one job, or every active job when [id] is null. Partial data is discarded. */
    fun cancel(id: String?) {
        val hit = synchronized(lock) {
            jobs.values.filter { (id == null || it.id == id) && it.active }.onEach {
                it.cancelRequested = true
                if (it.state == QUEUED) it.state = CANCELLED
            }
        }
        hit.forEach { onCancel?.invoke(it) }
        changed()
    }

    fun clearFinished() {
        synchronized(lock) { jobs.values.removeAll { !it.active } }
        changed()
    }

    fun nextQueued(): Job? = synchronized(lock) {
        jobs.values.firstOrNull { it.state == QUEUED }?.also { it.state = RUNNING }
    }

    private fun startService(context: Context) {
        val app = context.applicationContext
        app.startForegroundService(Intent(app, DownloadService::class.java))
    }
}
