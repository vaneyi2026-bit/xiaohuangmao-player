package com.vaneyi.xhmplayer

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.os.ext.SdkExtensions
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * 小黄毛影音 —— 安卓原生能力：
 * 相册/文件选择、带进度的复制、缩略图与时长、字幕编码识别、
 * 本窗口亮度、系统媒体音量、音频焦点与耳机拔出、外部分享入口。
 */
class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioPool = Executors.newFixedThreadPool(2)
    private val probePool = Executors.newSingleThreadExecutor()
    private var events: EventChannel.EventSink? = null
    private val pendingShares = ArrayList<Map<String, Any?>>()
    private var pickResult: MethodChannel.Result? = null
    private val cancelled: MutableSet<String> = ConcurrentHashMap.newKeySet()
    private var focusRequest: AudioFocusRequest? = null
    private var audio: AudioManager? = null

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                emit(mapOf("type" to "noisy"))
            }
        }
    }

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) {
            emit(mapOf("type" to "focusLoss"))
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(noisyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(noisyReceiver, filter)
        }
        if (savedInstanceState == null) handleIntent(intent, false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent, true)
    }

    override fun onDestroy() {
        try { unregisterReceiver(noisyReceiver) } catch (_: Exception) {}
        abandonFocus()
        ioPool.shutdown()
        probePool.shutdown()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        EventChannel(messenger, "xhm/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) { events = sink }
            override fun onCancel(arguments: Any?) { events = null }
        })
        MethodChannel(messenger, "xhm/native").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "dirs" -> result.success(mapOf("files" to filesDir.absolutePath, "cache" to cacheDir.absolutePath))
                    "freeSpace" -> result.success(StatFs(filesDir.absolutePath).availableBytes)
                    "pickGallery" -> startPick(gallery = true, single = false, result = result)
                    "pickFiles" -> startPick(gallery = false, single = false, result = result)
                    "pickSubtitle" -> startPick(gallery = false, single = true, result = result)
                    "queryUri" -> result.success(queryUri(Uri.parse(call.argument<String>("uri")!!)))
                    "copyUri" -> copyUri(
                        call.argument<String>("taskId")!!,
                        call.argument<String>("uri")!!,
                        call.argument<String>("dest")!!,
                        result
                    )
                    "cancelCopy" -> {
                        cancelled.add(call.argument<String>("taskId")!!)
                        result.success(null)
                    }
                    "probe" -> probe(call.argument<String>("path")!!, call.argument<String>("thumb")!!, result)
                    "readText" -> readText(call.argument<String>("path")!!, call.argument<String>("encoding") ?: "auto", result)
                    "takeShared" -> {
                        result.success(ArrayList(pendingShares))
                        pendingShares.clear()
                    }
                    "getBrightness" -> result.success(currentBrightness())
                    "setBrightness" -> {
                        setWindowBrightness((call.argument<Double>("value") ?: -1.0).toFloat())
                        result.success(null)
                    }
                    "resetBrightness" -> {
                        setWindowBrightness(-1f)
                        result.success(null)
                    }
                    "getVolume" -> {
                        val am = audio!!
                        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
                        result.success(am.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max)
                    }
                    "setVolume" -> {
                        val am = audio!!
                        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        val v = call.argument<Double>("value") ?: 0.0
                        val idx = Math.round(v * max).toInt().coerceIn(0, max)
                        am.setStreamVolume(AudioManager.STREAM_MUSIC, idx, 0)
                        result.success(null)
                    }
                    "requestFocus" -> result.success(requestFocus())
                    "abandonFocus" -> {
                        abandonFocus()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("native", e.message ?: e.toString(), null)
            }
        }
    }

    private fun emit(m: Map<String, Any?>) {
        mainHandler.post { events?.success(m) }
    }

    // ---------------- 选择器 ----------------

    private val reqPick = 4101

    private fun photoPickerAvailable(): Boolean {
        if (Build.VERSION.SDK_INT >= 33) return true
        if (Build.VERSION.SDK_INT >= 30) {
            return SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2
        }
        return false
    }

    private fun startPick(gallery: Boolean, single: Boolean, result: MethodChannel.Result) {
        if (pickResult != null) {
            result.error("busy", "选择器已打开", null)
            return
        }
        val intent: Intent = if (gallery && photoPickerAvailable()) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "video/*"
                putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, 50)
            }
        } else {
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = if (gallery) "video/*" else "*/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, !single)
            }
        }
        pickResult = result
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, reqPick)
        } catch (e: Exception) {
            pickResult = null
            result.error("nopicker", e.message ?: "无法打开系统选择器", null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != reqPick) return
        val r = pickResult ?: return
        pickResult = null
        val uris = ArrayList<String>()
        if (resultCode == Activity.RESULT_OK && data != null) {
            val clip = data.clipData
            if (clip != null) {
                for (i in 0 until clip.itemCount) {
                    clip.getItemAt(i).uri?.let { uris.add(it.toString()) }
                }
            } else {
                data.data?.let { uris.add(it.toString()) }
            }
        }
        r.success(uris)
    }

    private fun queryUri(uri: Uri): Map<String, Any?> {
        var name: String? = null
        var size = -1L
        var dateTaken = 0L
        try {
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val ni = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (ni >= 0 && !c.isNull(ni)) name = c.getString(ni)
                    val si = c.getColumnIndex(OpenableColumns.SIZE)
                    if (si >= 0 && !c.isNull(si)) size = c.getLong(si)
                }
            }
        } catch (_: Exception) {}
        try {
            contentResolver.query(uri, arrayOf(MediaStore.MediaColumns.DATE_TAKEN), null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    val di = c.getColumnIndex(MediaStore.MediaColumns.DATE_TAKEN)
                    if (di >= 0 && !c.isNull(di)) dateTaken = c.getLong(di)
                }
            }
        } catch (_: Exception) {}
        if (uri.scheme == "file") {
            val f = File(uri.path ?: "")
            if (name == null) name = f.name
            if (size < 0 && f.exists()) size = f.length()
        }
        var mime: String? = null
        try { mime = contentResolver.getType(uri) } catch (_: Exception) {}
        return mapOf(
            "name" to (name ?: uri.lastPathSegment ?: "video"),
            "size" to size,
            "mime" to mime,
            "dateTaken" to dateTaken
        )
    }

    // ---------------- 复制 ----------------

    private fun copyUri(taskId: String, uriStr: String, dest: String, result: MethodChannel.Result) {
        cancelled.remove(taskId)
        ioPool.execute {
            val out = File(dest)
            try {
                out.parentFile?.mkdirs()
                val uri = Uri.parse(uriStr)
                var total = -1L
                try { total = (queryUri(uri)["size"] as? Long) ?: -1L } catch (_: Exception) {}
                val input = contentResolver.openInputStream(uri) ?: throw IOException("无法读取该文件")
                var copied = 0L
                var lastEmit = 0L
                input.use { ins ->
                    FileOutputStream(out).use { os ->
                        val buf = ByteArray(1 shl 20)
                        while (true) {
                            if (cancelled.contains(taskId)) throw InterruptedException("cancelled")
                            val n = ins.read(buf)
                            if (n < 0) break
                            os.write(buf, 0, n)
                            copied += n
                            if (copied - lastEmit >= (4L shl 20)) {
                                lastEmit = copied
                                if (StatFs(out.parent ?: filesDir.absolutePath).availableBytes < (50L shl 20)) {
                                    throw IOException("NO_SPACE")
                                }
                                emit(mapOf("type" to "progress", "taskId" to taskId, "copied" to copied, "total" to total))
                            }
                        }
                        os.fd.sync()
                    }
                }
                val done = copied
                mainHandler.post { result.success(done) }
            } catch (e: InterruptedException) {
                out.delete()
                mainHandler.post { result.error("cancelled", "已取消", null) }
            } catch (e: Exception) {
                out.delete()
                val msg = e.message ?: e.toString()
                mainHandler.post { result.error("copy", msg, null) }
            } finally {
                cancelled.remove(taskId)
            }
        }
    }

    // ---------------- 缩略图与时长 ----------------

    private fun probe(path: String, thumb: String, result: MethodChannel.Result) {
        probePool.execute {
            val map = HashMap<String, Any?>()
            val r = MediaMetadataRetriever()
            try {
                r.setDataSource(path)
                val dur = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                var w = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
                var h = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
                val rot = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
                if (rot == 90 || rot == 270) {
                    val t = w; w = h; h = t
                }
                val hasVideo = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
                map["duration"] = dur
                map["width"] = w
                map["height"] = h
                map["hasVideo"] = hasVideo
                map["thumb"] = false
                if (hasVideo) {
                    val at = if (dur > 0) minOf(dur * 1000L / 10L, 10_000_000L) else 1_000_000L
                    val bmp = r.getFrameAtTime(at, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                        ?: r.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    if (bmp != null) {
                        val target = 360
                        val scaled = if (bmp.width > target) {
                            val nh = maxOf(1, (bmp.height.toLong() * target / bmp.width).toInt())
                            Bitmap.createScaledBitmap(bmp, target, nh, true)
                        } else bmp
                        File(thumb).parentFile?.mkdirs()
                        FileOutputStream(thumb).use { scaled.compress(Bitmap.CompressFormat.JPEG, 82, it) }
                        map["thumb"] = true
                    }
                }
                map["ok"] = true
            } catch (e: Exception) {
                map["ok"] = false
                map["error"] = e.message ?: e.toString()
            } finally {
                try { r.release() } catch (_: Exception) {}
            }
            mainHandler.post { result.success(map) }
        }
    }

    // ---------------- 字幕编码 ----------------

    private fun readText(path: String, encoding: String, result: MethodChannel.Result) {
        ioPool.execute {
            try {
                val bytes = File(path).readBytes()
                val decoded = decodeText(bytes, encoding)
                mainHandler.post { result.success(mapOf("text" to decoded.first, "encoding" to decoded.second)) }
            } catch (e: Exception) {
                val msg = e.message ?: e.toString()
                mainHandler.post { result.error("read", msg, null) }
            }
        }
    }

    private fun decodeText(b: ByteArray, enc: String): Pair<String, String> {
        if (enc != "auto") {
            var s = String(b, Charset.forName(enc))
            if (s.startsWith("﻿")) s = s.substring(1)
            return Pair(s, enc)
        }
        if (b.size >= 3 && b[0] == 0xEF.toByte() && b[1] == 0xBB.toByte() && b[2] == 0xBF.toByte()) {
            return Pair(String(b, 3, b.size - 3, Charsets.UTF_8), "UTF-8")
        }
        if (b.size >= 2 && b[0] == 0xFF.toByte() && b[1] == 0xFE.toByte()) {
            return Pair(String(b, 2, b.size - 2, Charsets.UTF_16LE), "UTF-16LE")
        }
        if (b.size >= 2 && b[0] == 0xFE.toByte() && b[1] == 0xFF.toByte()) {
            return Pair(String(b, 2, b.size - 2, Charsets.UTF_16BE), "UTF-16BE")
        }
        try {
            val s = Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(b)).toString()
            return Pair(s, "UTF-8")
        } catch (_: CharacterCodingException) {
        }
        return Pair(String(b, Charset.forName("GB18030")), "GB18030")
    }

    // ---------------- 亮度、音量、音频焦点 ----------------

    private fun currentBrightness(): Double {
        val v = window.attributes.screenBrightness
        if (v >= 0f) return v.toDouble()
        return try {
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS) / 255.0
        } catch (_: Exception) {
            0.5
        }
    }

    private fun setWindowBrightness(v: Float) {
        val lp = window.attributes
        lp.screenBrightness = if (v < 0f) WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE else v.coerceIn(0.01f, 1f)
        window.attributes = lp
    }

    private fun requestFocus(): Boolean {
        val am = audio ?: return false
        val req = focusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
                    .build()
            )
            .setOnAudioFocusChangeListener(focusListener)
            .build()
            .also { focusRequest = it }
        return am.requestAudioFocus(req) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonFocus() {
        val am = audio ?: return
        focusRequest?.let { am.abandonAudioFocusRequest(it) }
    }

    // ---------------- 外部打开与分享 ----------------

    private fun handleIntent(intent: Intent?, live: Boolean) {
        if (intent == null) return
        val uris = ArrayList<String>()
        var text: String? = null
        when (intent.action) {
            Intent.ACTION_VIEW -> intent.data?.let { uris.add(it.toString()) }
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                val u = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (u != null) uris.add(u.toString()) else text = intent.getStringExtra(Intent.EXTRA_TEXT)
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                @Suppress("DEPRECATION")
                val list = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                list?.forEach { uris.add(it.toString()) }
            }
            else -> return
        }
        if (uris.isEmpty() && text == null) return
        val m = mapOf<String, Any?>("type" to "shared", "uris" to uris, "text" to text)
        if (live && events != null) emit(m) else pendingShares.add(m)
    }
}
