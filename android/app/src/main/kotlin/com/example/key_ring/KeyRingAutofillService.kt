package com.example.key_ring

import android.app.assist.AssistStructure
import android.content.Context
import android.database.Cursor
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillContext
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.view.View
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import android.database.sqlite.SQLiteDatabase

/**
 * KeyRing 系统自动填充服务（Android 8.0+）。
 *
 * 用户在「系统设置 > 密码和自动填充」选择 KeyRing 后，任意应用的
 * 登录表单都会触发 onFillRequest：识别用户名/密码输入框，从 KeyRing
 * 本地数据库只读查询条目并返回候选 Dataset。
 *
 * 数据源：直接只读打开 app_flutter/KeyRing.db（与 Flutter 侧
 * path_provider 的 getApplicationDocumentsDirectory 同一位置）。
 * 注意：KeyRing 当前未对 DB 加密；若未来加密，此处需要解锁桥。
 */
class KeyRingAutofillService : AutofillService() {

    private data class FieldIds(
        val username: AutofillId?,
        val password: AutofillId?,
    )

    private data class Entry(
        val id: String,
        val title: String,
        val username: String,
        val password: String,
    )

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        val fields = findFields(request.fillContexts) ?: run {
            callback.onSuccess(null)
            return
        }
        if (fields.username == null && fields.password == null) {
            callback.onSuccess(null)
            return
        }

        val entries = queryEntries(cancellationSignal)
        if (entries.isEmpty()) {
            callback.onSuccess(null)
            return
        }

        val builder = FillResponse.Builder()
        // 上限 12 条，避免候选面板过长。
        for (e in entries.take(12)) {
            val presentation = RemoteViews(packageName, android.R.layout.simple_list_item_1).apply {
                setTextViewText(android.R.id.text1, "${e.title}（${e.username}）")
            }
            val dataset = Dataset.Builder()
            fields.username?.let {
                dataset.setValue(it, AutofillValue.forText(e.username), presentation)
            }
            fields.password?.let {
                dataset.setValue(it, AutofillValue.forText(e.password), presentation)
            }
            builder.addDataset(dataset.build())
        }
        callback.onSuccess(builder.build())
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // 保存新条目需要解锁态交互，引导用户回主应用操作。
        callback.onSuccess()
    }

    /** 遍历 AssistStructure 找带 autofill hint 的输入框。 */
    private fun findFields(contexts: List<FillContext>): FieldIds? {
        var username: AutofillId? = null
        var password: AutofillId? = null

        for (context in contexts) {
            val structure: AssistStructure = context.structure
            val count = structure.windowNodeCount
            for (w in 0 until count) {
                val window = structure.getWindowNodeAt(w)
                walkNode(window.rootViewNode, { node, hints ->
                    val isUsername = hints.any {
                        it == View.AUTOFILL_HINT_USERNAME ||
                            it == View.AUTOFILL_HINT_EMAIL_ADDRESS ||
                            it == View.AUTOFILL_HINT_PHONE
                    }
                    val isPassword = hints.any { it == View.AUTOFILL_HINT_PASSWORD }
                    if (isUsername && username == null) username = node.autofillId
                    if (isPassword && password == null) password = node.autofillId
                })
            }
            if (username != null && password != null) break
        }
        return FieldIds(username, password)
    }

    private fun walkNode(
        node: AssistStructure.ViewNode,
        onHints: (AssistStructure.ViewNode, List<String>) -> Unit,
    ) {
        val hints = node.autofillHints?.toList() ?: emptyList()
        if (hints.isNotEmpty() && node.autofillId != null) {
            onHints(node, hints)
        }
        for (i in 0 until node.childCount) {
            walkNode(node.getChildAt(i), onHints)
        }
    }

    /** 只读查询 KeyRing 数据库。 */
    private fun queryEntries(signal: CancellationSignal): List<Entry> {
        val dbFile = keyringDbFile(applicationContext)
        if (!dbFile.exists()) return emptyList()

        val result = mutableListOf<Entry>()
        var db: SQLiteDatabase? = null
        try {
            db = SQLiteDatabase.openDatabase(
                dbFile.absolutePath, null,
                SQLiteDatabase.OPEN_READONLY,
            )
            if (signal.isCanceled) return emptyList()
            val cursor: Cursor = db.rawQuery(
                "SELECT id, title, username, password FROM password_items " +
                    "ORDER BY isFavorite DESC, datetime(updatedAt) DESC LIMIT 100",
                null,
            )
            cursor.use {
                while (it.moveToNext() && !signal.isCanceled) {
                    result.add(
                        Entry(
                            id = it.getString(0) ?: continue,
                            title = it.getString(1) ?: "",
                            username = it.getString(2) ?: "",
                            password = it.getString(3) ?: "",
                        ),
                    )
                }
            }
        } catch (_: Exception) {
            // 数据库被锁/迁移中：本次无候选。
        } finally {
            db?.close()
        }
        return result
    }

    companion object {
        /** Flutter 侧 path_provider 的文档目录在 Android 上是 app_flutter/。 */
        fun keyringDbFile(context: Context): java.io.File {
            val flutterDir = java.io.File(context.filesDir.parentFile, "app_flutter")
            return java.io.File(flutterDir, "KeyRing.db")
        }
    }
}
