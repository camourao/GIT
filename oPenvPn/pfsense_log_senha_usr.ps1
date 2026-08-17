<#
.SYNOPSIS
    Coleta e filtra todos os logs do OpenVPN no pfSense (sucesso e falha).
#>

# ==========================================
# Configurações
# ==========================================
$pfSenseIP   = "192.168.100.38"
$sshUser     = "admin"
$sshPass     = "Vp9w2TEXi5p5g3W30Hzu"  # <--- Insira a senha SSH do pfSense

$logRemote   = "/var/log/auth.log"

# Credenciais do Compartilhamento de Rede
$shareUser   = "services_ti@crn3.org.br"
$sharePass   = "mudar@123"

# Definindo o diretório de rede
$outputDir   = "\\192.168.100.34\Share\TI\Logs VPN"

# Gera a data do dia para compor o nome do arquivo
$dateStamp   = Get-Date -Format "yyyy-MM-dd"
$fileName    = "openvpn_auth_logs_$dateStamp.txt"

# Caminho final completo
$outputFile  = Join-Path -Path $outputDir -ChildPath $fileName

# ==========================================
# Execução da Coleta
# ==========================================

# 1. Carregar/Instalar módulo Posh-SSH
if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    Write-Host "Instalando módulo Posh-SSH..." -ForegroundColor Yellow
    Install-Module -Name Posh-SSH -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
}
Import-Module Posh-SSH -ErrorAction SilentlyContinue

# 2. Autenticação no Compartilhamento de Rede (SMB)
try {
    Write-Host "Autenticando no compartilhamento de rede..." -ForegroundColor Cyan
    Remove-SmbMapping -RemotePath "\\192.168.100.34\Share" -Force -ErrorAction SilentlyContinue
    
    $secSharePass = ConvertTo-SecureString $sharePass -AsPlainText -Force
    $shareCred = New-Object System.Management.Automation.PSCredential($shareUser, $secSharePass)
    New-SmbMapping -RemotePath "\\192.168.100.34\Share" -Credential $shareCred -ErrorAction Stop | Out-Null
    
    if (-not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
} catch {
    Write-Error "Falha ao autenticar no compartilhamento de rede: $_"
    exit 1
}

# 3. Conexão SSH e Coleta de Logs no pfSense
Write-Host "Conectando ao pfSense ($pfSenseIP) para coletar os logs do OpenVPN..." -ForegroundColor Cyan

$remoteCommand = "grep -i 'openvpn' $logRemote"

try {
    # Converte a senha do SSH
    $secSshPass = ConvertTo-SecureString $sshPass -AsPlainText -Force
    $sshCred = New-Object System.Management.Automation.PSCredential($sshUser, $secSshPass)

    # Cria a sessão SSH
    $session = New-SSHSession -ComputerName $pfSenseIP -Credential $sshCred -AcceptKey -ErrorAction Stop
    
    # Executa o comando remoto
    $result = Invoke-SSHCommand -SSHSession $session -Command $remoteCommand
    $logs = $result.Output

    if ($logs) {
        # Salva o arquivo na rede
        $logs | Out-File -FilePath $outputFile -Encoding UTF8 -Force
        
        Write-Host "Sucesso! $(($logs | Measure-Object).Count) registros encontrados." -ForegroundColor Green
        Write-Host "Logs salvos em: $outputFile" -ForegroundColor Yellow

        Write-Host "`n--- Últimas 300 entradas do OpenVPN ---" -ForegroundColor Cyan
        $logs | Select-Object -Last 300
    } else {
        Write-Host "Nenhum registro do OpenVPN foi encontrado em $logRemote." -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Falha ao coletar os logs do pfSense: $_"
}
finally {
    if ($session) {
        Remove-SSHSession -SSHSession $session -ErrorAction SilentlyContinue | Out-Null
    }
}