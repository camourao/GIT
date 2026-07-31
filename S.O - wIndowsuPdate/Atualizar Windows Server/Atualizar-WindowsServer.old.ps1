<#
.SINOPSE
    Script para verificar, baixar e instalar atualizações do Windows Server,
    registrando tudo em log, SEM reiniciar automaticamente o servidor.

.DESCRIÇÃO
    Este script foi desenhado especificamente para contornar o problema de
    "Access is denied (0x80070005)" que ocorre ao chamar Get-WindowsUpdate
    diretamente numa sessão RDP/remota. Ele usa Invoke-WuJob (PSWindowsUpdate),
    que executa a operação através de uma tarefa agendada local, evitando essa
    limitação da API COM do Windows Update Agent.

    Ao final:
      - Gera um log em arquivo (histórico cumulativo, uma linha por execução)
      - Registra um evento no Visualizador de Eventos do Windows (Event Log),
        para fins de auditoria/rastreabilidade de quem/quando rodou
      - Atualiza o status do Windows Update na interface gráfica (Server
        Manager / Configurações), para não ficar com informação desatualizada
      - NÃO reinicia o servidor, mesmo que existam atualizações pendentes de
        reboot — apenas avisa que há reinicialização pendente

.REQUISITOS
    - Módulo PSWindowsUpdate instalado (o script instala automaticamente se
      não encontrar)
    - Executar como Administrador
    - Executar localmente no servidor (via RDP/console), não via WinRM remoto
      de outra máquina

.USO
    .\Atualizar-WindowsServer.ps1
    .\Atualizar-WindowsServer.ps1 -CaminhoLog "D:\Logs\WindowsUpdate.log"
#>

param(
    [string]$CaminhoLog = "C:\Logs\WindowsUpdate_Historico.log",
    [string]$NomeOrigemEventLog = "ScriptAtualizacaoWU"
)

$ErrorActionPreference = "Stop"
$DataHoraInicio = Get-Date

# ---------------------------------------------------------------------------
# 0. Preparação: pasta de log e Event Log customizado
# ---------------------------------------------------------------------------
$PastaLog = Split-Path -Path $CaminhoLog -Parent
if (-not (Test-Path $PastaLog)) {
    New-Item -Path $PastaLog -ItemType Directory -Force | Out-Null
}

if (-not [System.Diagnostics.EventLog]::SourceExists($NomeOrigemEventLog)) {
    New-EventLog -LogName Application -Source $NomeOrigemEventLog
}

function Registrar-Log {
    param(
        [string]$Mensagem,
        [ValidateSet("Information", "Warning", "Error")]
        [string]$Nivel = "Information"
    )
    $linha = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Nivel, $Mensagem
    Add-Content -Path $CaminhoLog -Value $linha
    Write-Host $linha -ForegroundColor $(
        switch ($Nivel) { "Error" { "Red" }; "Warning" { "Yellow" }; default { "Gray" } }
    )

    $tipoEvento = switch ($Nivel) {
        "Error"   { "Error" }
        "Warning" { "Warning" }
        default   { "Information" }
    }
    Write-EventLog -LogName Application -Source $NomeOrigemEventLog -EventId 1000 `
        -EntryType $tipoEvento -Message $Mensagem
}

Registrar-Log "===== Início da execução do script de atualização (usuário: $env:USERNAME) ====="

# ---------------------------------------------------------------------------
# 1. Garantir que o módulo PSWindowsUpdate está disponível
# ---------------------------------------------------------------------------
try {
    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        Registrar-Log "Módulo PSWindowsUpdate não encontrado. Instalando..."
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        Install-Module -Name PSWindowsUpdate -Force -Confirm:$false
    }
    Import-Module PSWindowsUpdate
}
catch {
    Registrar-Log "Falha ao preparar o módulo PSWindowsUpdate: $($_.Exception.Message)" -Nivel Error
    throw
}

# ---------------------------------------------------------------------------
# 2. Habilitar o mecanismo de execução via tarefa agendada (contorna RDP)
# ---------------------------------------------------------------------------
try {
    Enable-WURemoting -Confirm:$false | Out-Null
}
catch {
    Registrar-Log "Aviso ao habilitar WURemoting (pode já estar habilitado): $($_.Exception.Message)" -Nivel Warning
}

# ---------------------------------------------------------------------------
# 3. Executar a instalação das atualizações via Invoke-WuJob
#    -IgnoreReboot: instala tudo que não exige reinício automático imediato,
#    mas NÃO reinicia o servidor mesmo que alguma atualização precise disso.
# ---------------------------------------------------------------------------
$ArquivoResultado = Join-Path $PastaLog ("WU_Resultado_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

Registrar-Log "Disparando verificação e instalação de atualizações (sem reinicialização automática)..."

try {
    # IMPORTANTE: Invoke-WuJob não roda em uma sessão de remoting real (não suporta $using:),
    # ele serializa o script como texto e executa via tarefa agendada local. Por isso o
    # caminho do arquivo de resultado precisa ser embutido como texto literal aqui.
    $TextoScript = @"
Import-Module PSWindowsUpdate
Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -IgnoreReboot -Verbose *>&1 | Out-File -FilePath '$ArquivoResultado' -Encoding UTF8
"@
    $BlocoScript = [scriptblock]::Create($TextoScript)

    Invoke-WuJob -ComputerName $env:COMPUTERNAME -Script $BlocoScript -RunNow -Confirm:$false | Out-Null
}
catch {
    Registrar-Log "Falha ao disparar o job de atualização: $($_.Exception.Message)" -Nivel Error
    throw
}

# ---------------------------------------------------------------------------
# 4. Aguardar a tarefa agendada concluir (checa status periodicamente)
# ---------------------------------------------------------------------------
$TentativasMax = 60   # 60 x 10s = até 10 minutos de espera
$Tentativa = 0
$Concluido = $false

do {
    Start-Sleep -Seconds 10
    $Tentativa++
    $infoTarefa = Get-ScheduledTask -TaskName "PSWindowsUpdate" -ErrorAction SilentlyContinue |
        Get-ScheduledTaskInfo -ErrorAction SilentlyContinue

    if ($infoTarefa -and $infoTarefa.LastTaskResult -ne 267009) {
        # 267009 = tarefa ainda em execução
        $Concluido = $true
    }
} while (-not $Concluido -and $Tentativa -lt $TentativasMax)

if (-not $Concluido) {
    Registrar-Log "A tarefa de atualização não confirmou conclusão dentro do tempo esperado. Verifique manualmente o arquivo: $ArquivoResultado" -Nivel Warning
}
elseif ($infoTarefa.LastTaskResult -ne 0) {
    Registrar-Log "A tarefa de atualização terminou com código de retorno $($infoTarefa.LastTaskResult) (diferente de sucesso)." -Nivel Warning
}
else {
    Registrar-Log "Tarefa de atualização concluída com sucesso."
}

# ---------------------------------------------------------------------------
# 5. Ler e registrar o resultado das atualizações instaladas
# ---------------------------------------------------------------------------
if (Test-Path $ArquivoResultado) {
    $conteudo = Get-Content $ArquivoResultado -Raw
    if ([string]::IsNullOrWhiteSpace($conteudo)) {
        Registrar-Log "Nenhuma atualização pendente encontrada. Servidor já está em dia."
    }
    else {
        Registrar-Log "Resultado da instalação:`n$conteudo"
    }
}
else {
    Registrar-Log "Arquivo de resultado não foi gerado ($ArquivoResultado). Pode indicar falha silenciosa no job." -Nivel Warning
}

# ---------------------------------------------------------------------------
# 6. Verificar se há reinicialização pendente (mas NÃO reiniciar)
# ---------------------------------------------------------------------------
$RebootPendente = $false
$chavesReboot = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"
)
foreach ($chave in $chavesReboot) {
    if (Test-Path $chave) { $RebootPendente = $true }
}

if ($RebootPendente) {
    Registrar-Log "ATENÇÃO: há reinicialização PENDENTE para concluir a instalação de uma ou mais atualizações. O servidor NÃO foi reiniciado automaticamente, conforme configurado." -Nivel Warning
}
else {
    Registrar-Log "Nenhuma reinicialização pendente detectada."
}

# ---------------------------------------------------------------------------
# 7. Atualizar o status exibido na interface gráfica (Server Manager /
#    Configurações), para refletir que a checagem/instalação acabou de rodar
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
Write-Host " - Resultado detalhado desta execução: $ArquivoResultado"
Write-Host " - Reinicialização pendente: $RebootPendente"
Write-Host " - Consulte também: Visualizador de Eventos > Aplicativos > Origem '$NomeOrigemEventLog'"
