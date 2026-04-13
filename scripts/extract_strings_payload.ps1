$in = 'G:\moodle\installer_extracted\[0]'
$out = 'G:\moodle\strings_payload.txt'
if (Test-Path $out) { Remove-Item $out -Force }
$min = 6
$fs = [IO.File]::OpenRead($in)
$buf = New-Object byte[] 4096
$sb = New-Object System.Text.StringBuilder
while (($read = $fs.Read($buf,0,$buf.Length)) -gt 0) {
    for ($i = 0; $i -lt $read; $i++) {
        $b = $buf[$i]
        if ($b -ge 32 -and $b -le 126) {
            $sb.Append([char]$b) > $null
        } else {
            if ($sb.Length -ge $min) { [System.IO.File]::AppendAllText($out, $sb.ToString() + "`n") }
            $sb.Clear() > $null
        }
    }
}
if ($sb.Length -ge $min) { [System.IO.File]::AppendAllText($out, $sb.ToString() + "`n") }
$fs.Close()

$pattern = 'localhost|127\.0\.0\.1|11434|ollama|http|https|port|listen|serve|daemon|service|CreateService|schtasks|RunOnce|HKLM|HKCU|ProgramData|AppData'
if (Test-Path $out) {
    Write-Host '--- Filtered hits ---'
    Select-String -Path $out -Pattern $pattern -AllMatches | ForEach-Object { $_.Line } | Select-Object -Unique | Select-Object -First 200 | ForEach-Object { Write-Host $_ }
} else {
    Write-Host 'strings file not created'
}
