<#
.SYNOPSIS
    Script para verificar o LogonHours zerado no AD e revogar sessões no Entra ID via API Graph.
#>

# Conexão com o Microsoft Graph
try {
    Write-Host "Conectando ao Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes "User.Read.All", "User.RevokeSessions.All" -ErrorAction Stop
    Import-Module Microsoft.Graph.Users -ErrorAction SilentlyContinue
}
catch {
    Write-Error "Erro ao conectar ao Microsoft Graph: $_"
    exit
}

Write-Host "Iniciando varredura no Active Directory..." -ForegroundColor Cyan

# Consulta os usuários buscando a propriedade LogonHours
$usuariosAD = Get-ADUser -Filter * -Properties LogonHours, UserPrincipalName, Enabled

$contadorBloqueados = 0

foreach ($adUser in $usuariosAD) {
    # Pula apenas usuários desativados no AD
    if (-not $adUser.Enabled) { 
        continue 
    }

    # Verifica se a propriedade LogonHours está totalmente zerada
    $isLogonHoursZeroed = $true
    if ($adUser.LogonHours) {
        foreach ($byte in $adUser.LogonHours) {
            if ($byte -ne 0) {
                $isLogonHoursZeroed = $false
                break
            }
        }
    } else {
        $isLogonHoursZeroed = $false 
    }

    # Se estiver zerado e tiver UPN preenchido
    if ($isLogonHoursZeroed -and $adUser.UserPrincipalName) {
        $upn = $adUser.UserPrincipalName
        
        # Pula contas locais que não são do Microsoft 365 (ex: domínios .sp)
        if ($upn -like "*.sp") {
            continue
        }

        Write-Host "-> Verificando usuário com LogonHours zerado: $upn" -ForegroundColor Yellow

        try {
            # Tenta localizar o usuário no Entra ID para pegar o ID correto
            $mgUser = Get-MgUser -UserId $upn -ErrorAction Stop

            if ($mgUser) {
                # Revoga as sessões ativas no M365 usando chamada direta à API (evita erro de cmdlet ausente)
                Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$($mgUser.Id)/revokeSignInSessions" -ErrorAction Stop
                
                Write-Host "   [Sucesso] Sessões revogadas para: $upn" -ForegroundColor Green
                $contadorBloqueados++
            }
        }
        catch {
            Write-Warning "   [Aviso] Erro ao processar o usuário $upn. Detalhes: $_"
        }
    }
}

Disconnect-MgGraph | Out-Null
Write-Host "Varredura concluída. Total de usuários com sessões revogadas: $contadorBloqueados" -ForegroundColor Cyan