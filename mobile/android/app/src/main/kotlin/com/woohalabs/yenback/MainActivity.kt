package com.woohalabs.yenback

import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    // ML Kit's Japanese model is bundled in the APK: no download, no network.
    private val recognizer by lazy {
        TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "yenback/receipt_ocr")
            .setMethodCallHandler { call, result ->
                if (call.method != "recognize") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("BAD_IMAGE", "missing path", null)
                    return@setMethodCallHandler
                }
                val image = try {
                    // Reads EXIF rotation; boxes come back in the upright frame.
                    InputImage.fromFilePath(this, Uri.fromFile(File(path)))
                } catch (e: Exception) {
                    result.error("BAD_IMAGE", e.message, null)
                    return@setMethodCallHandler
                }
                val rotated = image.rotationDegrees == 90 || image.rotationDegrees == 270
                val w = (if (rotated) image.height else image.width).toDouble().coerceAtLeast(1.0)
                val h = (if (rotated) image.width else image.height).toDouble().coerceAtLeast(1.0)

                recognizer.process(image)
                    .addOnSuccessListener { text ->
                        val lines = text.textBlocks.flatMap { it.lines }.mapNotNull { line ->
                            val box = line.boundingBox ?: return@mapNotNull null
                            mapOf(
                                "text" to line.text,
                                "left" to box.left / w,
                                "top" to box.top / h,
                                "width" to box.width() / w,
                                "height" to box.height() / h,
                            )
                        }
                        result.success(lines)
                    }
                    .addOnFailureListener { e -> result.error("OCR_FAILED", e.message, null) }
            }
    }
}
