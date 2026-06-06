package com.secure2share.app

import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SHARE_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareFile" -> {
                    try {
                        val args = call.arguments as? Map<*, *>
                        shareFile(args)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("SHARE_FAILED", error.message, null)
                    }
                }
                "shareText" -> {
                    try {
                        val args = call.arguments as? Map<*, *>
                        shareText(args)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("SHARE_FAILED", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun shareText(args: Map<*, *>?) {
        val text = args?.get("text") as? String
            ?: throw IllegalArgumentException("Share text is missing.")
        val subject = args["subject"] as? String ?: "Digital Wallet"

        val installedPackages = shareTargetPackages.filter(::isPackageInstalled)
        if (installedPackages.isEmpty()) {
            throw IllegalStateException("WhatsApp or Telegram is not installed.")
        }

        val sendIntents = installedPackages.map { packageName ->
            Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                setPackage(packageName)
                putExtra(Intent.EXTRA_TEXT, text)
                putExtra(Intent.EXTRA_SUBJECT, subject)
            }
        }

        val intent = if (sendIntents.size == 1) {
            sendIntents.first()
        } else {
            Intent.createChooser(sendIntents.first(), "Share with").apply {
                putExtra(Intent.EXTRA_INITIAL_INTENTS, sendIntents.drop(1).toTypedArray())
            }
        }

        startActivity(intent)
    }

    private fun shareFile(args: Map<*, *>?) {
        val path = args?.get("path") as? String
            ?: throw IllegalArgumentException("File path is missing.")
        val mimeType = args["mimeType"] as? String ?: "*/*"
        val requestedName = args["name"] as? String ?: File(path).name
        val source = File(path)

        if (!source.exists()) {
            throw IllegalArgumentException("File does not exist.")
        }

        val installedPackages = shareTargetPackages.filter(::isPackageInstalled)
        if (installedPackages.isEmpty()) {
            throw IllegalStateException("WhatsApp or Telegram is not installed.")
        }

        val shareFile = copyIntoShareCache(source, requestedName)
        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            shareFile
        )

        val sendIntents = installedPackages.map { packageName ->
            grantUriPermission(packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                setPackage(packageName)
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, requestedName)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }

        val intent = if (sendIntents.size == 1) {
            sendIntents.first()
        } else {
            Intent.createChooser(sendIntents.first(), "Share with").apply {
                putExtra(Intent.EXTRA_INITIAL_INTENTS, sendIntents.drop(1).toTypedArray())
            }
        }

        startActivity(intent)
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun copyIntoShareCache(source: File, requestedName: String): File {
        val shareDirectory = File(cacheDir, "share")
        shareDirectory.mkdirs()
        shareDirectory.listFiles()?.forEach { it.delete() }

        val safeName = requestedName
            .replace(Regex("""[\\/:*?"<>|]"""), "_")
            .ifBlank { "drive2share-file" }
        val destination = File(shareDirectory, safeName)
        source.copyTo(destination, overwrite = true)
        return destination
    }

    companion object {
        private const val SHARE_CHANNEL = "drive2share/share_targets"

        private val shareTargetPackages = listOf(
            "com.whatsapp",
            "com.whatsapp.w4b",
            "org.telegram.messenger",
            "org.thunderdog.challegram"
        )
    }
}
