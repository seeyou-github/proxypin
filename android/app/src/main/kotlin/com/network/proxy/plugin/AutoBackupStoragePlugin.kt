package com.network.proxy.plugin

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

class AutoBackupStoragePlugin : AndroidFlutterPlugin() {
    companion object {
        const val CHANNEL = "com.proxy/autoBackupStorage"
        private const val REQUEST_CODE_OPEN_TREE = 7231
        private const val TAG = "AutoBackupStorage"
    }

    private var channel: MethodChannel? = null
    private var pendingSelectResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "selectDirectory" -> selectDirectory(result)
                "writeFiles" -> {
                    val directoryUri = call.argument<String>("directoryUri")
                    val files = call.argument<Map<String, String>>("files")
                    if (directoryUri.isNullOrBlank() || files == null) {
                        result.success(mapOf("success" to false, "logs" to listOf("Missing directoryUri or files")))
                        return@setMethodCallHandler
                    }
                    result.success(writeFiles(directoryUri, files))
                }
                else -> result.notImplemented()
            }
        }
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE_OPEN_TREE) {
            return false
        }

        val result = pendingSelectResult ?: return true
        pendingSelectResult = null

        if (resultCode != Activity.RESULT_OK) {
            Log.i(TAG, "Directory selection cancelled, resultCode=$resultCode")
            result.success(
                mapOf(
                    "success" to false,
                    "cancelled" to true,
                    "resultCode" to resultCode,
                    "logs" to listOf("Directory selection cancelled resultCode=$resultCode")
                )
            )
            return true
        }

        val uri = data?.data
        if (uri == null) {
            Log.w(TAG, "Directory selection returned OK but data uri is null")
            result.success(
                mapOf(
                    "success" to false,
                    "cancelled" to false,
                    "resultCode" to resultCode,
                    "rawFlags" to (data?.flags ?: 0),
                    "logs" to listOf("Directory selection returned OK but data uri is null")
                )
            )
            return true
        }

        val flags = data.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        Log.i(TAG, "Directory selected: $uri flags=$flags rawFlags=${data.flags}")
        activity.contentResolver.takePersistableUriPermission(uri, flags)
        result.success(
            mapOf(
                "success" to true,
                "cancelled" to false,
                "uri" to uri.toString(),
                "flags" to flags,
                "rawFlags" to data.flags,
                "logs" to listOf("Directory selected uri=$uri flags=$flags rawFlags=${data.flags}")
            )
        )
        return true
    }

    private fun selectDirectory(result: MethodChannel.Result) {
        if (pendingSelectResult != null) {
            result.error("busy", "Directory selection is already in progress", null)
            return
        }

        pendingSelectResult = result
        Log.i(TAG, "Starting ACTION_OPEN_DOCUMENT_TREE")
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQUEST_CODE_OPEN_TREE)
    }

    private fun writeFiles(directoryUriValue: String, files: Map<String, String>): Map<String, Any?> {
        val logs = mutableListOf<String>()
        return try {
            logs.add("writeFiles started directoryUri=$directoryUriValue fileCount=${files.size}")
            val directoryUri = Uri.parse(directoryUriValue)
            for ((name, content) in files) {
                overwriteFile(directoryUri, name, content, logs)
            }
            logs.add("writeFiles succeeded")
            mapOf("success" to true, "logs" to logs)
        } catch (e: Exception) {
            logs.add("writeFiles failed: ${e.javaClass.name}: ${e.message}")
            logs.add(Log.getStackTraceString(e))
            Log.e(TAG, "writeFiles failed", e)
            mapOf("success" to false, "logs" to logs)
        }
    }

    private fun overwriteFile(directoryUri: Uri, name: String, content: String, logs: MutableList<String>) {
        val resolver = activity.contentResolver
        val parentUri = DocumentsContract.buildDocumentUriUsingTree(
            directoryUri,
            DocumentsContract.getTreeDocumentId(directoryUri)
        )
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            directoryUri,
            DocumentsContract.getTreeDocumentId(directoryUri)
        )

        logs.add("overwriteFile started name=$name bytes=${content.toByteArray(Charsets.UTF_8).size}")
        logs.add("parentUri=$parentUri childrenUri=$childrenUri")
        var deletedOldFile = false
        resolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            logs.add("query children count=${cursor.count}")
            val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            while (cursor.moveToNext()) {
                if (cursor.getString(nameIndex) == name) {
                    val oldUri = DocumentsContract.buildDocumentUriUsingTree(directoryUri, cursor.getString(idIndex))
                    DocumentsContract.deleteDocument(resolver, oldUri)
                    deletedOldFile = true
                    logs.add("deleted old file name=$name uri=$oldUri")
                    break
                }
            }
        } ?: logs.add("query children returned null cursor")

        val fileUri = DocumentsContract.createDocument(resolver, parentUri, "application/octet-stream", name)
            ?: throw IllegalStateException("Failed to create $name")
        logs.add("created file name=$name uri=$fileUri deletedOldFile=$deletedOldFile")
        resolver.openOutputStream(fileUri, "wt")?.use { output ->
            output.write(content.toByteArray(Charsets.UTF_8))
        } ?: throw IllegalStateException("Failed to open $name")
        logs.add("overwriteFile finished name=$name uri=$fileUri")
    }
}
