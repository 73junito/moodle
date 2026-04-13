$p = 'G:\moodle\innosetup-6.7.1.exe'
if (Test-Path $p) {
    Get-Item $p | Select-Object FullName,Length
    Get-FileHash -Algorithm SHA256 $p | Select-Object Algorithm,Hash
    $sig = Get-AuthenticodeSignature $p
    if ($sig -ne $null) {
        if ($sig.SignerCertificate -ne $null) {
            [PSCustomObject]@{
                Status = $sig.Status
                Signer = $sig.SignerCertificate.Subject
                Issuer = $sig.SignerCertificate.Issuer
                NotBefore = $sig.SignerCertificate.NotBefore
                NotAfter = $sig.SignerCertificate.NotAfter
            } | Format-List
        } else {
            [PSCustomObject]@{
                Status = $sig.Status
                Signer = $null
                Issuer = $null
                NotBefore = $null
                NotAfter = $null
            } | Format-List
        }
    }
} else {
    Write-Host 'MISSING'
}
