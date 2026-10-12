param([Parameter(Mandatory=$true)][string]$InputFile,[Parameter(Mandatory=$true)][string]$KeyFile,[Parameter(Mandatory=$true)][string]$OutputFile)
$ErrorActionPreference = 'Stop'
$keyBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $KeyFile))
$rsa = [System.Security.Cryptography.RSA]::Create()
try {
    $bytesRead = 0
    $rsa.ImportPkcs8PrivateKey($keyBytes,[ref]$bytesRead)
    $raw = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $InputFile))
    $signature = $rsa.SignData($raw,[System.Security.Cryptography.HashAlgorithmName]::SHA256,[System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $envelope = @{ signed=[Convert]::ToBase64String($raw); signature=[Convert]::ToBase64String($signature); key_id='czn-community-2026' } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($OutputFile),$envelope,[System.Text.UTF8Encoding]::new($false))
} finally { $rsa.Dispose(); [Array]::Clear($keyBytes,0,$keyBytes.Length) }
