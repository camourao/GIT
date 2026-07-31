<#
.SINOPSE
    Script para verificar, baixar e instalar atualizações do Windows Server,
    registrando tudo em log, SEM reiniciar automaticamente o servidor.

.DESCRICAO
    Executa a verificação, download e instalação de atualizações do Windows Server 
    diretamente via PSWindowsUpdate, gravando o histórico em arquivo de log e 
    no Event Log do Windows.

.USO
    .\Atualizar-WindowsServer.ps1
    .\Atualizar-WindowsServer.ps1 -CaminhoLog "D:\Logs\WindowsUpdate.log"
#>

param(
    [string]$CaminhoLog = "C:\script_update\logs\SERVER_CRN_BKP_WindowsUpdate_Historico.log",
    [string]$NomeOrigemEventLog = "ScriptAtualizacaoWU"
)

$ErrorActionPreference = "Stop"
$DataHoraInicio = Get-Date

# ---------------------------------------------------------------------------
# 0. Preparação: pasta de log e Event Log
# ---------------------------------------------------------------------------
$PastaLog = Split-Path -Path $CaminhoLog -Parent
if (-not (Test-Path $PastaLog)) {
    New-Item -Path $PastaLog -ItemType Directory -Force | Out-Null
}

try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($NomeOrigemEventLog)) {
        New-EventLog -LogName Application -Source $NomeOrigemEventLog -ErrorAction SilentlyContinue
    }
} catch { }

function Registrar-Log {
    param(
        [string]$Mensagem,
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Nivel = "Information"
    )
    $linha = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Nivel, $Mensagem
    Add-Content -Path $CaminhoLog -Value $linha -Encoding UTF8
    Write-Host $linha -ForegroundColor $(
        switch ($Nivel) { "Error" { "Red" }; "Warning" { "Yellow" }; default { "Gray" } }
    )

    try {
        $tipoEvento = switch ($Nivel) {
            "Error"   { "Error" }
            "Warning" { "Warning" }
            default   { "Information" }
        }
        Write-EventLog -LogName Application -Source $NomeOrigemEventLog -EventId 1000 `
            -EntryType $tipoEvento -Message $Mensagem -ErrorAction SilentlyContinue
    } catch { }
}

Registrar-Log "===== Início da execução do script de atualização (usuário: $env:USERNAME) ====="

# ---------------------------------------------------------------------------
# 1. Importar Módulo PSWindowsUpdate
# ---------------------------------------------------------------------------
try {
    Import-Module PSWindowsUpdate -Force
}
catch {
    Registrar-Log "Falha ao carregar o módulo PSWindowsUpdate: $($_.Exception.Message)" -Nivel Error
    throw
}

# ---------------------------------------------------------------------------
# 2. Executar Busca, Download e Instalação de Atualizações
# ---------------------------------------------------------------------------
$ArquivoResultado = Join-Path $PastaLog ("WU_Resultado_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

Registrar-Log "Disparando verificação, download e instalação das atualizações pendentes..."
Registrar-Log "Aguarde... Este processo levará alguns minutos (devido às atualizações cumulativas de grande porte)."

try {
    # Executa a instalação direta de forma limpa
    $resultado = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -IgnoreReboot -AutoReboot:$false

    if ($resultado) {
        $resultado | Out-File -FilePath $ArquivoResultado -Encoding UTF8 -Force
        $resumoTexto = $resultado | Out-String
        Registrar-Log "Atualizações processadas com sucesso:`n$resumoTexto"
    }
    else {
        Registrar-Log "Nenhuma atualização pendente foi instalada ou servidor já está atualizado."
        "Nenhuma atualização pendente instalada." | Out-File -FilePath $ArquivoResultado -Encoding UTF8 -Force
    }
}
catch {
    Registrar-Log "Erro durante a instalação das atualizações: $($_.Exception.Message)" -Nivel Error
    "Erro: $($_.Exception.Message)" | Out-File -FilePath $ArquivoResultado -Encoding UTF8 -Force
}

# ---------------------------------------------------------------------------
# 3. Verificar se há reinicialização pendente (sem reiniciar)
# ---------------------------------------------------------------------------
$RebootPendente = $false
try {
    $RebootPendente = Get-WURebootStatus -Silent
} catch {
    $chavesReboot = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
    )
    foreach ($chave in $chavesReboot) {
        if (Test-Path $chave) { $RebootPendente = $true }
    }
}

if ($RebootPendente) {
    Registrar-Log "ATENÇÃO: Há reinicialização PENDENTE para concluir atualizações. O servidor NÃO foi reiniciado automaticamente." -Nivel Warning
}
else {
    Registrar-Log "Nenhuma reinicialização pendente detectada."
}

# ---------------------------------------------------------------------------
# 4. Atualizar status na interface gráfica (Server Manager / Settings)
# ---------------------------------------------------------------------------
try {
    Start-Process "usoclient.exe" -ArgumentList "RefreshSettings" -WindowStyle Hidden -Wait
    Registrar-Log "Status do Windows Update na interface gráfica atualizado (usoclient RefreshSettings)."
}
catch {
    Registrar-Log "Não foi possível atualizar o status na interface gráfica automaticamente: $($_.Exception.Message)" -Nivel Warning
}

$Duracao = (Get-Date) - $DataHoraInicio
Registrar-Log "===== Execução finalizada. Duração total: $($Duracao.ToString('hh\:mm\:ss')) ====="

Write-Host "`nResumo:" -ForegroundColor Cyan
Write-Host " - Log completo: $CaminhoLog"
Write-Host " - Arquivo de resultado: $ArquivoResultado"
Write-Host " - Reinicialização pendente: $RebootPendente"