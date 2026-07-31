<#
.SINOPSE
    Script para verificar, baixar e instalar atualizações do Windows Server,
    registrando tudo em log, SEM reiniciar automaticamente o servidor.

.DESCRIÇÃO
    Garante a execução local das APIs do Windows Update criando nativamente uma
    Tarefa Agendada temporária configurada no escopo de NT AUTHORITY\SYSTEM.
    Isso elimina o erro de código de retorno 1 e contorna restrições de WinRM/RDP.
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
# 2. Preparação do Job Nativo via Agendador de Tarefas do Windows
# ---------------------------------------------------------------------------
$NomeTarefa = "Script_Update_Nativo_WU"
$ArquivoResultado = Join-Path $PastaLog ("WU_Resultado_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

# Remove resquícios de tarefas anteriores se houver falha prévia
if (Get-ScheduledTask -TaskName $NomeTarefa -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $NomeTarefa -Confirm:$false | Out-Null
}

Registrar-Log "Criando e disparando tarefa agendada nativa local sob privilégios do SYSTEM..."

# Monta o comando PowerShell em texto plano que a tarefa agendada executará localmente
$ScriptComando = "Import-Module PSWindowsUpdate; Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -IgnoreReboot -Verbose *>&1 | Out-File -FilePath '$ArquivoResultado' -Encoding UTF8"
$B64Comando = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($ScriptComando))

try {
    # Define os parâmetros para forçar a execução imediata sob a conta máxima (SYSTEM)
    $Acao = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $B64Comando"
    $Principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $Config = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    $Tarefa = Register-ScheduledTask -TaskName $NomeTarefa -Action $Acao -Principal $Principal -Settings $Config -ErrorAction Stop
    $Tarefa | Start-ScheduledTask | Out-Null
}
catch {
    Registrar-Log "Falha ao registrar/disparar a tarefa agendada nativa: $($_.Exception.Message)" -Nivel Error
    throw
}

# ---------------------------------------------------------------------------
# 3. Aguardar a execução da Tarefa Agendada nativa
# ---------------------------------------------------------------------------
$TentativasMax = 180   # 180 x 10s = Até 30 minutos de tempo limite para grandes atualizações
$Tentativa = 0
$Concluido = $false

do {
    Start-Sleep -Seconds 10
    $Tentativa++
    $infoTarefa = Get-ScheduledTask -TaskName $NomeTarefa -ErrorAction SilentlyContinue

    if ($infoTarefa.State -ne "Running") {
        $Concluido = $true
    }
} while (-not $Concluido -and $Tentativa -lt $TentativasMax)

# Coleta o resultado final da tarefa agendada antes de deletá-la
$InfoResultado = Get-ScheduledTask -TaskName $NomeTarefa | Get-ScheduledTaskInfo
$CodigoRetorno = $InfoResultado.LastTaskResult

# Limpa a tarefa agendada do sistema
Unregister-ScheduledTask -TaskName $NomeTarefa -Confirm:$false | Out-Null

if (-not $Concluido) {
    Registrar-Log "A tarefa de atualização atingiu o tempo limite. Verifique o arquivo: $ArquivoResultado" -Nivel Warning
}
elseif ($CodigoRetorno -ne 0) {
    Registrar-Log "A tarefa de atualização terminou com código de retorno $CodigoRetorno (diferente de sucesso)." -Nivel Warning
}
else {
    Registrar-Log "Tarefa de atualização concluída com sucesso."
}

# ---------------------------------------------------------------------------
# 4. Ler e registrar o resultado das atualizações instaladas
# ---------------------------------------------------------------------------
if (Test-Path $ArquivoResultado) {
    $conteudo = Get-Content $ArquivoResultado -Raw
    if ([string]::IsNullOrWhiteSpace($conteudo) -or $conteudo -match "Found \[0\] Updates") {
        Registrar-Log "Nenhuma atualização pendente instalada. O servidor já está em dia."
    }
    else {
        Registrar-Log "Resultado detalhado da instalação encontrada:`n$conteudo"
    }
}
else {
    Registrar-Log "Arquivo de resultado não foi gerado ($ArquivoResultado). Verifique o Visualizador de Eventos." -Nivel Warning
}

# ---------------------------------------------------------------------------
# 5. Verificar se há reinicialização pendente (mas NÃO reiniciar)
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
    Registrar-Log "ATENÇÃO: há reinicialização PENDENTE para concluir a instalação. O servidor NÃO foi reiniciado automaticamente." -Nivel Warning
}
else {
    Registrar-Log "Nenhuma reinicialização pendente detectada."
}

# ---------------------------------------------------------------------------
# 6. Atualizar o status exibido na interface gráfica
# ---------------------------------------------------------------------------
try {
    Start-Process "usoclient.exe" -ArgumentList "RefreshSettings" -WindowStyle Hidden -Wait
    Registrar-Log "Status do Windows Update na interface gráfica atualizado."
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