package com.medtroniclabs.uhis_next

import android.os.Bundle
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener

class MainActivity : FlutterFragmentActivity() {
    // installSplashScreen()'s default dismiss condition fires as soon as the
    // FlutterView's first (empty) draw pass happens — well before the engine
    // has actually rendered a real frame. In debug builds the slower
    // engine/isolate startup masks this; in AOT-compiled release builds it's
    // fast enough that the native splash disappears before anything has been
    // painted, so the app appears to skip straight to the in-app splash.
    // Hold it on screen until Flutter reports its first real UI frame.
    private var flutterUiDisplayed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        val splashScreen = installSplashScreen()
        splashScreen.setKeepOnScreenCondition { !flutterUiDisplayed }
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.renderer.addIsDisplayingFlutterUiListener(object : FlutterUiDisplayListener {
            override fun onFlutterUiDisplayed() {
                flutterUiDisplayed = true
            }
            override fun onFlutterUiNoLongerDisplayed() {}
        })
    }
}
