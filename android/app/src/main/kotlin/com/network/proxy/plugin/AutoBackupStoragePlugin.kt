package com.network.proxy.plugin

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

class AutoBackupStoragePlugin : AndroidFlutterPlugin() {
    companion object {
        const val CHANNEL = "com.proxy/autoBackupStorage"
        private const val REQUEST_CODE_OPEN_TREE = 7231
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
                        result.success(false)
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
            result.success(null)
            return true
        }

        val uri = data?.data
        if (uri == null) {
            result.success(null)
            return true
        }

        val flags = data.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        activity.contentResolver.takePersistableUriPermission(uri, flags)
        result.success(uri.toString())
        return true
    }

    private fun selectDirectory(result: MethodChannel.Result) {
        if (pendingSelectResult != null) {
            result.error("busy", "Directory selection is already in progress", null)
            return
        }

        pendingSelectResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQUEST_CODE_OPEN_TREE)
    }

    private fun writeFiles(directoryUriValue: String, files: Map<String, String>): Boolean {
        return try {
            val directoryUri = Uri.parse(directoryUriValue)
            for ((name, content) in files) {
                overwriteFile(directoryUri, name, content)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun overwriteFile(directoryUri: Uri, name: String, content: String) {
        val resolver = activity.contentResolver
        val parentUri = DocumentsContract.buildDocumentUriUsingTree(
            directoryUri,
            DocumentsContract.getTreeDocumentId(directoryUri)
        )
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            directoryUri,
            DocumentsContract.getTreeDocumentId(directoryUri)
        )

        resolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            while (cursor.moveToNext()) {
                if (cursor.getString(nameIndex) == name) {
                    val oldUri = DocumentsContract.buildDocumentUriUsingTree(directoryUri, cursor.getString(idIndex))
                    DocumentsContract.deleteDocument(resolver, oldUri)
                    break
                }
            }
        }

        val fileUri = DocumentsContract.createDocument(resolver, parentUri, "application/octet-stream", name)
            ?: throw IllegalStateException("Failed to create $name")
        resolver.openOutputStream(fileUri, "wt")?.use { output ->
            output.write(content.toByteArray(Charsets.UTF_8))
        } ?: throw IllegalStateException("Failed to open $name")
    }
}
