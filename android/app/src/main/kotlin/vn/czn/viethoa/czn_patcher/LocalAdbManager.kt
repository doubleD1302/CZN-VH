package vn.czn.viethoa.czn_patcher

import android.content.Context
import android.content.SharedPreferences
import io.github.muntashirakon.adb.AbsAdbConnectionManager
import io.github.muntashirakon.adb.AdbStream
import org.bouncycastle.x509.X509V3CertificateGenerator
import org.json.JSONObject
import java.io.*
import java.math.BigInteger
import java.net.Inet4Address
import java.net.NetworkInterface
import java.security.*
import java.security.cert.Certificate
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec
import java.util.*
import java.util.concurrent.Executors
import javax.security.auth.x500.X500Principal

object LocalAdbManager : AbsAdbConnectionManager() {
    private val worker = Executors.newSingleThreadExecutor()
    private var prefs: SharedPreferences? = null
    private var privateKeyInstance: PrivateKey? = null
    private var certificateInstance: Certificate? = null

    private const val PREF_PORT = "adb_debugging_port"
    private const val PREF_HOST = "adb_debugging_host"

    fun init(context: Context) {
        prefs = context.getSharedPreferences("czn_local_adb", Context.MODE_PRIVATE)
        loadOrGenerateKeys(context.filesDir)

        val savedPort = prefs?.getInt(PREF_PORT, -1) ?: -1
        val savedHost = prefs?.getString(PREF_HOST, null)
        if (savedPort > 0) {
            worker.execute {
                try {
                    connectDevice(savedHost, savedPort)
                } catch (_: Exception) {}
            }
        }
    }

    private fun loadOrGenerateKeys(filesDir: File) {
        val keysDir = File(filesDir, "adb_keys")
        if (!keysDir.exists()) keysDir.mkdirs()
        val privFile = File(keysDir, "czn_adb_private.key")
        val certFile = File(keysDir, "czn_adb_cert.der")

        if (privFile.exists() && certFile.exists()) {
            try {
                val privBytes = privFile.readBytes()
                val kf = KeyFactory.getInstance("RSA")
                val priv = kf.generatePrivate(PKCS8EncodedKeySpec(privBytes))
                val cf = CertificateFactory.getInstance("X.509")
                val cert = cf.generateCertificate(certFile.inputStream())
                privateKeyInstance = priv
                certificateInstance = cert
                return
            } catch (_: Exception) {
                privFile.delete()
                certFile.delete()
            }
        }

        // Generate standard Software RSA 2048-bit keypair
        val kpg = KeyPairGenerator.getInstance("RSA")
        kpg.initialize(2048)
        val kp = kpg.generateKeyPair()

        // Generate X509 certificate using BouncyCastle
        @Suppress("DEPRECATION")
        val gen = X509V3CertificateGenerator()
        val now = System.currentTimeMillis()
        gen.setSerialNumber(BigInteger.valueOf(now))
        val principal = X500Principal("CN=CZN_LocalADB")
        gen.setIssuerDN(principal)
        gen.setSubjectDN(principal)
        gen.setNotBefore(Date(now - 86400000L))
        gen.setNotAfter(Date(now + 86400000L * 365 * 10)) // 10 years
        gen.setPublicKey(kp.public)
        gen.setSignatureAlgorithm("SHA256WithRSAEncryption")
        val cert: X509Certificate = gen.generate(kp.private)

        privFile.writeBytes(kp.private.encoded)
        certFile.writeBytes(cert.encoded)

        privateKeyInstance = kp.private
        certificateInstance = cert
    }

    override fun getPrivateKey(): PrivateKey {
        return privateKeyInstance ?: throw IllegalStateException("Chưa khởi tạo private key.")
    }

    override fun getCertificate(): Certificate {
        return certificateInstance ?: throw IllegalStateException("Chưa khởi tạo certificate.")
    }

    override fun getDeviceName(): String {
        return "CZN_LocalADB"
    }

    fun isLocalConnected(): Boolean {
        return isConnected
    }

    fun getLocalWifiIp(): String? {
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return null
            for (intf in interfaces) {
                if (!intf.isUp || intf.isLoopback) continue
                val addrs = intf.inetAddresses ?: continue
                for (addr in addrs) {
                    if (!addr.isLoopbackAddress && addr is Inet4Address) {
                        val host = addr.hostAddress
                        if (!host.isNullOrEmpty() && !host.startsWith("127.")) {
                            return host
                        }
                    }
                }
            }
        } catch (_: Exception) {}
        return null
    }

    fun pairDevice(host: String? = null, port: Int, code: String): Boolean {
        val hostsToTry = mutableListOf<String>()
        if (!host.isNullOrBlank()) {
            hostsToTry.add(host.trim())
        }
        val wifiIp = getLocalWifiIp()
        if (!wifiIp.isNullOrBlank() && !hostsToTry.contains(wifiIp)) {
            hostsToTry.add(wifiIp)
        }
        if (!hostsToTry.contains("127.0.0.1")) {
            hostsToTry.add("127.0.0.1")
        }

        for (targetHost in hostsToTry) {
            try {
                if (pair(targetHost, port, code)) {
                    return true
                }
            } catch (_: Exception) {}
        }
        return false
    }

    fun connectDevice(host: String? = null, port: Int): Boolean {
        val hostsToTry = mutableListOf<String>()
        if (!host.isNullOrBlank()) {
            hostsToTry.add(host.trim())
        }
        val wifiIp = getLocalWifiIp()
        if (!wifiIp.isNullOrBlank() && !hostsToTry.contains(wifiIp)) {
            hostsToTry.add(wifiIp)
        }
        if (!hostsToTry.contains("127.0.0.1")) {
            hostsToTry.add("127.0.0.1")
        }

        for (targetHost in hostsToTry) {
            try {
                if (connect(targetHost, port)) {
                    prefs?.edit()?.putInt(PREF_PORT, port)?.putString(PREF_HOST, targetHost)?.apply()
                    return true
                }
            } catch (_: Exception) {}
        }
        return false
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
