package app.weeklylens.collect

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.TimeUnit

/** Runs the collector every few hours so the OS's short usage history never runs out. */
class CollectWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            Collector(applicationContext).run()
            Result.success()
        } catch (e: Exception) {
            // A permission revoked mid-run or a full disk: log it and let WorkManager try again.
            Log.w("WeeklyLens", "collect failed", e)
            Result.retry()
        }
    }

    companion object {
        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<CollectWorker>(2, TimeUnit.HOURS).build()
            WorkManager.getInstance(context)
                .enqueueUniquePeriodicWork("collect", ExistingPeriodicWorkPolicy.KEEP, request)
        }
    }
}

/**
 * ACTION_PACKAGE_FULLY_REMOVED is one of the few implicit broadcasts still delivered to
 * manifest receivers, and it gives the exact removal time the snapshot diff cannot.
 */
class PackageRemovedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_PACKAGE_FULLY_REMOVED) return
        val pkg = intent.data?.schemeSpecificPart ?: return
        val at = System.currentTimeMillis()
        val pending = goAsync() // keeps the receiver alive while the disk work runs off the main thread
        Thread {
            try {
                val db = ActivityDb.get(context)
                db.inventoryLabel(pkg)?.let { label ->
                    db.insertPackageChanges(listOf(PackageChange(pkg, label, PackageChange.Kind.REMOVED, at, exact = true)))
                }
            } finally {
                pending.finish()
            }
        }.start()
    }
}
