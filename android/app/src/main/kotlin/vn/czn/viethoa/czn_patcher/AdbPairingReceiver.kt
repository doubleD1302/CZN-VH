package vn.czn.viethoa.czn_patcher

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.RemoteInput

class AdbPairingReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.d("CZN_PAIR", "AdbPairingReceiver nhận action: $action")
        if (action == AdbNotificationPairer.ACTION_PAIR) {
            val results = RemoteInput.getResultsFromIntent(intent)
            val code = results?.getCharSequence(AdbNotificationPairer.KEY_PAIRING_INPUT)?.toString()
            if (!code.isNullOrBlank()) {
                AdbNotificationPairer.handlePairingInput(context.applicationContext, code)
            } else {
                Log.w("CZN_PAIR", "Không tìm thấy nội dung input trong intent RemoteInput")
            }
        } else if (action == AdbNotificationPairer.ACTION_CANCEL) {
            AdbNotificationPairer.stop(context.applicationContext)
        }
    }
}
