package com.example.resqlink_mobile

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val SMS_CHANNEL = "com.resqlink.sms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sendSMS" -> {
                    val number = call.argument<String>("number") ?: "7996710095"
                    val message = call.argument<String>("message") ?: ""
                    try {
                        val intent = Intent(Intent.ACTION_SENDTO).apply {
                            data = Uri.parse("smsto:$number")
                            putExtra("sms_body", message)
                        }
                        startActivity(intent)
                        result.success("SMS_INTENT_LAUNCHED")
                    } catch (e: Exception) {
                        result.error("SMS_FAILED", "Could not open SMS client: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
