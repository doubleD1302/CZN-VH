package vn.czn.viethoa.czn_patcher

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import io.github.muntashirakon.adb.AbsAdbConnectionManager
import io.github.muntashirakon.adb.AdbStream
import org.json.JSONObject
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.InputStreamReader
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.cert.Certificate
import java.util.concurrent.Executors
import javax.security.auth.x500.X500Principal

object LocalAdbManager : AbsAdbConnectionManager() {
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private val worker = Executors.newSingleThreadExecutor()
    private var prefs: SharedPreferences? = null
    private const val KEY_ALIAS = "czn_local_adb_key"
    private const val PREF_PORT = "adb_debugging_port"

    fun init(context: Context) {
        prefs = context.getSharedPreferences("czn_local_adb", Context.MODE_PRIVATE)
        if (!keyStore.containsAlias(KEY_ALIAS)) {
            val kpg = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, "AndroidKeyStore")
            val spec = KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA512)
                .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
                .setKeySize(2048)
                .setCertificateSubject(X500Principal("CN=CZN_LocalADB"))
                .setCertificateSerialNumber(BigInteger.ONE)
                .build()
            kpg.initialize(spec)
            kpg.generateKeyPair()
        }
        val savedPort = prefs?.getInt(PREF_PORT, -1) ?: -1
        if (savedPort > 0) {
            worker.execute {
                try {
                    connect("127.0.0.1", savedPort)
                } catch (_: Exception) {}
            }
        }
    }

    override fun getPrivateKey(): PrivateKey {
        return keyStore.getKey(KEY_ALIAS, null) as PrivateKey
    }

    override fun getCertificate(): Certificate {
        return keyStore.getCertificate(KEY_ALIAS)
    }

    override fun getDeviceName(): String {
        return "CZN_LocalADB"
    }

    fun isLocalConnected(): Boolean {
        return isConnected
    }

    fun pairDevice(port: Int, code: String): Boolean {
        return pair("127.0.0.1", port, code)
    }

    fun connectDevice(port: Int): Boolean {
        val success = connect("127.0.0.1", port)
        if (success) {
            prefs?.edit()?.putInt(PREF_PORT, port)?.apply()
        }
        return success
    }

    fun pushFile(inputStream: InputStream, remotePath: String) {
        check(isConnected) { "Chưa kết nối Local ADB. Hãy kết nối qua Gỡ lỗi không dây." }
        execCommand("rm -f \"$remotePath\"")
        val stream: AdbStream = openStream("shell:cat > \"$remotePath\"")
        val out = stream.openOutputStream()
        try {
            val buf = ByteArray(16384)
            while (true) {
                val n = inputStream.read(buf)
                if (n <= 0) break
                out.write(buf, 0, n)
            }
            out.flush()
        } finally {
            try { out.close() } catch (_: Exception) {}
            try { stream.close() } catch (_: Exception) {}
        }
        execCommand("chmod 644 \"$remotePath\"")
    }

    fun execCommand(command: String): String {
        check(isConnected) { "Chưa kết nối Local ADB. Hãy kết nối qua Gỡ lỗi không dây." }
        val stream: AdbStream = openStream("shell:$command")
        val stdout = ByteArrayOutputStream()
        try {
            val buf = ByteArray(4096)
            while (!stream.isClosed) {
                val n = stream.read(buf, 0, buf.size)
                if (n < 0) break
                stdout.write(buf, 0, n)
            }
        } finally {
            try { stream.close() } catch (_: Exception) {}
        }
        return stdout.toString("UTF-8")
    }

    fun execPatchCli(
        context: Context,
        args: List<String>,
        onProgress: ((String, Int) -> Unit)? = null
    ): JSONObject {
        check(isConnected) { "Chưa kết nối Local ADB. Hãy kết nối qua Gỡ lỗi không dây." }
        val apkPath = context.applicationInfo.sourceDir
        val cmd = "CLASSPATH=\"$apkPath\" app_process /system/bin vn.czn.viethoa.czn_patcher.PatchCli ${args.joinToString(" ") { "\"$it\"" }}"
        val stream: AdbStream = openStream("shell:$cmd")
        val streamIn = stream.openInputStream()
        val reader = BufferedReader(InputStreamReader(streamIn, Charsets.UTF_8))
        var jsonLine: String? = null
        try {
            while (true) {
                val line = reader.readLine() ?: break
                if (line.startsWith("PROGRESS:")) {
                    val parts = line.split(":", limit = 3)
                    if (parts.size >= 3) {
                        val pct = parts[1].toIntOrNull() ?: 0
                        val lbl = parts[2]
                        onProgress?.invoke(lbl, pct)
                    }
                } else if (line.trim().startsWith("{") && line.trim().endsWith("}")) {
                    jsonLine = line.trim()
                }
            }
        } finally {
            try { stream.close() } catch (_: Exception) {}
        }
        if (jsonLine != null) {
            return JSONObject(jsonLine)
        }
        throw IllegalStateException("Lệnh PatchCli không trả về kết quả JSON hợp lệ.")
    }
}
