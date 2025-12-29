package uk.bw86.floaty

import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import com.ryanheise.audioservice.AudioServicePlugin
import uz.shs.better_player_plus.BetterPlayerPlugin

class MainActivity : FlutterFragmentActivity() {

    private var flutterEngine: FlutterEngine? = null

    /**
     * Provide the shared AudioService engine
     */
    override fun provideFlutterEngine(@NonNull context: Context): FlutterEngine {
        val engine = AudioServicePlugin.getFlutterEngine(context)
        flutterEngine = engine


        return engine
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Ensure engine exists before super.onCreate()
        if (flutterEngine == null) {
            flutterEngine = AudioServicePlugin.getFlutterEngine(this)
        }
        super.onCreate(savedInstanceState)
    }

    override fun getCachedEngineId(): String? {
        return AudioServicePlugin.getFlutterEngineId()
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        // Keep the shared engine alive even if the Activity is destroyed
        return false
    }

    /**
     * Picture-in-Picture mode callback.
     * Safe because pipCallbackHelper is lazy-initialized.
     */
    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
                BetterPlayerPlugin.onPictureInPictureModeChanged(isInPictureInPictureMode)
    }
}
