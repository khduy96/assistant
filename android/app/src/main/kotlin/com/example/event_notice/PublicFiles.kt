package com.example.event_notice

import android.app.DownloadManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import java.io.File

/**
 * Đưa tệp nhận được ra thư mục Download công cộng, và mở lại nó.
 *
 * Tệp app tự ghi nằm trong `Android/data/<gói>/files`, mà từ Android 11 Google
 * đã chặn đường đó khỏi app Files lẫn hộp thoại chọn tệp — người dùng gần như
 * không lấy ra được. MediaStore là lối ra duy nhất không phải xin quyền bộ nhớ.
 */
object PublicFiles {
  /** MediaStore chỉ ghi được vào Download công cộng từ Android 10 trở lên. */
  val isSupported: Boolean
    get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

  /**
   * Chép [sourcePath] vào `Download/[subDir]` rồi xoá bản tạm.
   *
   * Trả về uri nội dung và đường dẫn để hiển thị, hoặc null nếu không làm được
   * (máy quá cũ, hoặc tệp nguồn đã biến mất).
   */
  fun saveToDownloads(
    context: Context,
    sourcePath: String,
    subDir: String
  ): Map<String, String>? {
    if (!isSupported) return null
    val source = File(sourcePath)
    if (!source.exists()) return null

    val name = source.name
    val values = ContentValues().apply {
      put(MediaStore.MediaColumns.DISPLAY_NAME, name)
      put(MediaStore.MediaColumns.MIME_TYPE, mimeOf(name))
      put(
        MediaStore.MediaColumns.RELATIVE_PATH,
        Environment.DIRECTORY_DOWNLOADS + File.separator + subDir
      )
      // Ẩn khỏi các app khác cho tới khi chép xong, kẻo có app đọc phải tệp dở.
      put(MediaStore.MediaColumns.IS_PENDING, 1)
    }

    val resolver = context.contentResolver
    val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
      ?: return null

    try {
      resolver.openOutputStream(uri)?.use { out ->
        source.inputStream().use { it.copyTo(out) }
      } ?: run {
        resolver.delete(uri, null, null)
        return null
      }
    } catch (e: Exception) {
      runCatching { resolver.delete(uri, null, null) }
      return null
    }

    resolver.update(
      uri,
      ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
      null,
      null
    )
    // Bản tạm trong thư mục riêng của app không còn việc gì nữa.
    runCatching { source.delete() }

    // MediaStore tự đổi tên khi trùng, nên hỏi lại tên thật nó đã đặt.
    val saved = displayNameOf(context, uri) ?: name
    return mapOf(
      "uri" to uri.toString(),
      "path" to "Download/$subDir/$saved",
      "name" to saved
    )
  }

  /** Mở tệp bằng app mặc định của máy. */
  fun openFile(context: Context, uriString: String, name: String): Boolean {
    val uri = runCatching { Uri.parse(uriString) }.getOrNull() ?: return false
    val intent = Intent(Intent.ACTION_VIEW).apply {
      setDataAndType(uri, mimeOf(name))
      addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    return runCatching { context.startActivity(intent) }.isSuccess
  }

  /**
   * Mở màn hình Tải xuống của hệ thống.
   *
   * Android không có cách nào mở đúng một thư mục cho mọi máy, nhưng màn hình
   * Tải xuống thì máy nào cũng có và tệp của ta nằm ngay trong đó.
   */
  fun openDownloads(context: Context): Boolean {
    val intent = Intent(DownloadManager.ACTION_VIEW_DOWNLOADS)
      .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    return runCatching { context.startActivity(intent) }.isSuccess
  }

  private fun displayNameOf(context: Context, uri: Uri): String? {
    val columns = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME)
    return runCatching {
      context.contentResolver.query(uri, columns, null, null, null)?.use { cursor ->
        if (cursor.moveToFirst()) cursor.getString(0) else null
      }
    }.getOrNull()
  }

  private fun mimeOf(name: String): String {
    val ext = name.substringAfterLast('.', "").lowercase()
    if (ext.isEmpty()) return "application/octet-stream"
    return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext)
      ?: "application/octet-stream"
  }
}
