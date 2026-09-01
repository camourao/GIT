Import-Module ActiveDirectory

# =========================================================
# LISTA DE USUÁRIOS (pode estar em OUs diferentes)
# =========================================================
$usernames = @(
    "services_ti"
    #"luis.andrade"
    
)

# =========================================================
# CONFIGURAÇÃO DE DIAS E HORÁRIOS
# =========================================================
# Dias (0 = Domingo, 1 = Segunda, ..., 6 = Sábado)
$daysAllowed = @(1, 2, 3, 4, 5) 

# Horário (formato 24h)
$startHour = 8   # 08:00
$endHour   = 24  # Liberado até 16:59 (para liberar até 17:59, use 18)
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
foreach ($user in $usernames) {
    try {
        Set-ADUser -Identity $user -Replace @{logonHours = $byteArray} -ErrorAction Stop
        Write-Host "Horário configurado com sucesso para: $user" -ForegroundColor Green
    }
    catch {
        Write-Host "Erro ao aplicar no usuário '$user': $_" -ForegroundColor Red
    }
}