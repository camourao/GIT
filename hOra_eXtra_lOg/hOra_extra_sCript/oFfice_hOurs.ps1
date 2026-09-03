Import-Module ActiveDirectory

# =========================================================
# CONFIGURAÇÃO DE LOGS
# =========================================================
$logPath = "C:\hOra_eXtra_lOg\oFfice_hOurs_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$logDir = Split-Path -Path $logPath -Parent

# Garante a criação do diretório de log se não existir
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
    
    # Exibe no console
    switch ($Type) {
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "ERROR"   { Write-Host $logEntry -ForegroundColor Red }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        default   { Write-Host $logEntry -ForegroundColor Cyan }
    }
    
    # Escreve no arquivo de log (força encoding UTF8 para evitar falhas)
    Add-Content -Path $logPath -Value $logEntry -Encoding UTF8
}

Write-Log "Iniciando processo de atualizacao do LogonHours..." "INFO"

# =========================================================
# LISTA DE USUÁRIOS
# =========================================================
$usernames = @(
    "fernando.guimaraes",
    "katia.fugita",
    "lilian.marques"
    
)

# =========================================================
# CONFIGURAÇÃO DE DIAS E HORÁRIOS
# =========================================================
# Dias (0 = Domingo, 1 = Segunda, ..., 6 = Sábado)
$daysAllowed = @(1, 2, 3, 4, 5)

# Horário (formato 24h)
$startHour = 0   # 10:00
$endHour   = 0   # Liberado até 21:59
# =========================================================

# 1. Cria a matriz de 168 horas zerada
$hoursInWeek = New-Object 'byte[]' 168

# 2. Preenche os dias e horas configurados
foreach ($day in $daysAllowed) {
    for ($hour = $startHour; $hour -lt $endHour; $hour++) {
        $index = ($day * 24) + $hour
        $hoursInWeek[$index] = 1
    }
}

# 3. Ajusta o Fuso Horário Local para UTC
$timeZoneOffset = [TimeZoneInfo]::Local.GetUtcOffset([DateTime]::Now).Hours
$hoursInWeekUTC = New-Object 'byte[]' 168

for ($i = 0; $i -lt 168; $i++) {
    if ($hoursInWeek[$i] -eq 1) {
        $utcIndex = ($i - $timeZoneOffset + 168) % 168
        $hoursInWeekUTC[$utcIndex] = 1
    }
}

# 4. Converte em array de bytes do Active Directory
$byteArray = New-Object 'byte[]' 21
for ($i = 0; $i -lt 168; $i++) {
    if ($hoursInWeekUTC[$i] -eq 1) {
        $byteIndex = [math]::Floor($i / 8)
        $bitIndex = $i % 8
        $byteArray[$byteIndex] = $byteArray[$byteIndex] -bor ([byte][math]::Pow(2, $bitIndex))
    }
}

# 5. Loop para aplicar a todos os usuários da lista
$sucessos = 0
$erros = 0

foreach ($user in $usernames) {
    try {
        Set-ADUser -Identity $user -Replace @{logonHours = $byteArray} -ErrorAction Stop
        Write-Log "Horario configurado com sucesso para o usuario: '$user'" "SUCCESS"
        $sucessos++
    }
    catch {
        Write-Log "Falha ao aplicar alteracoes no usuario '$user': $_" "ERROR"
        $erros++
    }
}

Write-Log "Processo concluido. Sucessos: $sucessos | Falhas: $erros" "INFO"
Write-Log "Arquivo de log salvo em: $logPath" "INFO"