$dir = 'G:\moodle\installer_extracted_full'
$keywords = @('localhost','127.0.0.1','http','https','11434','port','listen','serve','daemon','service','CreateService','schtasks','RunOnce','Run','HKLM','HKCU','ProgramData','AppData','model','ollama','api')
$results = @()
Get-ChildItem -Path $dir -Recurse -File | ForEach-Object {
    $path = $_.FullName
    try {
        $fs = [IO.File]::OpenRead($path)
        $bufSize = 4*1024*1024
        $buf = New-Object byte[] $bufSize
        while (($read = $fs.Read($buf,0,$bufSize)) -gt 0) {
            $s = [Text.Encoding]::ASCII.GetString($buf,0,$read)
            foreach ($k in $keywords) {
                if ($s.IndexOf($k,[StringComparison]::InvariantCultureIgnoreCase) -ne -1) {
                    $results += [PSCustomObject]@{ Path = $path; Keyword = $k }
                    break
                }
            }
            if ($results.Count -ge 5000) { break }
        }
        $fs.Close()
    } catch {}
}
if ($results.Count -eq 0) {
    Write-Output 'NO_MATCHES'
} else {
    $results | Select-Object -Unique Path,Keyword | Sort-Object Path | Format-Table -AutoSize
}
