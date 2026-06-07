package com.example.lg_webos_wifi_remote

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

/**
 * Holds a Wi-Fi [WifiManager.MulticastLock] while the app is running.
 *
 * SSDP M-SEARCH replies usually arrive as unicast and work without this, but
 * some devices/ROMs drop multicast traffic unless a multicast lock is held.
 * Acquiring it makes discovery more reliable; it is released on destroy.
 */
class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val wifi = applicationContext
                .getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifi.createMulticastLock("lg_webos_wifi_remote.ssdp").apply {
                setReferenceCounted(true)
                acquire()
            }
        } catch (e: Exception) {
            // Non-fatal: discovery still works for unicast replies.
        }
    }

    override fun onDestroy() {
        try {
            multicastLock?.let { if (it.isHeld) it.release() }
        } catch (e: Exception) {
            // Ignore release failures.
        }
        multicastLock = null
        super.onDestroy()
    }
}
