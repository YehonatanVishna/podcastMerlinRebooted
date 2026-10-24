package com.podcastmerlin.podcast_merlin_flutter

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    companion object {
        /** URI attached to the home widget's launch intent to request the Now Playing sheet. */
        const val NOW_PLAYING_URI = "podcastmerlin://now-playing"
    }

    private val networkChannel = "com.podcastmerlin.app/network"
    private val launchChannel = "com.podcastmerlin.app/launch"

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Keep getIntent() current so a widget tap while the activity is alive can be
        // consumed by Flutter on resume.
        setIntent(intent)
    }

    /**
     * Returns the widget launch URI (if this activity was opened from the home widget and the
     * request has not been consumed yet) and clears it so subsequent resumes don't re-trigger.
     */
    private fun consumeWidgetLaunch(): String? {
        val current = intent ?: return null
        if (current.action != HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION) return null
        val uri = current.data?.toString() ?: ""
        current.action = Intent.ACTION_MAIN
        current.data = null
        return uri
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, launchChannel).setMethodCallHandler { call, result ->
            if (call.method == "consumeWidgetLaunch") {
                result.success(consumeWidgetLaunch())
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, networkChannel).setMethodCallHandler { call, result ->
            if (call.method == "getNetworkInfo") {
                val context = applicationContext
                val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                val activeNetwork = connectivityManager?.activeNetwork
                val capabilities = connectivityManager?.getNetworkCapabilities(activeNetwork)

                val isWifi = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
                val isEthernet = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true
                val isCellular = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true
                val isConnected = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true

                var ssid: String? = null
                if (isWifi) {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val wifiInfo = capabilities?.transportInfo as? WifiInfo
                            ssid = wifiInfo?.ssid
                        }
                        if (ssid == null || ssid == "<unknown ssid>" || ssid == "0x") {
                            val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                            ssid = wifiManager?.connectionInfo?.ssid
                        }
                        if (ssid != null) {
                            var clean = ssid.trim()
                            if (clean.startsWith("\"") && clean.endsWith("\"")) {
                                clean = clean.substring(1, clean.length - 1)
                            }
                            if (clean == "<unknown ssid>" || clean == "0x" || clean.isEmpty()) {
                                ssid = null
                            } else {
                                ssid = clean
                            }
                        }
                    } catch (_: Exception) {
                        ssid = null
                    }
                }

                val map = hashMapOf(
                    "isConnected" to isConnected,
                    "isWifi" to isWifi,
                    "isEthernet" to isEthernet,
                    "isCellular" to isCellular,
                    "ssid" to ssid
                )
                result.success(map)
            } else {
                result.notImplemented()
            }
        }
    }
}
