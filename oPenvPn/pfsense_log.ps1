<#
.SYNOPSIS
    Coleta e filtra todos os logs do OpenVPN no pfSense (sucesso e falha).
#>

# ==========================================
# Configurações
# ==========================================
$pfSenseIP  = "192.168.100.38"
$sshUser    = "admin"
$sshPort    = 22
$logRemote  = "/var/log/auth.log"

# Definindo o diretório de rede
$outputDir  = "\\192.168.100.34\Share\TI\Logs VPN"

# Gera a data do dia para compor o nome do arquivo (ex: openvpn_auth_logs_2026-07-30.txt)
$dateStamp  = Get-Date -Format "yyyy-MM-dd"
$fileName   = "openvpn_auth_logs_$dateStamp.txt"

# Caminho final completo
$outputFile = Join-Path -Path $outputDir -ChildPath $fileName

# ==========================================
# Execução da Coleta
# ==========================================

Write-Host "Conectando ao pfSense ($pfSenseIP) para coletar os logs do OpenVPN..." -ForegroundColor Cyan

# Busca TODAS as linhas contendo 'openvpn' (sucessos, falhas, erros de senha, conexões, etc)
$remoteCommand = "grep -i 'openvpn' $logRemote"

try {
    # Garante que o diretório de destino na rede existe antes de salvar
    if (-not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    # Opções do SSH
    $sshOpts = @("-o", "StrictHostKeyChecking=accept-new")
    
    # Executa a coleta via SSH
    $logs = ssh $sshOpts -p $sshPort "${sshUser}@${pfSenseIP}" $remoteCommand

    if ($logs) {
        # Salva o arquivo com a data do dia
        Set-Content -LiteralPath $outputFile -Value $logs -Encoding UTF8
        
        Write-Host "Sucesso! $(($logs | Measure-Object).Count) registros encontrados." -ForegroundColor Green
        Write-Host "Logs salvos em: $outputFile" -ForegroundColor Yellow

        Write-Host "`n--- Últimas 10 entradas do OpenVPN ---" -ForegroundColor Cyan
        $logs | Select-Object -Last 300
    } else {
        Write-Host "Nenhum registro do OpenVPN foi encontrado em $logRemote." -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Falha ao coletar os logs do pfSense: $_"
}