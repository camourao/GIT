git# =========================================================================
# 1. Configuração do Logging
# =========================================================================

$ScriptDir = "C:\auditoria"

# Cria diretório se não existir
if (-not (Test-Path -Path $ScriptDir)) {
    New-Item -Path $ScriptDir -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path -Path $ScriptDir -ChildPath "Log_CoordSupDisableRegraBloquearDisparoEmail_$((Get-Date).ToString('yyyyMMdd_HHmmss')).txt"

Start-Transcript -Path $LogFile -Append -Force
Write-Host "--- Início da Execução $(Get-Date) ---"

# =========================================================================
# 2. Preparação do Ambiente
# =========================================================================

try {
    # Política somente para a sessão
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction Stop

    Write-Host "Importando módulo ExchangeOnlineManagement..."
    Import-Module ExchangeOnlineManagement -ErrorAction Stop

    Write-Host "Módulo ExchangeOnlineManagement carregado."
}
catch {
    Write-Error "Falha ao preparar ambiente: $($_.Exception.Message)"
    Stop-Transcript
    exit 1
}

# =========================================================================
# 3. Configuração APP-ONLY (Exchange Online)
# =========================================================================

# === AJUSTE SE NECESSÁRIO ===
$TenantDomain   = "crn3.org.br"
$ClientID       = "fcbe8bc8-ae43-4ce5-a28e-3246ded4d973"
$CertThumbprint = "62E1DCE226784599F868ACB64100D69D0CD48BD6"

# Validação do certificado
try {
    $Cert = Get-ChildItem -Path "Cert:\LocalMachine\My\$CertThumbprint" -ErrorAction Stop
    Write-Host "Certificado encontrado: $($Cert.Subject)"
}
catch {
    Write-Error "❌ Certificado $CertThumbprint não encontrado em LocalMachine\My"
    Stop-Transcript
    exit 1
}

# =========================================================================
# 4. Conexão ao Exchange Online (APP-ONLY)
# =========================================================================

try {
    Write-Host "Conectando ao Exchange Online (App-Only)..."

    Connect-ExchangeOnline `
        -AppId $ClientID `
        -CertificateThumbprint $CertThumbprint `
        -Organization $TenantDomain `
        -ShowBanner:$false `
        -ErrorAction Stop

    Write-Host "Conexão estabelecida com sucesso."
}
catch {
    Write-Error "❌ Falha ao conectar ao Exchange Online: $($_.Exception.Message)"
    Stop-Transcript
    exit 1
}

# =========================================================================
# 5. Execução da Ação
# =========================================================================

try {
    Write-Host "Desabilitando regra de transporte: GRP_Email_Restricted_Coordenadores"

    Disable-TransportRule `
        -Identity "GRP_Email_Restricted_Coordenadores" `
        -Confirm:$false `
        -ErrorAction Stop

    Write-Host "Regra desabilitada com sucesso."
}
catch {
    Write-Error "Erro ao desabilitar a regra de transporte: $($_.Exception.Message)"
}

# =========================================================================
# 6. Limpeza e Encerramento
# =========================================================================

try {
    Write-Host "Desconectando do Exchange Online..."
    Disconnect-ExchangeOnline -Confirm:$false
}
catch {
    Write-Host "Aviso: falha ao desconectar, não impacta a execução."
}

Write-Host "--- Fim da Execução $(Get-Date) ---"
Stop-Transcript
# =========================================================================
