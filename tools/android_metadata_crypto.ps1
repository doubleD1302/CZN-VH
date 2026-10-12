param([ValidateSet('Sign','Verify')][string]$Mode,[string]$InputFile,[string]$PublicFile,[string]$KeyFile,[string]$OutputFile)
$ErrorActionPreference = 'Stop'
$rsa = [System.Security.Cryptography.RSA]::Create()
$keyBytes = $null
try {
 $publicBytes = [System.IO.File]::ReadAllBytes($PublicFile)
 $readCount = 0
 if ($Mode -eq 'Sign') {
  $keyBytes = [System.IO.File]::ReadAllBytes($KeyFile)
  $rsa.ImportPkcs8PrivateKey($keyBytes,[ref]$readCount)
  if ([Convert]::ToBase64String($rsa.ExportSubjectPublicKeyInfo()) -ne [Convert]::ToBase64String($publicBytes)) { throw 'Khóa ký không thuộc kênh CZN cộng đồng.' }
  $raw = [System.IO.File]::ReadAllBytes($InputFile)
  $signature = $rsa.SignData($raw,[System.Security.Cryptography.HashAlgorithmName]::SHA256,[System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
  $result = @{signed=[Convert]::ToBase64String($raw);signature=[Convert]::ToBase64String($signature);key_id='czn-community-2026'} | ConvertTo-Json -Compress
  [System.IO.File]::WriteAllText($OutputFile,$result,[System.Text.UTF8Encoding]::new($false))
 } else {
  $rsa.ImportSubjectPublicKeyInfo($publicBytes,[ref]$readCount)
  $envelope = Get-Content -LiteralPath $InputFile -Raw -Encoding UTF8 | ConvertFrom-Json
  $raw = [Convert]::FromBase64String($envelope.signed)
  if (-not $rsa.VerifyData($raw,[Convert]::FromBase64String($envelope.signature),[System.Security.Cryptography.HashAlgorithmName]::SHA256,[System.Security.Cryptography.RSASignaturePadding]::Pkcs1)) { throw 'Chữ ký cập nhật không hợp lệ.' }
  [System.IO.File]::WriteAllBytes($OutputFile,$raw)
 }
} finally { $rsa.Dispose();if($keyBytes){[Array]::Clear($keyBytes,0,$keyBytes.Length)} }
