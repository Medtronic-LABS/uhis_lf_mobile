package com.medtroniclabs.uhis_next

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
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
        super.onCreate(savedInstanceState)
        // Must run after super.onCreate() — the theme (and its NoActionBar /
        // transparent-background attributes) is only resolved onto the window
        // once the framework's own onCreate has run. Calling this before
        // super.onCreate() forces an early DecorView inflation against the
        // window's pre-theme defaults, which surfaced a stray native
        // ActionBar (visible as a solid bar showing the app label) — most
        // visible in dark mode.
        enableEdgeToEdge()
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
