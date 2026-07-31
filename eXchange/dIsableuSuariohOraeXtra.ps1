# =========================================================================
# SCRIPT PARA TAREFA AGENDADA - Adicionar Usuários ao Grupo de Bloqueio
# Exchange Online App-Only
# =========================================================================

# -----------------------------------
# 0. PARÂMETROS DA EXCEÇÃO
# -----------------------------------
$GrupoBloqueioIdentity = "GRP_Email_Restricted_Demais"
$UsuariosExcecao       = @(
    "cassia.machado@crn3.org.br",
    "conceicao.veras@crn3.org.br",
    "denise.silveira@crn3.org.br",
    "franciele.brito@crn3.org.br",
    "rejane.araujo@crn3.org.br"
)

# -----------------------------------
# 1. CONFIGURAÇÃO DE LOG
# -----------------------------------
$ScriptDir = "C:\auditoria"

if (-not (Test-Path -Path $ScriptDir)) {
    New-Item -Path $ScriptDir -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path -Path $ScriptDir -ChildPath "Log_AdicionarUsuariosGrupoBloqueio_$((Get-Date).ToString('yyyyMMdd_HHmmss')).txt"

Start-Transcript -Path $LogFile -Append -Force
Write-Host "--- Início da Execução $(Get-Date) ---"

# -----------------------------------
# 2. PREPARAÇÃO DO AMBIENTE
# -----------------------------------
try {
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

# -----------------------------------
# 3. CONFIGURAÇÃO APP-ONLY
# -----------------------------------
$TenantDomain   = "crn3.org.br"
$ClientID       = "fcbe8bc8-ae43-4ce5-a28e-3246ded4d973"
$CertThumbprint = "62E1DCE226784599F868ACB64100D69D0CD48BD6"

try {
    $Cert = Get-ChildItem -Path "Cert:\LocalMachine\My\$CertThumbprint" -ErrorAction Stop
    Write-Host "Certificado encontrado: $($Cert.Subject)"
}
catch {
    Write-Error "❌ Certificado $CertThumbprint não encontrado em LocalMachine\My"
    Stop-Transcript
    exit 1
}

# -----------------------------------
# 4. CONEXÃO AO EXCHANGE ONLINE
# -----------------------------------
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

# -----------------------------------
# 5. EXECUÇÃO DA AÇÃO (ADICIONAR AO GRUPO)
# -----------------------------------
try {
    Write-Host "Iniciando inclusão dos usuários de volta ao grupo '$GrupoBloqueioIdentity'..."

    foreach ($User in $UsuariosExcecao) {
        $CleanUser = $User.Trim().TrimEnd(',')

        try {
            Add-DistributionGroupMember `
                -Identity $GrupoBloqueioIdentity `
                -Member $CleanUser `
                -BypassSecurityGroupManagerCheck `
                -ErrorAction Stop

            Write-Host " [SUCESSO] Usuário $CleanUser inserido no grupo (Voltou a ser bloqueado)." -ForegroundColor Green
        }
        catch {
            Write-Host " [AVISO/ERRO] Não foi possível adicionar ${CleanUser}: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Error "Erro ao processar adição dos usuários: $($_.Exception.Message)"
}

# -----------------------------------
# 6. LIMPEZA E ENCERRAMENTO
# -----------------------------------
try {
    Write-Host "Desconectando do Exchange Online..."
    Disconnect-ExchangeOnline -Confirm:$false
}
catch {
    Write-Host "Aviso: falha ao desconectar, não impacta a execução."
}

Write-Host "--- Fim da Execução $(Get-Date) ---"
Stop-Transcript