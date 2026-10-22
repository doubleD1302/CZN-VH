package vn.czn.viethoa.czn_patcher

import android.content.Context
import android.content.SharedPreferences
import io.github.muntashirakon.adb.AbsAdbConnectionManager
import io.github.muntashirakon.adb.AdbStream
import org.bouncycastle.jce.provider.BouncyCastleProvider
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
import java.security.interfaces.RSAPublicKey
import java.security.spec.PKCS8EncodedKeySpec
import java.security.spec.X509EncodedKeySpec
import java.util.*
import java.util.concurrent.Executors
import javax.security.auth.x500.X500Principal

class DelegatingX509Certificate(
    private val delegate: X509Certificate,
    private val rsaPublicKey: RSAPublicKey
) : X509Certificate() {
    override fun getPublicKey(): PublicKey = rsaPublicKey
    override fun getEncoded(): ByteArray = delegate.encoded
    override fun verify(key: PublicKey?) = delegate.verify(key)
    override fun verify(key: PublicKey?, sigProvider: String?) = delegate.verify(key, sigProvider)
    override fun toString(): String = delegate.toString()
    override fun checkValidity() = delegate.checkValidity()
    override fun checkValidity(date: Date?) = delegate.checkValidity(date)
    override fun getVersion(): Int = delegate.version
    override fun getSerialNumber(): BigInteger = delegate.serialNumber
    override fun getIssuerDN(): Principal = delegate.issuerDN
    override fun getSubjectDN(): Principal = delegate.subjectDN
    override fun getNotBefore(): Date = delegate.notBefore
    override fun getNotAfter(): Date = delegate.notAfter
    override fun getTBSCertificate(): ByteArray = delegate.tbsCertificate
    override fun getSignature(): ByteArray = delegate.signature
    override fun getSigAlgName(): String = delegate.sigAlgName
    override fun getSigAlgOID(): String = delegate.sigAlgOID
    override fun getSigAlgParams(): ByteArray? = delegate.sigAlgParams
    override fun getIssuerUniqueID(): BooleanArray? = delegate.issuerUniqueID
    override fun getSubjectUniqueID(): BooleanArray? = delegate.subjectUniqueID
    override fun getKeyUsage(): BooleanArray? = delegate.keyUsage
    override fun getBasicConstraints(): Int = delegate.basicConstraints
    override fun getCriticalExtensionOIDs(): MutableSet<String>? = delegate.criticalExtensionOIDs
    override fun getExtensionValue(oid: String?): ByteArray? = delegate.getExtensionValue(oid)
    override fun getNonCriticalExtensionOIDs(): MutableSet<String>? = delegate.nonCriticalExtensionOIDs
    override fun hasUnsupportedCriticalExtension(): Boolean = delegate.hasUnsupportedCriticalExtension()
}

object LocalAdbManager : AbsAdbConnectionManager() {
    private val worker = Executors.newSingleThreadExecutor()
    private var appContext: Context? = null
    private var prefs: SharedPreferences? = null
    private var privateKeyInstance: PrivateKey? = null
    private var publicKeyInstance: RSAPublicKey? = null
    private var certificateInstance: X509Certificate? = null

    private const val PREF_PORT = "adb_debugging_port"
    private const val PREF_HOST = "adb_debugging_host"

    fun init(context: Context) {
        appContext = context.applicationContext
        prefs = context.getSharedPreferences("czn_local_adb", Context.MODE_PRIVATE)
        try {
            loadOrGenerateKeys(context.filesDir)
        } catch (e: Throwable) {
            android.util.Log.e("CZN_ADB", "Khởi tạo khóa thất bại: ${e.message}", e)
        }

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

    fun loadOrGenerateKeys(filesDir: File, forceRegenerate: Boolean = false) {
        val keysDir = File(filesDir, "adb_keys")
        if (!keysDir.exists()) keysDir.mkdirs()
        val privFile = File(keysDir, "czn_adb_private.key")
        val pubFile = File(keysDir, "czn_adb_public.key")
        val certFile = File(keysDir, "czn_adb_cert.der")

        try {
            if (Security.getProvider(BouncyCastleProvider.PROVIDER_NAME) == null) {
                Security.addProvider(BouncyCastleProvider())
            }
        } catch (e: Throwable) {
            android.util.Log.w("CZN_ADB", "Không thể thêm BouncyCastleProvider: ${e.message}")
        }

        if (!forceRegenerate && privFile.exists() && certFile.exists() && privFile.length() > 0 && certFile.length() > 0) {
            try {
                val kf = KeyFactory.getInstance("RSA")
                val priv = kf.generatePrivate(PKCS8EncodedKeySpec(privFile.readBytes()))

                val pub: RSAPublicKey? = if (pubFile.exists() && pubFile.length() > 0) {
                    try {
                        kf.generatePublic(X509EncodedKeySpec(pubFile.readBytes())) as? RSAPublicKey
                    } catch (_: Throwable) { null }
                } else null

                val cf = try {
                    CertificateFactory.getInstance("X.509", BouncyCastleProvider.PROVIDER_NAME)
                } catch (_: Throwable) {
                    CertificateFactory.getInstance("X.509")
                }
                val rawCert = cf.generateCertificate(certFile.inputStream()) as? X509Certificate

                val effectivePub = pub ?: (rawCert?.publicKey as? RSAPublicKey)
                if (priv != null && rawCert != null && effectivePub != null && effectivePub.modulus != null && effectivePub.modulus.bitLength() >= 2048) {
                    if (!pubFile.exists() || pubFile.length() == 0L) {
                        try { pubFile.writeBytes(effectivePub.encoded) } catch (_: Throwable) {}
                    }
                    privateKeyInstance = priv
                    publicKeyInstance = effectivePub
                    certificateInstance = DelegatingX509Certificate(rawCert, effectivePub)
                    android.util.Log.d("CZN_ADB", "Đã nạp và xác minh thành công cặp khóa ADB RSA 2048.")
                    return
                } else {
                    android.util.Log.w("CZN_ADB", "Khóa cũ không đạt chuẩn RSA, xóa và tạo lại mới...")
                }
            } catch (e: Throwable) {
                android.util.Log.w("CZN_ADB", "Khóa cũ hỏng (${e.message}), tạo lại mới...", e)
            }
            try { privFile.delete() } catch (_: Exception) {}
            try { pubFile.delete() } catch (_: Exception) {}
            try { certFile.delete() } catch (_: Exception) {}
        }

        // Generate standard Software RSA 2048-bit keypair
        val kpg = KeyPairGenerator.getInstance("RSA")
        kpg.initialize(2048)
        val kp = kpg.generateKeyPair()
        val priv = kp.private
        val pub = kp.public as RSAPublicKey
        check(pub.modulus != null) { "Public key modulus vừa sinh bị null" }

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
        gen.setPublicKey(pub)
        gen.setSignatureAlgorithm("SHA256withRSA")
        val rawCert: X509Certificate = try {
            gen.generate(priv, BouncyCastleProvider.PROVIDER_NAME)
        } catch (_: Throwable) {
            gen.generate(priv)
        }

        try {
            privFile.writeBytes(priv.encoded)
            pubFile.writeBytes(pub.encoded)
            certFile.writeBytes(rawCert.encoded)
        } catch (e: Throwable) {
            android.util.Log.w("CZN_ADB", "Không thể lưu khóa ra file: ${e.message}")
        }

        privateKeyInstance = priv
        publicKeyInstance = pub
        certificateInstance = DelegatingX509Certificate(rawCert, pub)
        android.util.Log.d("CZN_ADB", "Đã tạo mới và kiểm chứng cặp khóa ADB RSA 2048 thành công!")
    }

    override fun getPrivateKey(): PrivateKey {
        privateKeyInstance?.let { return it }
        appContext?.let { loadOrGenerateKeys(it.filesDir) }
        return privateKeyInstance ?: throw IllegalStateException("Chưa khởi tạo private key ADB.")
    }

    override fun getCertificate(): Certificate {
        certificateInstance?.let { cert ->
            val pub = cert.publicKey as? RSAPublicKey
            if (pub?.modulus != null) return cert
        }
        appContext?.let { loadOrGenerateKeys(it.filesDir, forceRegenerate = true) }
        return certificateInstance ?: throw IllegalStateException("Chưa khởi tạo certificate ADB.")
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
        getPrivateKey()
        val cert = getCertificate()
        val pubKey = cert.publicKey as? RSAPublicKey
        if (pubKey == null || pubKey.modulus == null) {
            android.util.Log.w("CZN_ADB", "Public key không hợp lệ trước khi ghép nối, tái tạo khẩn cấp...")
            appContext?.let { loadOrGenerateKeys(it.filesDir, forceRegenerate = true) }
        }

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

        var lastException: Throwable? = null
        for (targetHost in hostsToTry) {
            try {
                android.util.Log.d("CZN_ADB", "Thử ghép nối ADB tới $targetHost:$port...")
                if (pair(targetHost, port, code)) {
                    android.util.Log.d("CZN_ADB", "Ghép nối ADB thành công với $targetHost:$port!")
                    return true
                }
            } catch (t: Throwable) {
                android.util.Log.w("CZN_ADB", "Ghép nối thất bại với $targetHost:$port: ${t.message}", t)
                lastException = t
            }
        }
        if (lastException != null) {
            throw lastException
        }
        return false
    }

    fun connectDevice(host: String? = null, port: Int): Boolean {
        getPrivateKey()
        val cert = getCertificate()
        val pubKey = cert.publicKey as? RSAPublicKey
        if (pubKey == null || pubKey.modulus == null) {
            android.util.Log.w("CZN_ADB", "Public key không hợp lệ trước khi kết nối, tái tạo khẩn cấp...")
            appContext?.let { loadOrGenerateKeys(it.filesDir, forceRegenerate = true) }
        }

        if (isConnected) {
            try { disconnect() } catch (_: Throwable) {}
        }

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

        var lastException: Throwable? = null
        for (targetHost in hostsToTry) {
            try {
                android.util.Log.d("CZN_ADB", "Thử kết nối ADB tới $targetHost:$port...")
                if (connect(targetHost, port)) {
                    prefs?.edit()?.putInt(PREF_PORT, port)?.putString(PREF_HOST, targetHost)?.apply()
                    android.util.Log.d("CZN_ADB", "Kết nối ADB thành công với $targetHost:$port!")
                    return true
                }
            } catch (t: Throwable) {
                android.util.Log.w("CZN_ADB", "Kết nối thất bại với $targetHost:$port: ${t.message}", t)
                lastException = t
            }
        }
        if (lastException != null) {
            throw lastException
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
        } catch (e: IOException) {
            if (e.message?.contains("Stream closed", ignoreCase = true) != true &&
                e.message?.contains("closed", ignoreCase = true) != true) {
                throw e
            }
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
                val n = try {
                    stream.read(buf, 0, buf.size)
                } catch (e: IOException) {
                    if (e.message?.contains("Stream closed", ignoreCase = true) == true ||
                        e.message?.contains("closed", ignoreCase = true) == true) {
                        -1
                    } else {
                        throw e
                    }
                }
                if (n < 0) break
                stdout.write(buf, 0, n)
            }
        } catch (e: IOException) {
            if (e.message?.contains("Stream closed", ignoreCase = true) != true &&
                e.message?.contains("closed", ignoreCase = true) != true) {
                throw e
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
        val cmd = "export CLASSPATH=\"$apkPath\"; exec app_process /system/bin vn.czn.viethoa.czn_patcher.PatchCli ${args.joinToString(" ") { "\"$it\"" }} 2>&1"
        val stream: AdbStream = openStream("shell:$cmd")
        val streamIn = stream.openInputStream()
        val reader = BufferedReader(InputStreamReader(streamIn, Charsets.UTF_8))
        var jsonLine: String? = null
        val allOutput = StringBuilder()
        try {
            while (true) {
                val line = try {
                    reader.readLine()
                } catch (e: IOException) {
                    if (e.message?.contains("Stream closed", ignoreCase = true) == true ||
                        e.message?.contains("closed", ignoreCase = true) == true) {
                        null
                    } else {
                        throw e
                    }
                } ?: break

                allOutput.append(line).append("\n")

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
        } catch (e: IOException) {
            if (e.message?.contains("Stream closed", ignoreCase = true) != true &&
                e.message?.contains("closed", ignoreCase = true) != true) {
                throw e
            }
        } finally {
            try { stream.close() } catch (_: Exception) {}
        }
        if (jsonLine != null) {
            return JSONObject(jsonLine)
        }
        val outText = allOutput.toString().trim()
        throw IllegalStateException(
            if (outText.isNotBlank()) "Lệnh PatchCli kết thúc nhưng không có kết quả JSON. Đầu ra:\n$outText"
            else "Lệnh PatchCli không trả về dữ liệu nào từ tiến trình Local ADB."
        )
    }
}
