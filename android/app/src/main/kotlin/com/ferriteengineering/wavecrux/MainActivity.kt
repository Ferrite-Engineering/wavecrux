package com.ferriteengineering.wavecrux

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import one.mixin.desktop.drop.DesktopDropPlugin
import java.io.File

/**
 * Main activity.  Handles `ACTION_VIEW` intents so that WaveCrux appears in
 * the system share sheet and "Open With" menu for `.vcd`, `.fst`, `.ghw`, and
 * `.wavecrux` files.
 *
 * Platform channels (registered in [configureFlutterEngine]):
 *   • `com.wavecrux/incoming_file` (MethodChannel)
 *       - `getInitialFile()` → String? — path of a cold-start file
 *   • `com.wavecrux/incoming_file_stream` (EventChannel)
 *       - emits String — path of each file opened while the app is running
 *
 * Content-URI handling: Android email, cloud-storage, and Downloads apps
 * typically deliver files via `content://` URIs, which are opaque references
 * that can only be read through the [ContentResolver].  Because the Rust wellen
 * FFI layer requires a real filesystem path, content URIs are copied to
 * `files/incoming/<filename>` inside the app's private internal storage before
 * the path is forwarded to Dart.
 */
class MainActivity : FlutterActivity() {

    /** Path of a file received before Flutter engine is ready (cold start). */
    private var pendingFilePath: String? = null

    /** `true` once Flutter has called `getInitialFile()` at least once. */
    private var isFlutterReady = false

    /** Non-null while Flutter is subscribed to the event channel. */
    private var incomingFileEventSink: EventChannel.EventSink? = null

    companion object {
        private const val METHOD_CHANNEL = "com.wavecrux/incoming_file"
        private const val EVENT_CHANNEL  = "com.wavecrux/incoming_file_stream"
        /** Subdirectory inside filesDir for copies of content-URI files. */
        private const val INCOMING_DIR   = "incoming"
    }

    // -------------------------------------------------------------------------
    // FlutterActivity overrides
    // -------------------------------------------------------------------------

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // `desktop_drop` makes the desktop window a file drop target. It also
        // ships an Android implementation, which claims every system drag on
        // the activity's content view and would make this app a drop target
        // that does nothing. WaveCrux accepts drops on desktop only, so the
        // plugin is unregistered here, which detaches that drag listener.
        flutterEngine.plugins.remove(DesktopDropPlugin::class.java)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialFile" -> {
                        isFlutterReady = true
                        result.success(pendingFilePath)
                        pendingFilePath = null
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    incomingFileEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    incomingFileEventSink = null
                }
            })
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        processIncomingIntent(intent)
    }

    /** Called when the app is already running and a new ACTION_VIEW intent arrives. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        processIncomingIntent(intent)
    }

    // -------------------------------------------------------------------------
    // Intent processing
    // -------------------------------------------------------------------------

    private fun processIncomingIntent(intent: Intent) {
        if (intent.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        val path = resolveFilePath(uri) ?: return

        val sink = incomingFileEventSink
        if (isFlutterReady && sink != null) {
            // Flutter is running — deliver immediately via the event stream.
            sink.success(path)
        } else {
            // Flutter not yet ready — store for getInitialFile().
            pendingFilePath = path
        }
    }

    // -------------------------------------------------------------------------
    // URI resolution
    // -------------------------------------------------------------------------

    private fun resolveFilePath(uri: Uri): String? = when (uri.scheme) {
        "file"    -> uri.path
        "content" -> copyContentUriToStorage(uri)
        else      -> null
    }

    /**
     * Copies the content at [uri] into `files/incoming/<displayName>` and
     * returns the absolute path, or `null` on failure.
     *
     * Using [filesDir] (internal storage) ensures the copy persists across
     * launches so recent-files entries remain openable after the original
     * content URI permission expires.
     */
    private fun copyContentUriToStorage(uri: Uri): String? {
        return try {
            val fileName = getDisplayName(uri)
                ?: uri.lastPathSegment
                ?: "waveform_file"

            val incomingDir = File(filesDir, INCOMING_DIR)
            incomingDir.mkdirs()
            val destFile = File(incomingDir, fileName)

            contentResolver.openInputStream(uri)?.use { input ->
                destFile.outputStream().use { output -> input.copyTo(output) }
            }
            destFile.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    /** Returns the display name of a content URI, or `null` if unavailable. */
    private fun getDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (!cursor.moveToFirst()) return null
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx < 0) null else cursor.getString(idx)
            }
        } catch (_: Exception) {
            null
        }
    }
}
