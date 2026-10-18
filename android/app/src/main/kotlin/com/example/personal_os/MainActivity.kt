package com.example.personal_os

import android.app.KeyguardManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.content.Intent
import android.util.Log
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.personal_os/lockscreen"
    private val TAG = "AlarmLaunchDebug"

    // Kept as a field (instead of a local val inside configureFlutterEngine)
    // so dispatchKeyEvent can reach it to forward volume-key presses to
    // Dart. configureFlutterEngine can in principle run more than once
    // across the activity's lifetime, so this always points at the most
    // recently attached engine's channel.
    private var methodChannel: MethodChannel? = null

    // Set by the `alarm` plugin (or fall back to checking action/extras below)
    // when it launches this activity for a ringing alarm. Applying the
    // show-when-locked / turn-screen-on flags here, natively, means they're
    // set BEFORE Flutter's engine spins up — on a cold start (app fully
    // killed), the old approach (setting these flags from Dart via the
    // MethodChannel) was too late: Android had already rendered the keyguard
    // by the time Flutter was ready to call back into native code.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (isAlarmRingIntent(intent)) {
            applyAlarmWindowFlags()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (isAlarmRingIntent(intent)) {
            applyAlarmWindowFlags()
        }
    }

    // Intercepts volume up/down while this activity is in the foreground
    // (i.e. while the alarm ring screen is showing) and forwards it to
    // Flutter instead of letting it change media volume. Returning true
    // "consumes" the event so the system volume UI never pops up.
    //
    // Deliberately NOT doing this for KEYCODE_POWER: that key is intercepted
    // by the system before it ever reaches an app's dispatchKeyEvent on
    // modern Android (this has been true since ~Android 5.0, for security /
    // screen-lock-bypass reasons), so there's no reliable way for a regular
    // app to hook power-button presses here. Only privileged/system-signed
    // apps get that behavior, and it's inconsistent even then across OEM
    // skins like MIUI. Skipping it rather than shipping something flaky.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN &&
            (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
             event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            methodChannel?.invokeMethod("volumeKeyPressed", null)
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    // IMPORTANT: this defaults to false on anything we don't recognize.
    // A previous version of this defaulted to true for a normal launch
    // (ACTION_MAIN), which — combined with the old manifest-level
    // showWhenLocked/turnScreenOn — is part of what caused the screen to
    // never time out normally while the app was open. Now that those
    // manifest flags are removed, this native check is the ONLY thing
    // deciding when the lock-screen-override behavior turns on, so it
    // needs to be precise rather than permissive.
    //
    // We don't yet know for certain what intent the `alarm` plugin (v5.2.1)
    // actually fires on a cold-start full-screen-intent launch. Logging it
    // here once will show us in `adb logcat -s AlarmLaunchDebug` (or
    // Android Studio's Logcat panel) exactly what action/extras arrive —
    // trigger a real alarm from a killed app state, check the log, and
    // send me the output so the check below can be tightened to match it
    // precisely instead of guessing.
    private fun isAlarmRingIntent(intent: Intent?): Boolean {
        if (intent == null) return false
        Log.d(TAG, "action=${intent.action} extras=${intent.extras?.keySet()?.joinToString()}")
        if (intent.getBooleanExtra("IS_ALARM_RING", false)) return true
        val action = intent.action ?: return false
        return action.contains("alarm", ignoreCase = true)
    }

    private fun applyAlarmWindowFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        val keyguardManager = getSystemService(KEYGUARD_SERVICE) as KeyguardManager
        keyguardManager.requestDismissKeyguard(this, null)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "moveTaskToBack" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                            setShowWhenLocked(false)
                            setTurnScreenOn(false)
                        } else {
                            @Suppress("DEPRECATION")
                            window.clearFlags(
                                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                            )
                        }
                        moveTaskToBack(true)
                        result.success(null)
                    }

                    "hasOverlayPermission" -> {
                        result.success(Settings.canDrawOverlays(this))
                    }

                    "requestOverlayPermission" -> {
                        if (!Settings.canDrawOverlays(this)) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            startActivity(intent)
                        }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}