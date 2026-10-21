<#
.SYNOPSIS
    Script automatizado para verificar o LogonHours zerado no AD e revogar sessões no Entra ID.
#>

$ScriptDir = "C:\auditoria"
if (-not (Test-Path $ScriptDir)) { New-Item -Path $ScriptDir -ItemType Directory | Out-Null }
$LogFile = Join-Path -Path $ScriptDir -ChildPath "Log_RevogarSessao_365_$((Get-Date).ToString('yyyyMMdd_HHmmss')).txt"

Start-Transcript -Path $LogFile -Append -Force
Write-Host "=== Início da Execução: $(Get-Date) ===" -ForegroundColor Cyan

$TenantDomain   = "crn3.org.br"
$ClientID       = "fcbe8bc8-ae43-4ce5-a28e-3246ded4d973"
$CertThumbprint = "62E1DCE226784599F868ACB64100D69D0CD48BD6"

try {
    $Cert = Get-ChildItem -Path "Cert:\LocalMachine\My\$CertThumbprint" -ErrorAction Stop
    Write-Host "Certificado encontrado: $($Cert.Subject)" -ForegroundColor Green
}
catch {
    Write-Error "❌ Certificado não encontrado"
    Stop-Transcript
    exit 1
}

try {
    Connect-MgGraph -TenantId $TenantDomain -ClientId $ClientID -CertificateThumbprint $CertThumbprint -ErrorAction Stop
    Write-Host "Conectado ao Microsoft Graph com sucesso." -ForegroundColor Green
}
catch {
    Write-Error ("❌ Erro ao conectar: " + $_.Exception.Message)
    Stop-Transcript
    exit 1
}

Write-Host "Iniciando varredura no Active Directory..." -ForegroundColor Cyan

try {
    $usuariosAD = Get-ADUser -Filter * -Properties LogonHours, UserPrincipalName, Enabled
    $contador = 0

    foreach ($adUser in $usuariosAD) {
        if (-not $adUser.Enabled) { continue }

        $isZero = $true
        if ($adUser.LogonHours) {
            foreach ($byte in $adUser.LogonHours) {
                if ($byte -ne 0) { $isZero = $false; break }
            }
        } else {
            $isZero = $false
        }

        if ($isZero -and $adUser.UserPrincipalName) {
            $upn = $adUser.UserPrincipalName
            if ($upn -like "*.sp") { continue }

            Write-Host "-> Verificando usuário: $upn" -ForegroundColor Yellow
            try {
                $mgUser = Get-MgUser -UserId $upn -ErrorAction Stop
                if ($mgUser) {
                    Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$($mgUser.Id)/revokeSignInSessions" -ErrorAction Stop | Out-Null
                    Write-Host "   [Sucesso] Revogado: $upn" -ForegroundColor Green
                    $contador++
                }
            }
            catch {
                Write-Warning ("   [Aviso] Erro em " + $upn + ": " + $_.Exception.Message)
            }
        }
    }
    Write-Host "Varredura concluída. Total revogado: $contador" -ForegroundColor Cyan
}
catch {
    Write-Error ("❌ Erro no AD: " + $_.Exception.Message)
}

Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
Write-Host "=== Fim da Execução: $(Get-Date) ===" -ForegroundColor Cyan
Stop-Transcript
