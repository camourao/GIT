Import-Module ActiveDirectory

$username = "Services T I"

# =========================================================
# ALTERE AQUI OS DIAS E HORÁRIOS QUE DESEJA LIBERAR
# =========================================================
# Dias da semana (0 = Domingo, 1 = Segunda, 2 = Terça, 3 = Quarta, 4 = Quinta, 5 = Sexta, 6 = Sábado)
$daysAllowed = @(1, 2, 3, 4, 5) # Ex: Segunda a Sexta. Para incluir Sábado, use: @(1, 2, 3, 4, 5, 6)

# Horário de início e término (formato 24h)
$startHour = 8   # Ex: 8 para 08:00
$endHour   = 18  # Ex: 18 para 18:00 (o script liberará até 17:59)
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

# 5. Aplica ao usuário
Set-ADUser -Identity $username -Replace @{logonHours = $byteArray}