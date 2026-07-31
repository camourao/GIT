<#
    Verificar-AtualizacoesPendentes-v7.ps1

    Objetivo: Verificar (SEM INSTALAR) se cada servidor da lista possui
    atualizacoes do Windows Server pendentes.
    Ajustes v7: 
    - Corrigido bug onde .Count ficava em branco ao retornar apenas 1 KB.
    - Ignora vacina diaria do Defender (KB2267602) por padrao para evitar falsos positivos.
#>

param(
    [Parameter(Mandatory=$false)]
    [PSCredential]$Credential,
    
    [Parameter(Mandatory=$false)]
    [string]$DomainSuffix = "crn3.sp",

    [Parameter(Mandatory=$false)]
    [bool]$IgnoreDefender = $true
)

# Lista de IPs dos servidores
$serverNames = @(
    "192.168.100.30",
    "192.168.100.31",
    "192.168.100.32",
    "192.168.100.33",
    "192.168.100.34",
    "192.168.100.100",
    "192.168.100.200",
    "192.168.100.16",
    "192.168.100.17",
    "192.168.100.18",
    "192.168.100.19"
)

# Pasta/arquivos de log centralizados na maquina onde o script roda
$logFolder  = "C:\Logs"
if (-not (Test-Path $logFolder)) { New-Item -Path $logFolder -ItemType Directory -Force | Out-Null }
$logPath    = Join-Path $logFolder "VerificacaoAtualizacoes_Historico.log"
$reportPath = Join-Path $logFolder "VerificacaoAtualizacoes_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $Message"
    $line | Out-File -FilePath $logPath -Append -Encoding UTF8
    Write-Host $line -ForegroundColor $Color
}

$resultadosFinais = @()

Write-Log "===== INICIO DA VERIFICACAO DE ATUALIZACOES PENDENTES =====" "Yellow"

foreach ($name in $serverNames) {
    # Se for um IP valido, usa o IP puro. Caso contrario, monta com o FQDN.
    $server = if ($name -match '^\d{1,3}(\.\d{1,3}){3}$') { $name } elseif ($name -like "*.*") { $name } else { "$name.$DomainSuffix" }
    
    Write-Host "`n--- Verificando: $server ---" -ForegroundColor Cyan
    
    $item = [PSCustomObject]@{
        Servidor         = $server
        Status           = "N/A"
        QtdPendentes     = 0
        KBsPendentes     = ""
        DataVerificacao  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Observacao       = ""
    }

    try {
        # 1. Teste de Conectividade via PING (ICMP)
        if (-not (Test-Connection -ComputerName $server -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
            $item.Status     = "OFFLINE"
            $item.Observacao = "Sem resposta de Ping (ICMP). Servidor desligado ou bloqueado por Firewall."
            Write-Log "$server -> OFFLINE (Ping)" "DarkYellow"
            $resultadosFinais += $item
            continue
        }

        # 2. Execucao do Comando Remoto
        $invokeParams = @{
            ComputerName = $server
            ErrorAction  = "Stop"
            ScriptBlock  = {
                param($IgnoreDef)
                
                # Garante que o NuGet e o PSWindowsUpdate existam sem travar a sessao
                if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                    Install-Module PSWindowsUpdate -Force -AcceptLicense -Scope CurrentUser -ErrorAction Stop | Out-Null
                }
                
                Import-Module PSWindowsUpdate -ErrorAction Stop
                $updates = Get-WindowsUpdate -MicrosoftUpdate -Verbose:$false -ErrorAction Stop
                
                # Filtra o Defender se a flag estiver ativa
                if ($IgnoreDef) {
                    $updates = $updates | Where-Object { $_.KB -ne 'KB2267602' -and $_.Title -notlike "*Defender*" }
                }

                if ($null -eq $updates) { 
                    return @() 
                } else { 
                    return @($updates) | Select-Object KB, Title 
                }
            }
            ArgumentList = $IgnoreDefender
        }

        if ($null -ne $Credential) { $invokeParams.Add("Credential", $Credential) }

        # Executa no servidor remoto e garante conversao explicita em Array @()
        $updatesRemotos = @(Invoke-Command @invokeParams)

        # 3. Processamento do Retorno
        if ($null -eq $updatesRemotos -or $updatesRemotos.Count -eq 0) {
            $item.Status     = "ATUALIZADO"
            $item.Observacao = "Nenhuma atualizacao pendente encontrada."
            Write-Log "$server -> ATUALIZADO" "Green"
        } else {
            $item.Status        = "DESATUALIZADO"
            $item.QtdPendentes  = $updatesRemotos.Count
            $item.KBsPendentes  = ($updatesRemotos | ForEach-Object { $_.KB }) -join "; "
            $item.Observacao    = "Existem $($updatesRemotos.Count) atualizacao(oes) pendente(s)."
            Write-Log "$server -> DESATUALIZADO ($($item.QtdPendentes) KBs)" "Red"
        }

    } catch {
        $item.Status     = "ERRO"
        $msg = $_.Exception.Message
        if ($msg -like "*Access is denied*" -or $msg -like "*Acesso negado*") {
            $item.Observacao = "Acesso Negado. Rode como Admin do Dominio ou use -Credential."
        } else {
            $item.Observacao = "Erro: $msg"
        }
        Write-Log "$server -> ERRO: $($item.Observacao)" "Magenta"
    }

    $resultadosFinais += $item
}

# Geracao do Relatorio TXT
$reportLines = @()
$reportLines += "===================================================="
$reportLines += " RELATORIO DE VERIFICACAO DE ATUALIZACOES PENDENTES"
$reportLines += " Gerado em: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportLines += "===================================================="
$reportLines += ""

foreach ($r in $resultadosFinais) {
    $reportLines += "Servidor         : $($r.Servidor)"
    $reportLines += "Status           : $($r.Status)"
    $reportLines += "Qtd. Pendentes   : $($r.QtdPendentes)"
    if ($r.KBsPendentes) { $reportLines += "KBs Pendentes    : $($r.KBsPendentes)" }
    $reportLines += "Data Verificacao : $($r.DataVerificacao)"
    $reportLines += "Observacao       : $($r.Observacao)"
    $reportLines += "----------------------------------------------------"
}

$resumo = @{
    Total    = $resultadosFinais.Count
    Desat    = (@($resultadosFinais | Where-Object { $_.Status -eq 'DESATUALIZADO' })).Count
    Atua     = (@($resultadosFinais | Where-Object { $_.Status -eq 'ATUALIZADO' })).Count
    Off      = (@($resultadosFinais | Where-Object { $_.Status -eq 'OFFLINE' })).Count
    Erro     = (@($resultadosFinais | Where-Object { $_.Status -eq 'ERRO' })).Count
}

$reportLines += ""
$reportLines += "===== RESUMO ====="
$reportLines += "Total de servidores verificados : $($resumo.Total)"
$reportLines += "Desatualizados                   : $($resumo.Desat)"
$reportLines += "Atualizados                      : $($resumo.Atua)"
$reportLines += "Offline                          : $($resumo.Off)"
$reportLines += "Erro                             : $($resumo.Erro)"

$reportLines | Out-File -FilePath $reportPath -Encoding UTF8

Write-Log "===== FIM DA VERIFICACAO =====" "Yellow"
Write-Host "`nRelatorio gerado em: $reportPath" -ForegroundColor Cyan