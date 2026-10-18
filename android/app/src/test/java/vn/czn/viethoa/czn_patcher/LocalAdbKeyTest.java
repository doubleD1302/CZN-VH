package vn.czn.viethoa.czn_patcher;

import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.x509.X509V3CertificateGenerator;
import org.junit.Assert;
import org.junit.BeforeClass;
import org.junit.Test;

import java.io.File;
import java.math.BigInteger;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.Security;
import java.security.cert.X509Certificate;
import java.security.interfaces.RSAPublicKey;
import java.util.Date;
import javax.security.auth.x500.X500Principal;

public class LocalAdbKeyTest {

    @BeforeClass
    public static void setUp() {
        if (Security.getProvider(BouncyCastleProvider.PROVIDER_NAME) == null) {
            Security.addProvider(new BouncyCastleProvider());
        }
    }

    @Test
    public void testDelegatingX509CertificateGuaranteesModulus() throws Exception {
        KeyPairGenerator kpg = KeyPairGenerator.getInstance("RSA");
        kpg.initialize(2048);
        KeyPair kp = kpg.generateKeyPair();
        RSAPublicKey pub = (RSAPublicKey) kp.getPublic();

        @SuppressWarnings("deprecation")
        X509V3CertificateGenerator gen = new X509V3CertificateGenerator();
        long now = System.currentTimeMillis();
        gen.setSerialNumber(BigInteger.valueOf(now));
        X500Principal principal = new X500Principal("CN=CZN_LocalADB_Test");
        gen.setIssuerDN(principal);
        gen.setSubjectDN(principal);
        gen.setNotBefore(new Date(now - 86400000L));
        gen.setNotAfter(new Date(now + 86400000L * 365));
        gen.setPublicKey(pub);
        gen.setSignatureAlgorithm("SHA256withRSA");
        X509Certificate rawCert = gen.generate(kp.getPrivate(), BouncyCastleProvider.PROVIDER_NAME);

        DelegatingX509Certificate delegating = new DelegatingX509Certificate(rawCert, pub);

        Assert.assertNotNull("getPublicKey() must never be null", delegating.getPublicKey());
        Assert.assertTrue("getPublicKey() must be RSAPublicKey", delegating.getPublicKey() instanceof RSAPublicKey);

        RSAPublicKey rsaKey = (RSAPublicKey) delegating.getPublicKey();
        Assert.assertNotNull("Modulus must never be null", rsaKey.getModulus());
        Assert.assertTrue("Modulus bit length must be >= 2048", rsaKey.getModulus().bitLength() >= 2048);
    }

    @Test
    public void testLocalAdbManagerLoadAndGenerateKeys() throws Exception {
        File tempDir = new File(System.getProperty("java.io.tmpdir"), "czn_adb_test_" + System.currentTimeMillis());
        tempDir.mkdirs();
        try {
            LocalAdbManager.INSTANCE.loadOrGenerateKeys(tempDir, false);

            Assert.assertNotNull("PrivateKey instance must not be null", LocalAdbManager.INSTANCE.getPrivateKey());
            Assert.assertNotNull("Certificate instance must not be null", LocalAdbManager.INSTANCE.getCertificate());

            java.security.cert.Certificate cert = LocalAdbManager.INSTANCE.getCertificate();
            Assert.assertTrue("Certificate must have RSAPublicKey", cert.getPublicKey() instanceof RSAPublicKey);
            RSAPublicKey rsaPub = (RSAPublicKey) cert.getPublicKey();
            Assert.assertNotNull("Modulus must not be null", rsaPub.getModulus());
            Assert.assertTrue("Modulus bit length >= 2048", rsaPub.getModulus().bitLength() >= 2048);

            // Test reload from existing files
            LocalAdbManager.INSTANCE.loadOrGenerateKeys(tempDir, false);
            java.security.cert.Certificate reloadedCert = LocalAdbManager.INSTANCE.getCertificate();
            RSAPublicKey reloadedPub = (RSAPublicKey) reloadedCert.getPublicKey();
            Assert.assertEquals("Modulus must match across reloads", rsaPub.getModulus(), reloadedPub.getModulus());

            // Test force regenerate
            LocalAdbManager.INSTANCE.loadOrGenerateKeys(tempDir, true);
            java.security.cert.Certificate regenCert = LocalAdbManager.INSTANCE.getCertificate();
            RSAPublicKey regenPub = (RSAPublicKey) regenCert.getPublicKey();
            Assert.assertNotNull("Regenerated modulus must not be null", regenPub.getModulus());
        } finally {
            File[] files = tempDir.listFiles();
            if (files != null) {
                for (File f : files) {
                    File[] sub = f.listFiles();
                    if (sub != null) for (File s : sub) s.delete();
                    f.delete();
                }
            }
            tempDir.delete();
        }
    }
}
