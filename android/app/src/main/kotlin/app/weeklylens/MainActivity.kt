package app.weeklylens

import app.weeklylens.bridge.ActivityApi
import app.weeklylens.bridge.ActivityApiImpl
import app.weeklylens.collect.CollectWorker
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ActivityApi.setUp(flutterEngine.dartExecutor.binaryMessenger, ActivityApiImpl(applicationContext))
        CollectWorker.schedule(applicationContext)
    }
}
