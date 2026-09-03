Import-Module ActiveDirectory

# =========================================================
# CONFIGURAÇÃO DE LOGS
# =========================================================
$logPath = "C:\hOra_eXtra_lOg\oFfice_hOurs_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$logDir  = Split-Path -Path $logPath -Parent

if (-not (Test-Path -Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "ERROR", "WARNING")]
        [string]$Type = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Type] $Message"
    
    switch ($Type) {
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "ERROR"   { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        default   { Write-Host $logEntry -ForegroundColor Cyan }
    }
    Add-Content -Path $logPath -Value $logEntry -Encoding UTF8
}

Write-Log "Iniciando processo de bloqueio total do LogonHours..." "INFO"

# =========================================================
# 1. USUÁRIOS MANUAIS (Opção A)
# =========================================================
$manualUsernames = @(
    "fernando.guimaraes",
    "katia.fugita",
    "lilian.marques"
)

# =========================================================
# 2. SELEÇÃO POR ORGANIZATIONAL UNITS - OUs (Opção B)
# Preencha com os caminhos das OUs se quiser buscar automático.
# Se não for usar, deixe como está: @()
# =========================================================
$targetOUs = @(
    # "OU=Financeiro,OU=Usuarios,DC=seuDomain,DC=com",
    # "OU=Vendas,OU=Usuarios,DC=seuDomain,DC=com"
)

# Coleta usuários das OUs configuradas (se houver)
$ouUsernames = @()
foreach ($ou in $targetOUs) {
    try {
        $usersFromOU = Get-ADUser -SearchBase $ou -Filter * | Select-Object -ExpandProperty SamAccountName
        $ouUsernames += $usersFromOU
        Write-Log "Coletados $(($usersFromOU).Count) usuarios da OU: '$ou'" "INFO"
    }
    catch {
        Write-Log "Erro ao buscar usuarios na OU '$ou': $_" "ERROR"
    }
}

# Consolida todos os usuários sem duplicatas
$allUsers = ($manualUsernames + $ouUsernames) | Select-Object -Unique

# =========================================================
# CONFIGURAÇÃO DE LOGON HOURS (BLOQUEIO TOTAL / ALL DENY)
# =========================================================
# 21 bytes com valor 0 zeram a matriz (100% bloqueado/Denied)
$byteArray = [byte[]]@(0) * 21

# =========================================================
# APLICAÇÃO NO ACTIVE DIRECTORY
# =========================================================
$sucessos = 0
$erros = 0

foreach ($user in $allUsers) {
    try {
        Set-ADUser -Identity $user -Replace @{logonHours = $byteArray} -ErrorAction Stop
        Write-Log "Bloqueio total aplicado com sucesso para o usuario: '$user'" "SUCCESS"
        $sucessos++
    }
    catch {
        Write-Log "Falha ao aplicar alteracoes no usuario '$user': $_" "ERROR"
        $erros++
    }
}

Write-Log "Processo concluido. Sucessos: $sucessos | Falhas: $erros" "INFO"
Write-Log "Arquivo de log salvo em: $logPath" "INFO"