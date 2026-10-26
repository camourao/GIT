Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# =========================================================
# CRIAÇÃO DA JANELA PRINCIPAL
# =========================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Gestão de LogonHours - Active Directory"
$form.Size = New-Object System.Drawing.Size(650, 720)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# ---------------------------------------------------------
# 1. SEÇÃO DE MODO DE OPERAÇÃO
# ---------------------------------------------------------
$groupBoxMode = New-Object System.Windows.Forms.GroupBox
$groupBoxMode.Location = New-Object System.Drawing.Point(15, 15)
$groupBoxMode.Size = New-Object System.Drawing.Size(605, 80)
$groupBoxMode.Text = " 1. Selecione a Ação / Modo "

$radioBloqueioTotal = New-Object System.Windows.Forms.RadioButton
$radioBloqueioTotal.Location = New-Object System.Drawing.Point(20, 30)
$radioBloqueioTotal.Size = New-Object System.Drawing.Size(250, 25)
$radioBloqueioTotal.Text = "Bloqueio Total (All Deny)"
$radioBloqueioTotal.Checked = $true
$groupBoxMode.Controls.Add($radioBloqueioTotal)

$radioHorarioPersonalizado = New-Object System.Windows.Forms.RadioButton
$radioHorarioPersonalizado.Location = New-Object System.Drawing.Point(290, 30)
$radioHorarioPersonalizado.Size = New-Object System.Drawing.Size(280, 25)
$radioHorarioPersonalizado.Text = "Horário Personalizado (Dias/Horas)"
$groupBoxMode.Controls.Add($radioHorarioPersonalizado)

$form.Controls.Add($groupBoxMode)

# ---------------------------------------------------------
# 2. SEÇÃO DE CONFIGURAÇÃO DE HORÁRIOS (Dinâmica)
# ---------------------------------------------------------
$groupBoxTime = New-Object System.Windows.Forms.GroupBox
$groupBoxTime.Location = New-Object System.Drawing.Point(15, 105)
$groupBoxTime.Size = New-Object System.Drawing.Size(605, 110)
$groupBoxTime.Text = " 2. Parâmetros de Horário (Apenas se personalizado) "
$groupBoxTime.Enabled = $false

$labelDays = New-Object System.Windows.Forms.Label
$labelDays.Location = New-Object System.Drawing.Point(20, 30)
$labelDays.Size = New-Object System.Drawing.Size(120, 20)
$labelDays.Text = "Dias da Semana:"
$groupBoxTime.Controls.Add($labelDays)

$daysCheckboxes = @()
$dayNames = @("Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb")
for ($i = 0; $i -lt 7; $i++) {
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = $dayNames[$i]
    $chk.Tag = $i
    $chk.Size = New-Object System.Drawing.Size(55, 20)
    $chk.Location = New-Object System.Drawing.Point((140 + ($i * 62)), 28)
    if ($i -ge 1 -and $i -le 5) { $chk.Checked = $true }
    $groupBoxTime.Controls.Add($chk)
    $daysCheckboxes += $chk
}

$labelStart = New-Object System.Windows.Forms.Label
$labelStart.Location = New-Object System.Drawing.Point(20, 68)
$labelStart.Size = New-Object System.Drawing.Size(90, 20)
$labelStart.Text = "Hora Inicial (0-23):"
$groupBoxTime.Controls.Add($labelStart)

$txtStartHour = New-Object System.Windows.Forms.TextBox
$txtStartHour.Location = New-Object System.Drawing.Point(115, 66)
$txtStartHour.Size = New-Object System.Drawing.Size(60, 20)
$txtStartHour.Text = "8"
$groupBoxTime.Controls.Add($txtStartHour)

$labelEnd = New-Object System.Windows.Forms.Label
$labelEnd.Location = New-Object System.Drawing.Point(210, 68)
$labelEnd.Size = New-Object System.Drawing.Size(90, 20)
$labelEnd.Text = "Hora Final (0-23):"
$groupBoxTime.Controls.Add($labelEnd)

$txtEndHour = New-Object System.Windows.Forms.TextBox
$txtEndHour.Location = New-Object System.Drawing.Point(305, 66)
$txtEndHour.Size = New-Object System.Drawing.Size(60, 20)
$txtEndHour.Text = "18"
$groupBoxTime.Controls.Add($txtEndHour)

$form.Controls.Add($groupBoxTime)

$radioHorarioPersonalizado.Add_CheckedChanged({
    $groupBoxTime.Enabled = $radioHorarioPersonalizado.Checked
})

# ---------------------------------------------------------
# 3. SEÇÃO DE ALVOS (Utilizadores e OUs)
# ---------------------------------------------------------
$groupBoxTargets = New-Object System.Windows.Forms.GroupBox
$groupBoxTargets.Location = New-Object System.Drawing.Point(15, 225)
$groupBoxTargets.Size = New-Object System.Drawing.Size(605, 175)
$groupBoxTargets.Text = " 3. Utilizadores Manuais e OUs "

$labelUsers = New-Object System.Windows.Forms.Label
$labelUsers.Location = New-Object System.Drawing.Point(20, 25)
$labelUsers.Size = New-Object System.Drawing.Size(250, 20)
$labelUsers.Text = "Utilizadores (um por linha):"
$groupBoxTargets.Controls.Add($labelUsers)

$txtUsers = New-Object System.Windows.Forms.TextBox
$txtUsers.Location = New-Object System.Drawing.Point(20, 48)
$txtUsers.Size = New-Object System.Drawing.Size(270, 110)
$txtUsers.Multiline = $true
$txtUsers.ScrollBars = "Vertical"
$txtUsers.Text = "fernando.guimaraes`nkatia.fugita`nlilian.marques"
$groupBoxTargets.Controls.Add($txtUsers)

$labelOUs = New-Object System.Windows.Forms.Label
$labelOUs.Location = New-Object System.Drawing.Point(310, 25)
$labelOUs.Size = New-Object System.Drawing.Size(250, 20)
$labelOUs.Text = "Caminhos das OUs (opcional, um por linha):"
$groupBoxTargets.Controls.Add($labelOUs)

$txtOUs = New-Object System.Windows.Forms.TextBox
$txtOUs.Location = New-Object System.Drawing.Point(310, 48)
$txtOUs.Size = New-Object System.Drawing.Size(275, 110)
$txtOUs.Multiline = $true
$txtOUs.ScrollBars = "Vertical"
$groupBoxTargets.Controls.Add($txtOUs)

$form.Controls.Add($groupBoxTargets)

# ---------------------------------------------------------
# 4. BOTÃO DE EXECUÇÃO E LOGS
# ---------------------------------------------------------
$btnExecutar = New-Object System.Windows.Forms.Button
$btnExecutar.Location = New-Object System.Drawing.Point(15, 410)
$btnExecutar.Size = New-Object System.Drawing.Size(605, 40)
$btnExecutar.Text = "Executar Alteração no Active Directory"
$btnExecutar.BackColor = [System.Drawing.Color]::FromArgb(0, 122, 204)
$btnExecutar.ForeColor = [System.Drawing.Color]::White
$btnExecutar.Font = New-Object System.Drawing.Font("Microsoft Sans Serif", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnExecutar)

$labelLog = New-Object System.Windows.Forms.Label
$labelLog.Location = New-Object System.Drawing.Point(15, 460)
$labelLog.Size = New-Object System.Drawing.Size(200, 20)
$labelLog.Text = "Registo de Execução (Logs):"
$form.Controls.Add($labelLog)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(15, 485)
$txtLog.Size = New-Object System.Drawing.Size(605, 180)
$txtLog.Multiline = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.ReadOnly = $true
$txtLog.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($txtLog)

# =========================================================
# LÓGICA DO SCRIPT AO CLICAR NO BOTÃO
# =========================================================
$btnExecutar.Add_Click({
    $txtLog.Clear()
    $txtLog.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] [INFO] A iniciar processo...`r`n")
    $form.Refresh()

    try {
        Import-Module ActiveDirectory -ErrorAction Stop
    } catch {
        [System.Windows.Forms.MessageBox]::Show("O Módulo ActiveDirectory não pôde ser carregado. Certifique-se de executar numa máquina com as ferramentas RSAT.", "Erro", 'OK', 'Error')
        return
    }

    $logPath = "C:\hOra_eXtra_lOg\oFfice_hOurs_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    $logDir  = Split-Path -Path $logPath -Parent
    if (-not (Test-Path -Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

    function Log-UI {
        param([string]$Msg, [string]$Type = "INFO")
        $entry = "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss))] [$Type] $Msg"
        $txtLog.AppendText("$entry`r`n")
        Add-Content -Path $logPath -Value $entry -Encoding UTF8
    }

    $manualUsers = $txtUsers.Text -split "`r`n" | Where-Object { $_.Trim() -ne "" }
    $targetOUs = $txtOUs.Text -split "`r`n" | Where-Object { $_.Trim() -ne "" }
    $ouUsernames = @()

    foreach ($ou in $targetOUs) {
        try {
            $usersFromOU = Get-ADUser -SearchBase $ou.Trim() -Filter * | Select-Object -ExpandProperty SamAccountName
            $ouUsernames += $usersFromOU
            Log-UI "Coletados $(($usersFromOU).Count) utilizadores da OU: '$ou'" "INFO"
        }
        catch {
            Log-UI "Erro ao buscar utilizadores na OU '$ou': $_" "ERROR"
        }
    }

    $allUsers = ($manualUsers + $ouUsernames) | Select-Object -Unique

    if ($allUsers.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Nenhum utilizador foi especificado ou encontrado.", "Aviso", 'OK', 'Warning')
        return
    }

    if ($radioBloqueioTotal.Checked) {
        Log-UI "A aplicar Bloqueio Total (All Deny)..." "INFO"
        $byteArray = [byte[]]@(0) * 21
    }
    else {
        Log-UI "A calcular Horário Personalizado..." "INFO"
        $daysAllowed = @()
        foreach ($chk in $daysCheckboxes) {
            if ($chk.Checked) { $daysAllowed += [int]$chk.Tag }
        }
        
        $startHour = [int]$txtStartHour.Text
        $endHour   = [int]$txtEndHour.Text

        $hoursInWeek = New-Object 'byte[]' 168
        foreach ($day in $daysAllowed) {
            for ($hour = $startHour; $hour -lt $endHour; $hour++) {
                $index = ($day * 24) + $hour
                if ($index -lt 168) { $hoursInWeek[$index] = 1 }
            }
        }

        $timeZoneOffset = [TimeZoneInfo]::Local.GetUtcOffset([DateTime]::Now).Hours
        $hoursInWeekUTC = New-Object 'byte[]' 168
        for ($i = 0; $i -lt 168; $i++) {
            if ($hoursInWeek[$i] -eq 1) {
                $utcIndex = ($i - $timeZoneOffset + 168) % 168
                $hoursInWeekUTC[$utcIndex] = 1
            }
        }

        $byteArray = New-Object 'byte[]' 21
        for ($i = 0; $i -lt 168; $i++) {
            if ($hoursInWeekUTC[$i] -eq 1) {
                $byteIndex = [math]::Floor($i / 8)
                $bitIndex = $i % 8
                $byteArray[$byteIndex] = $byteArray[$byteIndex] -bor ([byte][math]::Pow(2, $bitIndex))
            }
        }
    }

    $sucessos = 0
    $erros = 0

    foreach ($user in $allUsers) {
        try {
            Set-ADUser -Identity $user.Trim() -Replace @{logonHours = $byteArray} -ErrorAction Stop
            Log-UI "Atualizado com sucesso: '$user'" "SUCCESS"
            $sucessos++
        }
        catch {
            Log-UI "Falha ao atualizar '$user': $_" "ERROR"
            $erros++
        }
    }

    Log-UI "Processo concluído. Sucessos: $sucessos | Falhas: $erros" "INFO"
    Log-UI "Log guardado em: $logPath" "INFO"
    [System.Windows.Forms.MessageBox]::Show("Processo concluído com sucesso!`nSucessos: $sucessos \vert{} Falhas:$erros", "Concluído", 'OK', 'Information')
})

[void]\$form.ShowDialog()