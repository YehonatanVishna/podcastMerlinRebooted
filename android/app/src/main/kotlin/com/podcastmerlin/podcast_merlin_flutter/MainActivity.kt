package com.podcastmerlin.podcast_merlin_flutter

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
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

    @Volatile
    private var currentWifiSsid: String? = null
    private var wifiNetworkCallback: ConnectivityManager.NetworkCallback? = null
    private val mainHandler = Handler(Looper.getMainLooper())

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

    private fun cleanSsid(raw: String?): String? {
        if (raw == null) return null
        var s = raw.trim()
        if (s.startsWith("\"") && s.endsWith("\"") && s.length >= 2) {
            s = s.substring(1, s.length - 1).trim()
        }
        if (s.isEmpty() || s == "<unknown ssid>" || s == "0x") {
            return null
        }
        return s
    }

    private fun hasWifiOrLocationPermission(): Boolean {
        val fineLocation = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val coarseLocation = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        val nearbyWifi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.NEARBY_WIFI_DEVICES
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            false
        }
        return fineLocation || coarseLocation || nearbyWifi
    }

    private fun updateSsidFromCapabilities(capabilities: NetworkCapabilities?) {
        if (capabilities == null) return
        var ssid: String? = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val wifiInfo = capabilities.transportInfo as? WifiInfo
            ssid = wifiInfo?.ssid
        }
        if (ssid == null || ssid == "<unknown ssid>" || ssid == "0x") {
            try {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                ssid = wifiManager?.connectionInfo?.ssid
            } catch (_: Exception) {}
        }
        val clean = cleanSsid(ssid)
        if (clean != null) {
            currentWifiSsid = clean
        }
    }

    @Synchronized
    private fun registerWifiCallbackIfNeeded() {
        if (wifiNetworkCallback != null) return
        val connectivityManager = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return

        // On Android 12+ (API 31+), registering with FLAG_INCLUDE_LOCATION_INFO requires permissions
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !hasWifiOrLocationPermission()) {
            return
        }

        try {
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .build()

            val callback = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                object : ConnectivityManager.NetworkCallback(FLAG_INCLUDE_LOCATION_INFO) {
                    override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                        super.onCapabilitiesChanged(network, networkCapabilities)
                        updateSsidFromCapabilities(networkCapabilities)
                    }

                    override fun onLost(network: Network) {
                        super.onLost(network)
                        currentWifiSsid = null
                    }
                }
            } else {
                object : ConnectivityManager.NetworkCallback() {
                    override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                        super.onCapabilitiesChanged(network, networkCapabilities)
                        updateSsidFromCapabilities(networkCapabilities)
                    }

                    override fun onLost(network: Network) {
                        super.onLost(network)
                        currentWifiSsid = null
                    }
                }
            }

            connectivityManager.registerNetworkCallback(request, callback)
            wifiNetworkCallback = callback
        } catch (_: Exception) {
            // Permission or system limitation fallback
        }
    }

    @Synchronized
    private fun unregisterWifiCallback() {
        val callback = wifiNetworkCallback ?: return
        try {
            val connectivityManager = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            connectivityManager?.unregisterNetworkCallback(callback)
        } catch (_: Exception) {
        } finally {
            wifiNetworkCallback = null
        }
    }

    override fun onResume() {
        super.onResume()
        registerWifiCallbackIfNeeded()
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterWifiCallback()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerWifiCallbackIfNeeded()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, launchChannel).setMethodCallHandler { call, result ->
            if (call.method == "consumeWidgetLaunch") {
                result.success(consumeWidgetLaunch())
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, networkChannel).setMethodCallHandler { call, result ->
            if (call.method == "getNetworkInfo") {
                registerWifiCallbackIfNeeded()

                val context = applicationContext
                val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                val activeNetwork = connectivityManager?.activeNetwork
                val capabilities = connectivityManager?.getNetworkCapabilities(activeNetwork)

                val isWifi = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
                val isEthernet = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) == true
                val isCellular = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true
                val isConnected = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true

                var ssid: String? = currentWifiSsid
                if (ssid == null && isWifi) {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val wifiInfo = capabilities?.transportInfo as? WifiInfo
                            ssid = cleanSsid(wifiInfo?.ssid)
                        }
                        if (ssid == null) {
                            val wifiManager = context.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                            ssid = cleanSsid(wifiManager?.connectionInfo?.ssid)
                        }
                    } catch (_: Exception) {
                        ssid = null
                    }
                    if (ssid != null) {
                        currentWifiSsid = ssid
                    }
                }

                fun reply(finalSsid: String?) {
                    val map = hashMapOf(
                        "isConnected" to isConnected,
                        "isWifi" to isWifi,
                        "isEthernet" to isEthernet,
                        "isCellular" to isCellular,
                        "ssid" to finalSsid
                    )
                    result.success(map)
                }

                if (isWifi && ssid == null && hasWifiOrLocationPermission()) {
                    // If callback was just registered, allow onCapabilitiesChanged up to 400ms to deliver unredacted SSID
                    var elapsed = 0
                    val interval = 50L
                    val maxWait = 400L
                    val pollRunnable = object : Runnable {
                        override fun run() {
                            val current = currentWifiSsid
                            if (current != null || elapsed >= maxWait) {
                                reply(current)
                            } else {
                                elapsed += interval.toInt()
                                mainHandler.postDelayed(this, interval)
                            }
                        }
                    }
                    mainHandler.postDelayed(pollRunnable, interval)
                } else {
                    reply(ssid)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
