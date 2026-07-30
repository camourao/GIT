# =========================================================================
# SCRIPT PARA TAREFA AGENDADA - Exchange Online App-Only
# =========================================================================

# -----------------------------------
# 1. CONFIGURAÇÃO DE LOG
# -----------------------------------

$ScriptDir = "C:\auditoria"

# Cria diretório caso não exista
if (-not (Test-Path $ScriptDir)) {
    New-Item -Path $ScriptDir -ItemType Directory | Out-Null
}

$LogFile = Join-Path -Path $ScriptDir -ChildPath "Log_CoordSupEnableRegraBloquearDisparoEmail_$((Get-Date).ToString('yyyyMMdd_HHmmss')).txt"

Start-Transcript -Path $LogFile -Append -Force
Write-Host "=== Início da Execução: $(Get-Date) ==="

# -----------------------------------
# 2. PREPARAÇÃO DO AMBIENTE
# -----------------------------------

try {
    # Permite execução apenas nesta sessão
    Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction Stop

    # Importa o módulo do Exchange
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
    Write-Host "Módulo ExchangeOnlineManagement carregado."
}
catch {
    Write-Error "Falha ao configurar ambiente: $($_.Exception.Message)"
    Stop-Transcript
    exit 1
}

# -----------------------------------
# 3. CONFIGURAÇÃO DO APP-ONLY
# -----------------------------------

# Preencha:
$TenantDomain = "crn3.org.br"  # Domínio do Tenant (não é GUID!)
$ClientID = "fcbe8bc8-ae43-4ce5-a28e-3246ded4d973"
$CertThumbprint = "62E1DCE226784599F868ACB64100D69D0CD48BD6"

# Confirmar se o certificado existe
try {
    $Cert = Get-ChildItem -Path "Cert:\LocalMachine\My\$CertThumbprint" -ErrorAction Stop
    Write-Host "Certificado encontrado: $($Cert.Subject)"
}
catch {
    Write-Error "❌ Certificado com thumbprint $CertThumbprint não encontrado no LocalMachine\My"
    Stop-Transcript
    exit 1
}

# -----------------------------------
# 4. CONEXÃO AO EXCHANGE ONLINE
# -----------------------------------

try {
    Write-Host "Conectando ao Exchange Online (App-Only)..."
    
    Connect-ExchangeOnline -AppId $ClientID `
        -CertificateThumbprint $CertThumbprint `
        -Organization "crn3.org.br" `
        -ShowBanner:$false `
        -ErrorAction Stop
    
    Write-Host "Conexão bem-sucedida."
}
catch {
    Write-Error "❌ Falha ao conectar ao Exchange Online: $($_.Exception.Message)"
    Stop-Transcript
    exit 1
}

# -----------------------------------
# 5. EXECUÇÃO DA AÇÃO (EXEMPLO)
# -----------------------------------

try {
    Write-Host "Habilitando regra de transporte: GRP_Email_Restricted_Coordenadores"

    Enable-TransportRule -Identity "GRP_Email_Restricted_Coordenadores" -Confirm:$false -ErrorAction Stop
    
    Write-Host "Regra habilitada com sucesso."
}
catch {
    Write-Error "❌ Erro ao habilitar a regra: $($_.Exception.Message)"
}

# -----------------------------------
# 6. FINALIZAÇÃO
# -----------------------------------

try {
    Write-Host "Desconectando..."
    Disconnect-ExchangeOnline -Confirm:$false
}
catch {
    Write-Host "Atenção: falha ao desconectar, mas não afeta a tarefa agendada."
}

Write-Host "=== Fim da Execução: $(Get-Date) ==="
Stop-Transcript

# =========================================================================
