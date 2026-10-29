<#
.SYNOPSIS
    Lista as OUs do AD, deixa você escolher e força gpupdate /force nos computadores delas.
#>
#Requires -Modules ActiveDirectory

param(
    [switch]$Recurse,        # Inclui sub-OUs das OUs escolhidas
    [switch]$Logoff,
    [switch]$Boot,
    [int]$ThrottleLimit = 32
)

# 1) Lista todas as OUs
$ous = Get-ADOrganizationalUnit -Filter * -Properties CanonicalName |
       Sort-Object CanonicalName |
       Select-Object Name, CanonicalName, DistinguishedName

if (-not $ous) { Write-Warning "Nenhuma OU encontrada."; return }

# 2) Seleção: janela gráfica; se não houver GUI, usa menu no console
$selecionadas = $null
if (Get-Command Out-GridView -ErrorAction SilentlyContinue) {
    $selecionadas = $ous | Out-GridView -Title "Selecione as OUs (Ctrl/Shift para várias) e clique OK" -PassThru
}
if (-not $selecionadas) {
    $i = 0
    $ous | ForEach-Object { "{0,3}) {1}" -f (++$i), $_.CanonicalName }
    $resp = Read-Host "`nDigite os números das OUs separados por vírgula (ex: 2,5)"
    $idx = $resp -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 }
    $selecionadas = $ous[$idx]
}
if (-not $selecionadas) { Write-Warning "Nenhuma OU selecionada."; return }

# 3) Busca os computadores das OUs escolhidas
$scope = if ($Recurse) { 'Subtree' } else { 'OneLevel' }
$computers = foreach ($ou in $selecionadas) {
    Get-ADComputer -Filter { Enabled -eq $true } -SearchBase $ou.DistinguishedName -SearchScope $scope |
        Select-Object -ExpandProperty Name
}
$computers = $computers | Sort-Object -Unique

if (-not $computers) { Write-Warning "Nenhum computador habilitado nas OUs escolhidas."; return }

Write-Host "`nOUs: $($selecionadas.CanonicalName -join ' | ')" -ForegroundColor Cyan
Write-Host "Computadores: $($computers.Count)" -ForegroundColor Cyan
if ((Read-Host "Continuar? (S/N)") -notmatch '^[sS]') { return }

# 4) Online/offline
$online = @(); $offline = @()
foreach ($c in $computers) {
    if (Test-Connection -ComputerName $c -Count 1 -Quiet) { $online += $c } else { $offline += $c }
}

# 5) gpupdate
$gpArgs = @('/force')
if ($Logoff) { $gpArgs += '/logoff' }
if ($Boot)   { $gpArgs += '/boot' }

$results = @()
if ($online) {
    $results = Invoke-Command -ComputerName $online -ThrottleLimit $ThrottleLimit `
        -ErrorAction SilentlyContinue -ErrorVariable remoteErrors -ScriptBlock {
            param($a)
            $out = & gpupdate.exe @a 2>&1 | Out-String
            [pscustomobject]@{ Computer = $env:COMPUTERNAME; ExitCode = $LASTEXITCODE; Output = $out.Trim() }
        } -ArgumentList (,$gpArgs)
}

# 6) Resumo e log
$ok     = @($results | Where-Object ExitCode -eq 0)
$falhou = @($results | Where-Object ExitCode -ne 0)

Write-Host "`n=== RESUMO ===" -ForegroundColor Cyan
Write-Host "Sucesso : $($ok.Count)" -ForegroundColor Green
Write-Host "Falha   : $($falhou.Count + @($remoteErrors).Count)" -ForegroundColor Red
Write-Host "Offline : $($offline.Count)" -ForegroundColor Yellow

if ($falhou)       { $falhou | Format-Table Computer, ExitCode -AutoSize }
if ($remoteErrors) { $remoteErrors | ForEach-Object { Write-Warning $_.Exception.Message } }
if ($offline)      { Write-Host "Offline: $($offline -join ', ')" -ForegroundColor Yellow }

$log = Join-Path $PSScriptRoot ("GPUpdate_{0:yyyyMMdd_HHmmss}.csv" -f (Get-Date))
$results | Select-Object Computer, ExitCode, Output | Export-Csv $log -NoTypeInformation -Encoding UTF8
Write-Host "Log salvo em: $log"