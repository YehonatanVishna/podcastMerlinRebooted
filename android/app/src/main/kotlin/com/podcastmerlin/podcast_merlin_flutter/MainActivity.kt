package com.podcastmerlin.podcast_merlin_flutter

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private val networkChannel = "com.podcastmerlin.app/network"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
