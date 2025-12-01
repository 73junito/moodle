param(
    [switch]$Apply,
    [string[]]$Paths = @('D:\Moodle\backups','D:\Moodle\bin')
)

$ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
$report = "D:\Moodle\backups\permissions-check-$ts.txt"
function Log { param($m) $m | Out-File -FilePath $report -Append -Encoding utf8; Write-Output $m }

Log "Permissions check started: $ts"
Log "Apply mode: $Apply"
Log ("Running as: {0}" -f [Environment]::UserName)

foreach ($path in $Paths) {
    if (-not (Test-Path $path)) {
        Log ("Path not found: {0}" -f $path)
        continue
    }
    Log "`n--- Path: $path ---"
    try {
        $acl = Get-Acl -Path $path
        Log ("Current ACL for {0}:" -f $path)
        $aclSddl = $acl.Sddl
        Log "SDDL: $aclSddl"
        Log "Entries:"
        foreach ($ace in $acl.Access) {
            Log ("  Identity: {0}  Rights: {1}  Inheritance: {2}  Propagation: {3}  Type: {4}" -f $ace.IdentityReference, $ace.FileSystemRights, $ace.InheritanceFlags, $ace.PropagationFlags, $ace.AccessControlType)
        }
    } catch {
        Log ("ERROR reading ACL for {0}: {1}" -f $path, $_.Exception.Message)
        continue
    }

    if ($Apply) {
        Log "Applying recommended ACLs to $path"
        try {
            # Ensure Administrators and SYSTEM have FullControl
            $acl = Get-Acl -Path $path
            $admins = New-Object System.Security.Principal.NTAccount('BUILTIN\Administrators')
            $systemAcc = New-Object System.Security.Principal.NTAccount('NT AUTHORITY\SYSTEM')
            $ruleAdmins = New-Object System.Security.AccessControl.FileSystemAccessRule($admins, "FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")
            $ruleSystem = New-Object System.Security.AccessControl.FileSystemAccessRule($systemAcc, "FullControl", "ContainerInherit, ObjectInherit", "None", "Allow")

            $acl.AddAccessRule($ruleAdmins)
            $acl.AddAccessRule($ruleSystem)

            # Make sure inheritance is enabled (preserve existing entries)
            $acl.SetAccessRuleProtection($false, $true)

            Set-Acl -Path $path -AclObject $acl
            Log ("Applied rules for Administrators and SYSTEM to {0}" -f $path)
        } catch {
            Log ("ERROR applying ACL to {0}: {1}" -f $path, $_.Exception.Message)
        }
    } else {
        Log "Dry-run: no changes applied to $path"
    }
}

Log "Permissions check finished. Report: $report"
exit 0
