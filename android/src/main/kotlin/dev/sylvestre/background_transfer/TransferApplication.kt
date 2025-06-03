package dev.sylvestre.background_transfer

import android.content.Context

interface QueueManagerProvider {
    val queueManager: TransferQueueManager
}

object QueueManagerHolder {
    private var instance: TransferQueueManager? = null
    
    @Synchronized
    fun getInstance(context: Context): TransferQueueManager {
        if (instance == null) {
            instance = TransferQueueManager(context.applicationContext)
        }
        return instance!!
    }
}
