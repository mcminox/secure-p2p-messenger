package com.example.secure_p2p_messenger

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Debug
import android.view.WindowManager
import java.io.File
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private var pendingLink: String? = null
    private var deepLinkChannel: MethodChannel? = null
    private var securityChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        pendingLink = intent?.dataString
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        deepLinkChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "spm/deeplink",
        ).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialLink" -> {
                        result.success(pendingLink)
                        pendingLink = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        securityChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "spm/security",
        ).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSecuritySignals" -> {
                        result.success(
                            mapOf(
                                "debuggerAttached" to Debug.isDebuggerConnected(),
                                "rootDetected" to isRootDetected(),
                                "emulatorDetected" to isEmulator(),
                                "hookDetected" to isHookDetected(),
                            ),
                        )
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = intent.dataString ?: return
        if (deepLinkChannel == null) {
            pendingLink = link
            return
        }
        deepLinkChannel?.invokeMethod("onLink", link)
    }

    private fun isEmulator(): Boolean {
        return Build.FINGERPRINT.contains("generic") ||
            Build.MODEL.contains("Emulator") ||
            Build.MANUFACTURER.contains("Genymotion") ||
            Build.BRAND.startsWith("generic") ||
            Build.PRODUCT.contains("sdk")
    }

    private fun isRootDetected(): Boolean {
        val tags = Build.TAGS ?: ""
        if (tags.contains("test-keys")) return true
        val paths = arrayOf(
            "/system/xbin/su",
            "/system/bin/su",
            "/sbin/su",
            "/system/app/Superuser.apk",
            "/system/bin/.ext/su",
        )
        return paths.any { File(it).exists() }
    }

    private fun isHookDetected(): Boolean {
        val maps = try {
            File("/proc/self/maps").readText()
        } catch (_: Exception) {
            ""
        }
        val suspicious = arrayOf("frida", "xposed", "substrate", "magisk")
        return suspicious.any { maps.contains(it, ignoreCase = true) }
    }
}
