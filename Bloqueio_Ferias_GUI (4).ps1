#Requires -Version 5.1
<#
    Bloqueio_Ferias_GUI.ps1
    Front end gráfico para bloquear / liberar o logon (LogonHours) de usuários do Active Directory.
    Baseado no script bLoqueio_fErias.ps1.

    Requisitos: módulo ActiveDirectory (RSAT ou Domain Controller) e permissão para alterar usuários.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    [System.Windows.Forms.MessageBox]::Show(
        "Não foi possível carregar o módulo ActiveDirectory.`r`n`r`n$_",
        "Erro", 'OK', 'Error') | Out-Null
    return
}

# =========================================================
# LOG
# =========================================================
$script:LogDir  = 'C:\hOra_eXtra_lOg'
$script:LogPath = Join-Path $script:LogDir ("oFfice_hOurs_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$script:txtLog  = $null

if (-not (Test-Path -Path $script:LogDir)) {
    New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
}

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'ERROR', 'WARNING')]
        [string]$Type = 'INFO'
    )
    $entry = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Type, $Message
    Add-Content -Path $script:LogPath -Value $entry -Encoding UTF8

    if ($script:txtLog) {
        $color = switch ($Type) {
            'SUCCESS' { [System.Drawing.Color]::LimeGreen }
            'ERROR'   { [System.Drawing.Color]::Tomato }
            'WARNING' { [System.Drawing.Color]::Gold }
            default   { [System.Drawing.Color]::DeepSkyBlue }
        }
        $script:txtLog.SelectionStart  = $script:txtLog.TextLength
        $script:txtLog.SelectionColor  = $color
        $script:txtLog.AppendText($entry + "`r`n")
        $script:txtLog.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

# =========================================================
# FUNÇÕES AUXILIARES
# =========================================================
$script:UserProps = @('logonHours', 'DisplayName', 'Enabled', 'UserPrincipalName')

function Resolve-ADUserInput {
    # Aceita SamAccountName, nome completo (CN), UPN/e-mail, DisplayName ou DN
    param([string]$Text)
    $t = $Text.Trim()

    if ($t -match '^CN=.+,(OU|DC)=') {
        return Get-ADUser -Identity $t -Properties $script:UserProps -ErrorAction Stop
    }

    $esc = $t.Replace("'", "''")
    $filtro = "SamAccountName -eq '$esc' -or UserPrincipalName -eq '$esc' -or Name -eq '$esc' -or DisplayName -eq '$esc'"
    $res = @(Get-ADUser -Filter $filtro -Properties $script:UserProps -ErrorAction Stop)

    if ($res.Count -eq 1) { return $res[0] }
    if ($res.Count -gt 1) { throw "'$t' corresponde a $($res.Count) usuários; use o SamAccountName." }
    return $null
}

function Get-Targets {
    # Consolida usuários digitados + usuários das OUs, sem duplicatas.
    # Retorna objetos: Input, User (ADUser ou $null), Erro
    $map = [ordered]@{}

    foreach ($entrada in $lstUsers.Items) {
        try {
            $u = Resolve-ADUserInput -Text $entrada
            if ($u) { $map[$u.SamAccountName] = [pscustomobject]@{ Input = $entrada; User = $u; Erro = $null } }
            else    { $map["?:$entrada"]      = [pscustomobject]@{ Input = $entrada; User = $null; Erro = 'NÃO ENCONTRADO' } }
        }
        catch {
            $map["?:$entrada"] = [pscustomobject]@{ Input = $entrada; User = $null; Erro = "$($_.Exception.Message)" }
        }
    }

    foreach ($ou in $lstOUs.Items) {
        try {
            $found = @(Get-ADUser -SearchBase $ou -Filter * -Properties $script:UserProps -ErrorAction Stop)
            Write-Log "Coletados $($found.Count) usuários da OU: '$ou'" 'INFO'
            foreach ($u in $found) {
                $map[$u.SamAccountName] = [pscustomobject]@{ Input = $u.SamAccountName; User = $u; Erro = $null }
            }
        }
        catch {
            Write-Log "Erro ao buscar usuários na OU '$ou': $_" 'ERROR'
        }
    }
    return , @($map.Values)
}

function Add-UserInputs {
    param([string]$Text)
    foreach ($p in ($Text -split '[;,\r\n]+')) {
        $v = $p.Trim()
        if ($v -and -not $lstUsers.Items.Contains($v)) { [void]$lstUsers.Items.Add($v) }
    }
}

$script:DayNames = @('Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb')

function Get-UtcOffsetHours {
    # Mesmo critério do script original: horas inteiras do fuso local
    return [TimeZoneInfo]::Local.GetUtcOffset([DateTime]::Now).Hours
}

function Format-Days {
    param([int[]]$Days)
    if ($Days.Count -ge 3 -and ($Days[-1] - $Days[0]) -eq ($Days.Count - 1)) {
        return "$($script:DayNames[$Days[0]])-$($script:DayNames[$Days[-1]])"
    }
    return (($Days | ForEach-Object { $script:DayNames[$_] }) -join ',')
}

function New-LogonHoursBytes {
    # Dias: 0=Domingo ... 6=Sábado | Horas: início inclusivo, fim exclusivo (hora local)
    param([int[]]$Days, [int]$StartHour, [int]$EndHour)
    $offset = Get-UtcOffsetHours
    $bytes  = New-Object byte[] 21
    foreach ($day in $Days) {
        for ($h = $StartHour; $h -lt $EndHour; $h++) {
            $local = ($day * 24) + $h
            $utc   = ($local - $offset + 168) % 168
            $bi    = [int][math]::Floor($utc / 8)
            $bytes[$bi] = $bytes[$bi] -bor [byte](1 -shl ($utc % 8))
        }
    }
    return , $bytes
}

function Get-LogonSummary {
    # Converte os bytes (UTC) de volta para dias/horas locais, quando o padrão é uniforme
    param($LogonHours)
    $offset = Get-UtcOffsetHours
    $local  = New-Object bool[] 168
    for ($utc = 0; $utc -lt 168; $utc++) {
        if (($LogonHours[[int][math]::Floor($utc / 8)] -band (1 -shl ($utc % 8))) -ne 0) {
            $local[($utc + $offset + 168) % 168] = $true
        }
    }

    $groups = @{}
    for ($d = 0; $d -lt 7; $d++) {
        $ranges = @()
        $h = 0
        while ($h -lt 24) {
            if ($local[$d * 24 + $h]) {
                $ini = $h
                while ($h -lt 24 -and $local[$d * 24 + $h]) { $h++ }
                $ranges += ('{0:00}:00-{1:00}:59' -f $ini, ($h - 1))
            }
            else { $h++ }
        }
        if ($ranges.Count -gt 0) {
            $sig = $ranges -join ' / '
            if (-not $groups.ContainsKey($sig)) { $groups[$sig] = New-Object 'System.Collections.Generic.List[int]' }
            $groups[$sig].Add($d)
        }
    }

    if ($groups.Count -eq 1) {
        $sig = @($groups.Keys)[0]
        return "Liberado: $(Format-Days -Days $groups[$sig].ToArray()) $sig"
    }
    return 'Horário personalizado'
}

function Get-LogonStatus {
    param($LogonHours)
    if ($null -eq $LogonHours -or $LogonHours.Count -eq 0) { return 'Sem restrição' }
    $nonZero = @($LogonHours | Where-Object { $_ -ne 0 }).Count
    $notFull = @($LogonHours | Where-Object { $_ -ne 255 }).Count
    if ($nonZero -eq 0) { return 'Bloqueado total' }
    if ($notFull -eq 0) { return 'Sem restrição' }
    if ($LogonHours.Count -eq 21) { return (Get-LogonSummary -LogonHours $LogonHours) }
    return 'Horário parcial'
}

# =========================================================
# REVOGAR SESSÕES DO MICROSOFT 365 (ENTRA ID)
# =========================================================
$script:RevCands = @()

$script:GraphTenant   = 'crn3.org.br'
$script:GraphClientId = 'fcbe8bc8-ae43-4ce5-a28e-3246ded4d973'
$script:GraphThumb    = '62E1DCE226784599F868ACB64100D69D0CD48BD6'

function Test-AllZero {
    param($Bytes)
    if ($null -eq $Bytes -or $Bytes.Count -eq 0) { return $false }
    return (@($Bytes | Where-Object { $_ -ne 0 }).Count -eq 0)
}

function Get-RevokeCandidates {
    param([string]$Escopo, [bool]$SoZero, [string]$Ignorar)

    $sufixos = @($Ignorar -split '[;,\s]+' | Where-Object { $_ })

    if ($Escopo -eq 'lista') {
        $base = @(Get-Targets | Where-Object { $_.User } | ForEach-Object { $_.User })
    }
    else {
        Write-Log 'Iniciando varredura no Active Directory...' 'INFO'
        $base = @(Get-ADUser -Filter * -Properties $script:UserProps -ErrorAction Stop)
    }

    $cnt = @{ Lidos = 0; Inativos = 0; SemUpn = 0; SemBloqueio = 0; Ignorados = 0 }

    $res = foreach ($u in $base) {
        $cnt.Lidos++
        if (-not $u.Enabled) { $cnt.Inativos++; continue }
        $upn = $u.UserPrincipalName
        if (-not $upn) { $cnt.SemUpn++; continue }
        if ($SoZero -and -not (Test-AllZero $u.logonHours)) { $cnt.SemBloqueio++; continue }

        $pular = $false
        foreach ($sf in $sufixos) {
            if ($upn -like "*$sf") { $pular = $true; break }
        }
        if ($pular) { $cnt.Ignorados++; continue }
        $u
    }

    Write-Log ("Resumo: {0} lidos | inativos: {1} | sem UPN: {2} | sem bloqueio total: {3} | ignorados por sufixo: {4}" -f `
        $cnt.Lidos, $cnt.Inativos, $cnt.SemUpn, $cnt.SemBloqueio, $cnt.Ignorados) 'INFO'
    return , @($res)
}

function Show-RevokeDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Revogar sessões do Microsoft 365 (Entra ID)'
    $dlg.ClientSize      = New-Object System.Drawing.Size(920, 670)
    $dlg.StartPosition   = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.Font            = New-Object System.Drawing.Font('Segoe UI', 9)

    # --- Conexão ---
    $gbConn = New-Object System.Windows.Forms.GroupBox
    $gbConn.Text     = 'Conexão Microsoft Graph (autenticação por certificado)'
    $gbConn.Location = New-Object System.Drawing.Point(12, 10)
    $gbConn.Size     = New-Object System.Drawing.Size(896, 94)

    $lblTenant = New-Object System.Windows.Forms.Label
    $lblTenant.Text = 'Tenant'; $lblTenant.AutoSize = $true
    $lblTenant.Location = New-Object System.Drawing.Point(14, 29)
    $txtTenant = New-Object System.Windows.Forms.TextBox
    $txtTenant.Text = $script:GraphTenant
    $txtTenant.Location = New-Object System.Drawing.Point(80, 25)
    $txtTenant.Size = New-Object System.Drawing.Size(200, 24)

    $lblClient = New-Object System.Windows.Forms.Label
    $lblClient.Text = 'Client ID'; $lblClient.AutoSize = $true
    $lblClient.Location = New-Object System.Drawing.Point(300, 29)
    $txtClient = New-Object System.Windows.Forms.TextBox
    $txtClient.Text = $script:GraphClientId
    $txtClient.Location = New-Object System.Drawing.Point(365, 25)
    $txtClient.Size = New-Object System.Drawing.Size(300, 24)

    $lblThumb = New-Object System.Windows.Forms.Label
    $lblThumb.Text = 'Thumbprint'; $lblThumb.AutoSize = $true
    $lblThumb.Location = New-Object System.Drawing.Point(14, 61)
    $txtThumb = New-Object System.Windows.Forms.TextBox
    $txtThumb.Text = $script:GraphThumb
    $txtThumb.Location = New-Object System.Drawing.Point(80, 57)
    $txtThumb.Size = New-Object System.Drawing.Size(360, 24)

    $lblCertInfo = New-Object System.Windows.Forms.Label
    $lblCertInfo.Text = 'O certificado deve estar em Cert:\LocalMachine\My deste computador.'
    $lblCertInfo.AutoSize = $true
    $lblCertInfo.ForeColor = [System.Drawing.Color]::DimGray
    $lblCertInfo.Location = New-Object System.Drawing.Point(455, 61)

    $gbConn.Controls.AddRange(@($lblTenant, $txtTenant, $lblClient, $txtClient, $lblThumb, $txtThumb, $lblCertInfo))

    # --- Escopo ---
    $gbScope = New-Object System.Windows.Forms.GroupBox
    $gbScope.Text     = 'Quem terá as sessões revogadas'
    $gbScope.Location = New-Object System.Drawing.Point(12, 110)
    $gbScope.Size     = New-Object System.Drawing.Size(896, 112)

    $rbVarr = New-Object System.Windows.Forms.RadioButton
    $rbVarr.Text = 'Varredura no AD: todos os usuários ativos (como no script original)'
    $rbVarr.Checked = $true; $rbVarr.AutoSize = $true
    $rbVarr.Location = New-Object System.Drawing.Point(14, 22)

    $rbLista = New-Object System.Windows.Forms.RadioButton
    $rbLista.Text = 'Somente os usuários e OUs da tela principal'
    $rbLista.AutoSize = $true
    $rbLista.Location = New-Object System.Drawing.Point(14, 46)

    $chkZero = New-Object System.Windows.Forms.CheckBox
    $chkZero.Text = 'Somente contas com logon bloqueado (logonHours zerado)'
    $chkZero.Checked = $true; $chkZero.AutoSize = $true
    $chkZero.Location = New-Object System.Drawing.Point(14, 76)

    $lblIgn = New-Object System.Windows.Forms.Label
    $lblIgn.Text = 'Ignorar UPN terminados em (separe por vírgula):'
    $lblIgn.AutoSize = $true
    $lblIgn.Location = New-Object System.Drawing.Point(520, 24)
    $txtIgn = New-Object System.Windows.Forms.TextBox
    $txtIgn.Text = '.sp'
    $txtIgn.Location = New-Object System.Drawing.Point(520, 46)
    $txtIgn.Size = New-Object System.Drawing.Size(220, 24)

    $chkSimD = New-Object System.Windows.Forms.CheckBox
    $chkSimD.Text = 'Modo simulação (não revoga nada)'
    $chkSimD.AutoSize = $true
    $chkSimD.Location = New-Object System.Drawing.Point(520, 78)

    $gbScope.Controls.AddRange(@($rbVarr, $rbLista, $chkZero, $lblIgn, $txtIgn, $chkSimD))

    # --- Botões, lista e log ---
    $btnList = New-Object System.Windows.Forms.Button
    $btnList.Text = '1. Listar candidatos'
    $btnList.Location = New-Object System.Drawing.Point(12, 232)
    $btnList.Size = New-Object System.Drawing.Size(200, 34)

    $btnRev = New-Object System.Windows.Forms.Button
    $btnRev.Text = '2. Revogar sessões'
    $btnRev.Location = New-Object System.Drawing.Point(220, 232)
    $btnRev.Size = New-Object System.Drawing.Size(200, 34)
    $btnRev.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnRev.ForeColor = [System.Drawing.Color]::White
    $btnRev.FlatStyle = 'Flat'

    $lblCnt = New-Object System.Windows.Forms.Label
    $lblCnt.AutoSize = $false
    $lblCnt.TextAlign = 'MiddleRight'
    $lblCnt.Location = New-Object System.Drawing.Point(660, 236)
    $lblCnt.Size = New-Object System.Drawing.Size(248, 26)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.GridLines = $true
    $lv.Location = New-Object System.Drawing.Point(12, 274)
    $lv.Size = New-Object System.Drawing.Size(896, 234)
    [void]$lv.Columns.Add('UPN', 330)
    [void]$lv.Columns.Add('Nome', 330)
    [void]$lv.Columns.Add('Status', 220)

    $dlgLog = New-Object System.Windows.Forms.RichTextBox
    $dlgLog.Location = New-Object System.Drawing.Point(12, 518)
    $dlgLog.Size = New-Object System.Drawing.Size(896, 140)
    $dlgLog.ReadOnly = $true
    $dlgLog.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $dlgLog.Font = New-Object System.Drawing.Font('Consolas', 9)

    $dlg.Controls.AddRange(@($gbConn, $gbScope, $btnList, $btnRev, $lblCnt, $lv, $dlgLog))

    # --- Listar candidatos ---
    $btnList.Add_Click({
        $dlg.Cursor = 'WaitCursor'
        try {
            $lv.Items.Clear()
            $escopo = if ($rbLista.Checked) { 'lista' } else { 'varredura' }
            $script:RevCands = Get-RevokeCandidates -Escopo $escopo -SoZero $chkZero.Checked -Ignorar $txtIgn.Text
            foreach ($u in $script:RevCands) {
                $it = New-Object System.Windows.Forms.ListViewItem($u.UserPrincipalName)
                $nome = if ($u.DisplayName) { $u.DisplayName } else { $u.Name }
                [void]$it.SubItems.Add($nome)
                [void]$it.SubItems.Add('Pendente')
                [void]$lv.Items.Add($it)
            }
            $lblCnt.Text = "$(@($script:RevCands).Count) candidato(s)"
            Write-Log "$(@($script:RevCands).Count) candidato(s) encontrados para revogação." 'INFO'
        }
        catch {
            Write-Log "Erro ao listar candidatos: $($_.Exception.Message)" 'ERROR'
        }
        finally {
            $dlg.Cursor = 'Default'
        }
    })

    # --- Revogar ---
    $btnRev.Add_Click({
        $cands = @($script:RevCands)
        if ($cands.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('Clique em "Listar candidatos" antes de revogar.', 'Atenção', 'OK', 'Warning') | Out-Null
            return
        }

        $simular = $chkSimD.Checked
        $modo = if ($simular) { ' (SIMULAÇÃO)' } else { '' }
        $resp = [System.Windows.Forms.MessageBox]::Show(
            "Revogar as sessões do Microsoft 365 de $($cands.Count) usuário(s)?$modo",
            'Confirmação', 'YesNo', 'Question')
        if ($resp -ne 'Yes') { return }

        $btnList.Enabled = $false
        $btnRev.Enabled  = $false
        $dlg.Cursor      = 'WaitCursor'
        $conectado       = $false

        try {
            if (-not $simular) {
                $faltando = @('Connect-MgGraph', 'Get-MgUser', 'Invoke-MgGraphRequest' |
                              Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
                if ($faltando.Count -gt 0) {
                    Write-Log "Módulo Microsoft.Graph não encontrado (faltando: $($faltando -join ', ')). Instale com: Install-Module Microsoft.Graph -Scope AllUsers" 'ERROR'
                    return
                }

                $thumb = $txtThumb.Text.Trim()
                try {
                    $cert = Get-ChildItem -Path "Cert:\LocalMachine\My\$thumb" -ErrorAction Stop
                    Write-Log "Certificado encontrado: $($cert.Subject)" 'SUCCESS'
                }
                catch {
                    Write-Log "Certificado não encontrado em Cert:\LocalMachine\My ($thumb)." 'ERROR'
                    return
                }

                try {
                    Connect-MgGraph -TenantId $txtTenant.Text.Trim() -ClientId $txtClient.Text.Trim() -CertificateThumbprint $thumb -ErrorAction Stop
                    $conectado = $true
                    Write-Log 'Conectado ao Microsoft Graph com sucesso.' 'SUCCESS'
                }
                catch {
                    Write-Log "Erro ao conectar: $($_.Exception.Message)" 'ERROR'
                    return
                }
            }

            Write-Log "Iniciando revogação de sessões do 365$modo" 'INFO'
            $ok = 0
            $err = 0
            for ($i = 0; $i -lt $cands.Count; $i++) {
                $upn = $cands[$i].UserPrincipalName
                $it  = $lv.Items[$i]
                try {
                    if ($simular) {
                        Write-Log "SIMULAÇÃO: sessões de '$upn' seriam revogadas (nenhuma alteração feita)." 'WARNING'
                        $it.SubItems[2].Text = 'Simulado'
                    }
                    else {
                        $mg = Get-MgUser -UserId $upn -ErrorAction Stop
                        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$($mg.Id)/revokeSignInSessions" -ErrorAction Stop | Out-Null
                        Write-Log "Sessões revogadas: $upn" 'SUCCESS'
                        $it.SubItems[2].Text = 'Revogado'
                        $it.ForeColor = [System.Drawing.Color]::SeaGreen
                    }
                    $ok++
                }
                catch {
                    Write-Log "Erro em ${upn}: $($_.Exception.Message)" 'ERROR'
                    $it.SubItems[2].Text = 'Erro'
                    $it.ForeColor = [System.Drawing.Color]::Firebrick
                    $err++
                }
            }
            Write-Log "Revogação concluída. Sucessos: $ok | Falhas: $err" 'INFO'
            Write-Log "Arquivo de log salvo em: $($script:LogPath)" 'INFO'
        }
        finally {
            if ($conectado) { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null }
            $btnList.Enabled = $true
            $btnRev.Enabled  = $true
            $dlg.Cursor      = 'Default'
        }
    })

    # O log da janela passa a receber as mensagens enquanto ela estiver aberta
    $logAnterior   = $script:txtLog
    $script:txtLog = $dlgLog
    try { [void]$dlg.ShowDialog($form) }
    finally { $script:txtLog = $logAnterior }
}

# =========================================================
# AGENDAMENTO (BLOQUEAR NA IDA / LIBERAR NA VOLTA) - AGENDADOR DE TAREFAS
# =========================================================
$script:SchedDir     = Join-Path $script:LogDir 'Agendamentos'
$script:TaskPath     = '\LogonHours\'
$script:SchedTargets = @()

# Script executado pelo Agendador de Tarefas (sem interface). Gravado em disco ao criar o agendamento.
$script:RunnerCode = @'
param(
    [Parameter(Mandatory = $true)][string]$JobFile,
    [Parameter(Mandatory = $true)][ValidateSet('Bloquear', 'Liberar')][string]$Acao
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$job        = Get-Content -Path $JobFile -Raw -Encoding UTF8 | ConvertFrom-Json
$logDir     = Split-Path -Path (Split-Path -Path $JobFile -Parent) -Parent
$logPath    = Join-Path $logDir ('Agendamento_{0}_{1}_{2}.log' -f $job.Id, $Acao, (Get-Date -Format 'yyyyMMdd_HHmmss'))
$backupFile = [System.IO.Path]::ChangeExtension($JobFile, '.backup.json')

function Write-Log {
    param([string]$Message, [string]$Type = 'INFO')
    $entry = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Type, $Message
    Add-Content -Path $logPath -Value $entry -Encoding UTF8
    Write-Host $entry
}

# Horarios anteriores de cada usuario (gravados no bloqueio, usados na liberacao)
$backup = @{}
if (Test-Path -Path $backupFile) {
    $obj = Get-Content -Path $backupFile -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($obj) { $obj.PSObject.Properties | ForEach-Object { $backup[$_.Name] = $_.Value } }
}

Write-Log ('Iniciando agendamento {0}: {1}' -f $job.Id, $Acao.ToUpper()) 'INFO'
$ok   = 0
$err  = 0
$upns = @()

if ($Acao -eq 'Bloquear') {
    $zero = New-Object byte[] 21
    foreach ($sam in @($job.Usuarios)) {
        try {
            $u = Get-ADUser -Identity $sam -Properties logonHours, UserPrincipalName -ErrorAction Stop
            if (-not $backup.ContainsKey($sam)) {
                if ($u.logonHours) { $backup[$sam] = [Convert]::ToBase64String([byte[]]$u.logonHours) }
                else               { $backup[$sam] = '' }
            }
            Set-ADUser -Identity $sam -Replace @{ logonHours = $zero } -ErrorAction Stop
            Write-Log ('Bloqueio total aplicado: {0}' -f $sam) 'SUCCESS'
            if ($u.UserPrincipalName) { $upns += $u.UserPrincipalName }
            $ok++
        }
        catch {
            Write-Log ('Falha ao bloquear {0}: {1}' -f $sam, $_.Exception.Message) 'ERROR'
            $err++
        }
    }
    ($backup | ConvertTo-Json) | Set-Content -Path $backupFile -Encoding UTF8

    if ($job.Revogar365 -and $upns.Count -gt 0) {
        try {
            $null = Get-ChildItem -Path ('Cert:\LocalMachine\My\{0}' -f $job.Thumbprint)
            Connect-MgGraph -TenantId $job.Tenant -ClientId $job.ClientId -CertificateThumbprint $job.Thumbprint
            Write-Log 'Conectado ao Microsoft Graph.' 'SUCCESS'
            foreach ($upn in $upns) {
                try {
                    $mg = Get-MgUser -UserId $upn
                    Invoke-MgGraphRequest -Method POST -Uri ('https://graph.microsoft.com/v1.0/users/{0}/revokeSignInSessions' -f $mg.Id) | Out-Null
                    Write-Log ('Sessoes do 365 revogadas: {0}' -f $upn) 'SUCCESS'
                }
                catch {
                    Write-Log ('Falha ao revogar sessoes de {0}: {1}' -f $upn, $_.Exception.Message) 'ERROR'
                    $err++
                }
            }
        }
        catch {
            Write-Log ('Falha na conexao com o Microsoft Graph: {0}' -f $_.Exception.Message) 'ERROR'
            $err++
        }
        finally {
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        }
    }
}
else {
    $modo = 'Restaurar'
    if ($job.ModoLiberar) { $modo = [string]$job.ModoLiberar }
    $novo = $null
    if ($modo -eq 'Horario' -and $job.LiberarHorario) {
        $novo = [Convert]::FromBase64String([string]$job.LiberarHorario)
    }
    if ($modo -eq 'Horario' -and -not $novo) {
        Write-Log 'Horario de liberacao ausente no agendamento; usando a restauracao do horario anterior.' 'WARNING'
        $modo = 'Restaurar'
    }
    Write-Log ('Modo de liberacao: {0} {1}' -f $modo, $job.LiberarDescricao) 'INFO'

    foreach ($sam in @($job.Usuarios)) {
        try {
            if ($modo -eq 'Horario') {
                Set-ADUser -Identity $sam -Replace @{ logonHours = $novo } -ErrorAction Stop
                Write-Log ('Horario definido na liberacao ({0}): {1}' -f $job.LiberarDescricao, $sam) 'SUCCESS'
            }
            elseif ($modo -eq 'Remover') {
                Set-ADUser -Identity $sam -Clear logonHours -ErrorAction Stop
                Write-Log ('Restricao de horario removida: {0}' -f $sam) 'SUCCESS'
            }
            else {
                $prev = $null
                if ($backup.ContainsKey($sam) -and $backup[$sam]) {
                    $prev = [Convert]::FromBase64String($backup[$sam])
                }
                if ($prev -and (@($prev | Where-Object { $_ -ne 0 }).Count -eq 0)) {
                    Write-Log ('ATENCAO: o horario anterior de {0} ja era bloqueio total; a restricao foi removida e a conta ficou SEM restricao.' -f $sam) 'WARNING'
                    $prev = $null
                }
                if ($prev) {
                    Set-ADUser -Identity $sam -Replace @{ logonHours = $prev } -ErrorAction Stop
                    Write-Log ('Horario anterior restaurado: {0}' -f $sam) 'SUCCESS'
                }
                else {
                    Set-ADUser -Identity $sam -Clear logonHours -ErrorAction Stop
                    Write-Log ('Restricao de horario removida: {0}' -f $sam) 'SUCCESS'
                }
            }
            $ok++
        }
        catch {
            Write-Log ('Falha ao liberar {0}: {1}' -f $sam, $_.Exception.Message) 'ERROR'
            $err++
        }
    }
}

Write-Log ('Concluido. Sucessos: {0} | Falhas: {1}' -f $ok, $err) 'INFO'
if ($err -gt 0) { exit 1 } else { exit 0 }
'@

function Show-ScheduleDialog {
    $script:SchedTargets = @()

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = 'Agendar bloqueio e liberação (férias)'
    $dlg.ClientSize      = New-Object System.Drawing.Size(940, 824)
    $dlg.StartPosition   = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.Font            = New-Object System.Drawing.Font('Segoe UI', 9)

    # --- Datas ---
    $gbDates = New-Object System.Windows.Forms.GroupBox
    $gbDates.Text     = 'Período'
    $gbDates.Location = New-Object System.Drawing.Point(12, 10)
    $gbDates.Size     = New-Object System.Drawing.Size(916, 84)

    $lblIni = New-Object System.Windows.Forms.Label
    $lblIni.Text = 'Bloquear em:'; $lblIni.AutoSize = $true
    $lblIni.Location = New-Object System.Drawing.Point(14, 31)

    $dtpStart = New-Object System.Windows.Forms.DateTimePicker
    $dtpStart.Format = 'Custom'; $dtpStart.CustomFormat = 'dd/MM/yyyy HH:mm'
    $dtpStart.Value    = (Get-Date).Date.AddDays(1)
    $dtpStart.Location = New-Object System.Drawing.Point(100, 27)
    $dtpStart.Size     = New-Object System.Drawing.Size(150, 24)

    $lblFimAg = New-Object System.Windows.Forms.Label
    $lblFimAg.Text = 'Liberar em:'; $lblFimAg.AutoSize = $true
    $lblFimAg.Location = New-Object System.Drawing.Point(280, 31)

    $dtpEnd = New-Object System.Windows.Forms.DateTimePicker
    $dtpEnd.Format = 'Custom'; $dtpEnd.CustomFormat = 'dd/MM/yyyy HH:mm'
    $dtpEnd.Value    = (Get-Date).Date.AddDays(31).AddHours(6)
    $dtpEnd.Location = New-Object System.Drawing.Point(358, 27)
    $dtpEnd.Size     = New-Object System.Drawing.Size(150, 24)

    $chkRevoga = New-Object System.Windows.Forms.CheckBox
    $chkRevoga.Text = 'Revogar sessões do Microsoft 365 ao bloquear'
    $chkRevoga.AutoSize = $true
    $chkRevoga.Location = New-Object System.Drawing.Point(560, 29)

    $lblDica = New-Object System.Windows.Forms.Label
    $lblDica.Text = 'Defina abaixo o que acontece na liberação. Ajuste também a hora (ex.: liberar às 06:00 do dia da volta).'
    $lblDica.AutoSize = $true
    $lblDica.ForeColor = [System.Drawing.Color]::DimGray
    $lblDica.Location = New-Object System.Drawing.Point(14, 58)

    $gbDates.Controls.AddRange(@($lblIni, $dtpStart, $lblFimAg, $dtpEnd, $chkRevoga, $lblDica))

    # --- Conexão Graph (só quando revogar 365) ---
    $gbGraph = New-Object System.Windows.Forms.GroupBox
    $gbGraph.Text     = 'Microsoft Graph (usado só se marcar a revogação de sessões)'
    $gbGraph.Location = New-Object System.Drawing.Point(12, 100)
    $gbGraph.Size     = New-Object System.Drawing.Size(916, 62)
    $gbGraph.Enabled  = $false

    $lblT = New-Object System.Windows.Forms.Label
    $lblT.Text = 'Tenant'; $lblT.AutoSize = $true
    $lblT.Location = New-Object System.Drawing.Point(14, 29)
    $txtTenant = New-Object System.Windows.Forms.TextBox
    $txtTenant.Text = $script:GraphTenant
    $txtTenant.Location = New-Object System.Drawing.Point(62, 25)
    $txtTenant.Size = New-Object System.Drawing.Size(150, 24)

    $lblC = New-Object System.Windows.Forms.Label
    $lblC.Text = 'Client ID'; $lblC.AutoSize = $true
    $lblC.Location = New-Object System.Drawing.Point(230, 29)
    $txtClient = New-Object System.Windows.Forms.TextBox
    $txtClient.Text = $script:GraphClientId
    $txtClient.Location = New-Object System.Drawing.Point(292, 25)
    $txtClient.Size = New-Object System.Drawing.Size(270, 24)

    $lblP = New-Object System.Windows.Forms.Label
    $lblP.Text = 'Thumbprint'; $lblP.AutoSize = $true
    $lblP.Location = New-Object System.Drawing.Point(580, 29)
    $txtThumb = New-Object System.Windows.Forms.TextBox
    $txtThumb.Text = $script:GraphThumb
    $txtThumb.Location = New-Object System.Drawing.Point(652, 25)
    $txtThumb.Size = New-Object System.Drawing.Size(250, 24)

    $gbGraph.Controls.AddRange(@($lblT, $txtTenant, $lblC, $txtClient, $lblP, $txtThumb))

    # --- O que fazer ao liberar ---
    $gbLib = New-Object System.Windows.Forms.GroupBox
    $gbLib.Text     = 'Ao liberar (na data de retorno)'
    $gbLib.Location = New-Object System.Drawing.Point(12, 168)
    $gbLib.Size     = New-Object System.Drawing.Size(916, 122)

    $rbLibRest = New-Object System.Windows.Forms.RadioButton
    $rbLibRest.Text = 'Restaurar o horário que o usuário tinha antes do bloqueio'
    $rbLibRest.Checked = $true; $rbLibRest.AutoSize = $true
    $rbLibRest.Location = New-Object System.Drawing.Point(14, 22)

    $rbLibHor = New-Object System.Windows.Forms.RadioButton
    $rbLibHor.Text = 'Definir horário permitido:'
    $rbLibHor.AutoSize = $true
    $rbLibHor.Location = New-Object System.Drawing.Point(14, 48)

    $rbLibRem = New-Object System.Windows.Forms.RadioButton
    $rbLibRem.Text = 'Remover a restrição (logon liberado em qualquer horário)'
    $rbLibRem.AutoSize = $true
    $rbLibRem.Location = New-Object System.Drawing.Point(14, 96)

    $chkLibDays = @()
    for ($i = 0; $i -lt 7; $i++) {
        $c = New-Object System.Windows.Forms.CheckBox
        $c.Text     = $script:DayNames[$i]
        $c.Tag      = $i
        $c.AutoSize = $true
        $c.Location = New-Object System.Drawing.Point((230 + $i * 62), 48)
        $c.Checked  = ($i -ge 1 -and $i -le 5)
        $chkLibDays += $c
    }

    $btnLibSegSex = New-Object System.Windows.Forms.Button
    $btnLibSegSex.Text = 'Seg-Sex'
    $btnLibSegSex.Location = New-Object System.Drawing.Point(678, 44)
    $btnLibSegSex.Size = New-Object System.Drawing.Size(74, 26)

    $btnLibTodos = New-Object System.Windows.Forms.Button
    $btnLibTodos.Text = 'Todos'
    $btnLibTodos.Location = New-Object System.Drawing.Point(758, 44)
    $btnLibTodos.Size = New-Object System.Drawing.Size(74, 26)

    $lblLibDas = New-Object System.Windows.Forms.Label
    $lblLibDas.Text = 'Liberar das'; $lblLibDas.AutoSize = $true
    $lblLibDas.Location = New-Object System.Drawing.Point(230, 80)

    $nudLibStart = New-Object System.Windows.Forms.NumericUpDown
    $nudLibStart.Minimum = 0; $nudLibStart.Maximum = 23; $nudLibStart.Value = 8
    $nudLibStart.Location = New-Object System.Drawing.Point(300, 76)
    $nudLibStart.Size = New-Object System.Drawing.Size(55, 24)

    $lblLibAte = New-Object System.Windows.Forms.Label
    $lblLibAte.Text = 'h  até'; $lblLibAte.AutoSize = $true
    $lblLibAte.Location = New-Object System.Drawing.Point(358, 80)

    $nudLibEnd = New-Object System.Windows.Forms.NumericUpDown
    $nudLibEnd.Minimum = 1; $nudLibEnd.Maximum = 24; $nudLibEnd.Value = 18
    $nudLibEnd.Location = New-Object System.Drawing.Point(402, 76)
    $nudLibEnd.Size = New-Object System.Drawing.Size(55, 24)

    $lblLibFim = New-Object System.Windows.Forms.Label
    $lblLibFim.AutoSize = $true
    $lblLibFim.Location = New-Object System.Drawing.Point(462, 80)

    $libCtrls = @($chkLibDays) + @($btnLibSegSex, $btnLibTodos, $lblLibDas, $nudLibStart, $lblLibAte, $nudLibEnd, $lblLibFim)
    foreach ($c in $libCtrls) { $c.Enabled = $false }

    $gbLib.Controls.AddRange([System.Windows.Forms.Control[]](@($rbLibRest, $rbLibHor, $rbLibRem) + $libCtrls))

    # --- Usuários ---
    $gbSel = New-Object System.Windows.Forms.GroupBox
    $gbSel.Text     = 'Usuários deste agendamento (lista e OUs da tela principal)'
    $gbSel.Location = New-Object System.Drawing.Point(12, 296)
    $gbSel.Size     = New-Object System.Drawing.Size(916, 190)

    $btnLoad = New-Object System.Windows.Forms.Button
    $btnLoad.Text = 'Recarregar da tela principal'
    $btnLoad.Location = New-Object System.Drawing.Point(14, 20)
    $btnLoad.Size = New-Object System.Drawing.Size(210, 26)

    $lblSel = New-Object System.Windows.Forms.Label
    $lblSel.AutoSize = $false
    $lblSel.TextAlign = 'MiddleRight'
    $lblSel.Location = New-Object System.Drawing.Point(660, 20)
    $lblSel.Size = New-Object System.Drawing.Size(242, 26)

    $lvSel = New-Object System.Windows.Forms.ListView
    $lvSel.View = 'Details'; $lvSel.FullRowSelect = $true; $lvSel.GridLines = $true
    $lvSel.Location = New-Object System.Drawing.Point(14, 52)
    $lvSel.Size = New-Object System.Drawing.Size(888, 130)
    [void]$lvSel.Columns.Add('Usuário', 180)
    [void]$lvSel.Columns.Add('Nome', 300)
    [void]$lvSel.Columns.Add('Logon atual', 380)

    $gbSel.Controls.AddRange(@($btnLoad, $lblSel, $lvSel))

    # --- Criar ---
    $btnCreate = New-Object System.Windows.Forms.Button
    $btnCreate.Text = 'Criar agendamento'
    $btnCreate.Location = New-Object System.Drawing.Point(12, 494)
    $btnCreate.Size = New-Object System.Drawing.Size(200, 34)
    $btnCreate.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnCreate.ForeColor = [System.Drawing.Color]::White
    $btnCreate.FlatStyle = 'Flat'

    $lblConta = New-Object System.Windows.Forms.Label
    $lblConta.Text = 'As tarefas rodam em uma conta com permissão no AD; a senha será solicitada e não fica salva no script.'
    $lblConta.AutoSize = $true
    $lblConta.ForeColor = [System.Drawing.Color]::DimGray
    $lblConta.Location = New-Object System.Drawing.Point(224, 503)

    # --- Agendamentos existentes ---
    $gbTasks = New-Object System.Windows.Forms.GroupBox
    $gbTasks.Text     = 'Agendamentos existentes (Agendador de Tarefas, pasta \LogonHours)'
    $gbTasks.Location = New-Object System.Drawing.Point(12, 536)
    $gbTasks.Size     = New-Object System.Drawing.Size(916, 176)

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = 'Atualizar'
    $btnRefresh.Location = New-Object System.Drawing.Point(14, 20)
    $btnRefresh.Size = New-Object System.Drawing.Size(110, 26)

    $btnRemove = New-Object System.Windows.Forms.Button
    $btnRemove.Text = 'Remover selecionado'
    $btnRemove.Location = New-Object System.Drawing.Point(130, 20)
    $btnRemove.Size = New-Object System.Drawing.Size(180, 26)

    $lvTasks = New-Object System.Windows.Forms.ListView
    $lvTasks.View = 'Details'; $lvTasks.FullRowSelect = $true; $lvTasks.GridLines = $true
    $lvTasks.Location = New-Object System.Drawing.Point(14, 52)
    $lvTasks.Size = New-Object System.Drawing.Size(888, 116)
    [void]$lvTasks.Columns.Add('Tarefa', 290)
    [void]$lvTasks.Columns.Add('Próxima execução', 130)
    [void]$lvTasks.Columns.Add('Estado', 70)
    [void]$lvTasks.Columns.Add('Último resultado', 110)
    [void]$lvTasks.Columns.Add('Descrição', 270)

    $gbTasks.Controls.AddRange(@($btnRefresh, $btnRemove, $lvTasks))

    # --- Log ---
    $dlgLog = New-Object System.Windows.Forms.RichTextBox
    $dlgLog.Location = New-Object System.Drawing.Point(12, 720)
    $dlgLog.Size = New-Object System.Drawing.Size(916, 96)
    $dlgLog.ReadOnly = $true
    $dlgLog.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $dlgLog.Font = New-Object System.Drawing.Font('Consolas', 9)

    $dlg.Controls.AddRange(@($gbDates, $gbGraph, $gbLib, $gbSel, $btnCreate, $lblConta, $gbTasks, $dlgLog))

    # --- Eventos ---
    $chkRevoga.Add_CheckedChanged({ $gbGraph.Enabled = $chkRevoga.Checked })

    $rbLibHor.Add_CheckedChanged({ foreach ($c in $libCtrls) { $c.Enabled = $rbLibHor.Checked } })
    $updLib = { $lblLibFim.Text = "(último logon permitido: {0:00}:59)" -f ([int]$nudLibEnd.Value - 1) }
    $nudLibEnd.Add_ValueChanged($updLib)
    & $updLib
    $btnLibSegSex.Add_Click({ foreach ($c in $chkLibDays) { $c.Checked = ($c.Tag -ge 1 -and $c.Tag -le 5) } })
    $btnLibTodos.Add_Click({ foreach ($c in $chkLibDays) { $c.Checked = $true } })

    $btnLoad.Add_Click({
        $dlg.Cursor = 'WaitCursor'
        try {
            $lvSel.Items.Clear()
            $script:SchedTargets = @(Get-Targets | Where-Object { $_.User })
            foreach ($t in $script:SchedTargets) {
                $u = $t.User
                $it = New-Object System.Windows.Forms.ListViewItem($u.SamAccountName)
                $nome = if ($u.DisplayName) { $u.DisplayName } else { $u.Name }
                [void]$it.SubItems.Add($nome)
                [void]$it.SubItems.Add((Get-LogonStatus $u.logonHours))
                [void]$lvSel.Items.Add($it)
            }
            $lblSel.Text = "$(@($script:SchedTargets).Count) usuário(s)"
            $nb = @($script:SchedTargets | Where-Object { (Get-LogonStatus $_.User.logonHours) -eq 'Bloqueado total' }).Count
            if ($nb -gt 0) {
                $rbLibHor.Checked = $true
                Write-Log "$nb usuário(s) já estão com bloqueio total. Selecionei 'Definir horário permitido' na liberação, para não devolverem a conta sem restrição." 'WARNING'
            }
        }
        catch {
            Write-Log "Erro ao carregar usuários: $($_.Exception.Message)" 'ERROR'
        }
        finally {
            $dlg.Cursor = 'Default'
        }
    })

    $btnRefresh.Add_Click({
        $lvTasks.Items.Clear()
        $tasks = @(Get-ScheduledTask -TaskPath $script:TaskPath -ErrorAction SilentlyContinue)
        foreach ($t in ($tasks | Sort-Object TaskName)) {
            $info = Get-ScheduledTaskInfo -InputObject $t -ErrorAction SilentlyContinue
            $prox = if ($info -and $info.NextRunTime -and $info.NextRunTime.Year -gt 2000) { $info.NextRunTime.ToString('dd/MM/yyyy HH:mm') } else { '-' }
            $res  = if (-not $info) { '-' }
                    elseif ($info.LastTaskResult -eq 267011) { 'Nunca executada' }
                    elseif ($info.LastTaskResult -eq 0) { 'Sucesso' }
                    else { 'Código ' + $info.LastTaskResult }
            $it = New-Object System.Windows.Forms.ListViewItem($t.TaskName)
            [void]$it.SubItems.Add($prox)
            [void]$it.SubItems.Add([string]$t.State)
            [void]$it.SubItems.Add($res)
            [void]$it.SubItems.Add([string]$t.Description)
            $it.Tag = $t.TaskName
            [void]$lvTasks.Items.Add($it)
        }
    })

    $btnRemove.Add_Click({
        if ($lvTasks.SelectedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('Selecione um agendamento na lista.', 'Atenção', 'OK', 'Warning') | Out-Null
            return
        }
        $ids = @($lvTasks.SelectedItems | ForEach-Object {
            ($_.Tag -replace '^LogonHours-Ferias-', '') -replace '-(Bloquear|Liberar)$', ''
        } | Sort-Object -Unique)

        $resp = [System.Windows.Forms.MessageBox]::Show(
            "Remover o agendamento (bloqueio e liberação) de: $($ids -join ', ')?`r`n`r`nSe o bloqueio já tiver sido aplicado, os usuários continuarão bloqueados até você liberar.",
            'Confirmação', 'YesNo', 'Question')
        if ($resp -ne 'Yes') { return }

        foreach ($id in $ids) {
            foreach ($nome in @("LogonHours-Ferias-$id-Bloquear", "LogonHours-Ferias-$id-Liberar")) {
                Unregister-ScheduledTask -TaskName $nome -TaskPath $script:TaskPath -Confirm:$false -ErrorAction SilentlyContinue
            }
            Write-Log "Agendamento $id removido." 'INFO'
        }
        $btnRefresh.PerformClick()
    })

    $btnCreate.Add_Click({
        $alvos = @($script:SchedTargets)
        if ($alvos.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('Nenhum usuário na lista. Adicione usuários na tela principal e clique em "Recarregar".', 'Atenção', 'OK', 'Warning') | Out-Null
            return
        }

        $inicio = $dtpStart.Value
        $fim    = $dtpEnd.Value
        if ($inicio -le (Get-Date)) {
            [System.Windows.Forms.MessageBox]::Show('A data/hora de bloqueio precisa estar no futuro.', 'Atenção', 'OK', 'Warning') | Out-Null
            return
        }
        if ($fim -le $inicio) {
            [System.Windows.Forms.MessageBox]::Show('A liberação precisa ser depois do bloqueio.', 'Atenção', 'OK', 'Warning') | Out-Null
            return
        }

        $revoga = $chkRevoga.Checked
        if ($revoga -and (@($txtTenant.Text, $txtClient.Text, $txtThumb.Text | Where-Object { -not $_.Trim() }).Count -gt 0)) {
            [System.Windows.Forms.MessageBox]::Show('Preencha Tenant, Client ID e Thumbprint para revogar as sessões.', 'Atenção', 'OK', 'Warning') | Out-Null
            return
        }

        $modoLib  = if ($rbLibHor.Checked) { 'Horario' } elseif ($rbLibRem.Checked) { 'Remover' } else { 'Restaurar' }
        $libBytes = ''
        $libDesc  = ''
        if ($modoLib -eq 'Horario') {
            $diasLib = @($chkLibDays | Where-Object { $_.Checked } | ForEach-Object { [int]$_.Tag })
            $iniLib  = [int]$nudLibStart.Value
            $fimLib  = [int]$nudLibEnd.Value
            if ($diasLib.Count -eq 0) {
                [System.Windows.Forms.MessageBox]::Show('Marque ao menos um dia da semana para o horário da liberação.', 'Atenção', 'OK', 'Warning') | Out-Null
                return
            }
            if ($fimLib -le $iniLib) {
                [System.Windows.Forms.MessageBox]::Show('Na liberação, a hora final deve ser maior que a inicial.', 'Atenção', 'OK', 'Warning') | Out-Null
                return
            }
            $libBytes = [Convert]::ToBase64String([byte[]](New-LogonHoursBytes -Days $diasLib -StartHour $iniLib -EndHour $fimLib))
            $libDesc  = '{0} {1:00}:00-{2:00}:59' -f (Format-Days -Days $diasLib), $iniLib, ($fimLib - 1)
        }

        $sams = @()
        foreach ($t in $alvos) {
            $sam = $t.User.SamAccountName
            if ($sam -ieq $env:USERNAME) {
                Write-Log "Usuário '$sam' é a conta atual - removido do agendamento." 'WARNING'
                continue
            }
            $sams += $sam
        }
        if ($sams.Count -eq 0) { return }

        $txtLib = switch ($modoLib) {
            'Horario' { "definir $libDesc" }
            'Remover' { 'remover a restrição' }
            default   { 'restaurar o horário anterior' }
        }
        $aviso = ''
        if ($modoLib -eq 'Restaurar') {
            $nb = @($alvos | Where-Object { (Get-LogonStatus $_.User.logonHours) -eq 'Bloqueado total' }).Count
            if ($nb -gt 0) {
                $aviso = "`r`n`r`nATENÇÃO: $nb usuário(s) já estão com bloqueio total. Restaurar o horário anterior deixará essas contas SEM restrição. Para voltarem com horário comercial, use 'Definir horário permitido'."
            }
        }
        $msg = "Agendar para $($sams.Count) usuário(s):`r`n`r`nBloquear: {0:dd/MM/yyyy HH:mm}`r`nLiberar: {1:dd/MM/yyyy HH:mm} ({3})`r`nRevogar sessões 365: {2}$aviso`r`n`r`nContinuar?" -f $inicio, $fim, $(if ($revoga) { 'sim' } else { 'não' }), $txtLib
        if ([System.Windows.Forms.MessageBox]::Show($msg, 'Confirmação', 'YesNo', 'Question') -ne 'Yes') { return }

        $cred = Get-Credential -UserName "$env:USERDOMAIN\$env:USERNAME" -Message 'Conta que executará as tarefas agendadas (precisa alterar usuários no AD).'
        if (-not $cred) { return }

        $dlg.Cursor = 'WaitCursor'
        $id = Get-Date -Format 'yyyyMMdd-HHmmss'
        try {
            if (-not (Test-Path -Path $script:SchedDir)) { New-Item -ItemType Directory -Path $script:SchedDir -Force | Out-Null }

            $runner  = Join-Path $script:SchedDir 'Executar-LogonHours.ps1'
            $jobFile = Join-Path $script:SchedDir "$id.job.json"
            Set-Content -Path $runner -Value $script:RunnerCode -Encoding UTF8

            $job = [ordered]@{
                Id         = $id
                Criado     = (Get-Date).ToString('s')
                Bloqueio   = $inicio.ToString('s')
                Liberacao  = $fim.ToString('s')
                Usuarios   = $sams
                Revogar365 = [bool]$revoga
                Tenant     = $txtTenant.Text.Trim()
                ClientId   = $txtClient.Text.Trim()
                Thumbprint = $txtThumb.Text.Trim()
                ModoLiberar      = $modoLib
                LiberarHorario   = $libBytes
                LiberarDescricao = $libDesc
            }
            ($job | ConvertTo-Json -Depth 4) | Set-Content -Path $jobFile -Encoding UTF8

            $resumo = if ($sams.Count -le 6) { $sams -join ', ' } else { "$($sams.Count) usuários" }
            $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 2)
            $senha = $cred.GetNetworkCredential().Password

            foreach ($def in @(@{ Acao = 'Bloquear'; Quando = $inicio }, @{ Acao = 'Liberar'; Quando = $fim })) {
                $nome = "LogonHours-Ferias-$id-$($def.Acao)"
                $arg  = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -JobFile "{1}" -Acao {2}' -f $runner, $jobFile, $def.Acao
                $acao = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
                $gat  = New-ScheduledTaskTrigger -Once -At $def.Quando
                [void](Register-ScheduledTask -TaskName $nome -TaskPath $script:TaskPath -Action $acao -Trigger $gat `
                        -Settings $settings -User $cred.UserName -Password $senha -RunLevel Highest `
                        -Description "$($def.Acao) logon (férias) - $resumo" -Force -ErrorAction Stop)
                Write-Log ("Tarefa criada: $nome ({0:dd/MM/yyyy HH:mm})" -f $def.Quando) 'SUCCESS'
            }
            Write-Log "Agendamento $id criado para $($sams.Count) usuário(s). Ao liberar: $txtLib. Logs das execuções: $($script:LogDir)" 'INFO'
        }
        catch {
            Write-Log "Erro ao criar agendamento: $($_.Exception.Message)" 'ERROR'
            foreach ($nome in @("LogonHours-Ferias-$id-Bloquear", "LogonHours-Ferias-$id-Liberar")) {
                Unregister-ScheduledTask -TaskName $nome -TaskPath $script:TaskPath -Confirm:$false -ErrorAction SilentlyContinue
            }
        }
        finally {
            $senha = $null
            $dlg.Cursor = 'Default'
        }
        $btnRefresh.PerformClick()
    })

    $dlg.Add_Shown({
        $btnLoad.PerformClick()
        $btnRefresh.PerformClick()
    })

    $logAnterior   = $script:txtLog
    $script:txtLog = $dlgLog
    try { [void]$dlg.ShowDialog($form) }
    finally { $script:txtLog = $logAnterior }
}

# =========================================================
# INTERFACE
# =========================================================
$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Gerenciador de Logon - Active Directory e Microsoft 365'
$form.ClientSize      = New-Object System.Drawing.Size(1000, 740)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox     = $false
$form.Font            = New-Object System.Drawing.Font('Segoe UI', 9)

# --- Usuários manuais ---
$gbUsers = New-Object System.Windows.Forms.GroupBox
$gbUsers.Text     = 'Usuários (login, nome/CN, e-mail ou DN)'
$gbUsers.Location = New-Object System.Drawing.Point(12, 12)
$gbUsers.Size     = New-Object System.Drawing.Size(335, 200)

$txtAddUser = New-Object System.Windows.Forms.TextBox
$txtAddUser.Location = New-Object System.Drawing.Point(10, 24)
$txtAddUser.Size     = New-Object System.Drawing.Size(315, 24)

$btnAddUser = New-Object System.Windows.Forms.Button
$btnAddUser.Text     = 'Adicionar'
$btnAddUser.Location = New-Object System.Drawing.Point(10, 54)
$btnAddUser.Size     = New-Object System.Drawing.Size(100, 26)

$btnRemUser = New-Object System.Windows.Forms.Button
$btnRemUser.Text     = 'Remover'
$btnRemUser.Location = New-Object System.Drawing.Point(118, 54)
$btnRemUser.Size     = New-Object System.Drawing.Size(100, 26)

$btnClearUsers = New-Object System.Windows.Forms.Button
$btnClearUsers.Text     = 'Limpar'
$btnClearUsers.Location = New-Object System.Drawing.Point(226, 54)
$btnClearUsers.Size     = New-Object System.Drawing.Size(99, 26)

$lstUsers = New-Object System.Windows.Forms.ListBox
$lstUsers.Location            = New-Object System.Drawing.Point(10, 88)
$lstUsers.Size                = New-Object System.Drawing.Size(315, 102)
$lstUsers.HorizontalScrollbar = $true
$lstUsers.SelectionMode       = 'MultiExtended'

$gbUsers.Controls.AddRange(@($txtAddUser, $btnAddUser, $btnRemUser, $btnClearUsers, $lstUsers))

# --- OUs ---
$gbOU = New-Object System.Windows.Forms.GroupBox
$gbOU.Text     = 'OUs - digite o DN ou escolha na lista (opcional)'
$gbOU.Location = New-Object System.Drawing.Point(12, 220)
$gbOU.Size     = New-Object System.Drawing.Size(335, 225)

$cmbOU = New-Object System.Windows.Forms.ComboBox
$cmbOU.DropDownStyle = 'DropDown'
$cmbOU.Location      = New-Object System.Drawing.Point(10, 24)
$cmbOU.Size          = New-Object System.Drawing.Size(315, 24)

$btnAddOU = New-Object System.Windows.Forms.Button
$btnAddOU.Text     = 'Adicionar'
$btnAddOU.Location = New-Object System.Drawing.Point(10, 54)
$btnAddOU.Size     = New-Object System.Drawing.Size(100, 26)

$btnRemOU = New-Object System.Windows.Forms.Button
$btnRemOU.Text     = 'Remover'
$btnRemOU.Location = New-Object System.Drawing.Point(118, 54)
$btnRemOU.Size     = New-Object System.Drawing.Size(100, 26)

$lstOUs = New-Object System.Windows.Forms.ListBox
$lstOUs.Location           = New-Object System.Drawing.Point(10, 88)
$lstOUs.Size               = New-Object System.Drawing.Size(315, 125)
$lstOUs.HorizontalScrollbar = $true

$gbOU.Controls.AddRange(@($cmbOU, $btnAddOU, $btnRemOU, $lstOUs))

# --- Ação ---
$gbAction = New-Object System.Windows.Forms.GroupBox
$gbAction.Text     = 'Ação'
$gbAction.Location = New-Object System.Drawing.Point(12, 453)
$gbAction.Size     = New-Object System.Drawing.Size(335, 120)

$rbBloquear = New-Object System.Windows.Forms.RadioButton
$rbBloquear.Text     = 'Bloquear logon (todos os horários)'
$rbBloquear.Checked  = $true
$rbBloquear.AutoSize = $true
$rbBloquear.Location = New-Object System.Drawing.Point(14, 24)

$rbLiberar = New-Object System.Windows.Forms.RadioButton
$rbLiberar.Text     = 'Liberar logon (remove a restrição)'
$rbLiberar.AutoSize = $true
$rbLiberar.Location = New-Object System.Drawing.Point(14, 48)

$rbHorario = New-Object System.Windows.Forms.RadioButton
$rbHorario.Text     = 'Definir horário permitido (dias/horas ao lado)'
$rbHorario.AutoSize = $true
$rbHorario.Location = New-Object System.Drawing.Point(14, 72)

$chkSim = New-Object System.Windows.Forms.CheckBox
$chkSim.Text     = 'Modo simulação (não altera o AD)'
$chkSim.AutoSize = $true
$chkSim.Location = New-Object System.Drawing.Point(14, 96)

$gbAction.Controls.AddRange(@($rbBloquear, $rbLiberar, $rbHorario, $chkSim))

# --- Horário permitido (dias + horas) ---
$gbSched = New-Object System.Windows.Forms.GroupBox
$gbSched.Text     = 'Horário permitido (usado na ação "Definir horário permitido")'
$gbSched.Location = New-Object System.Drawing.Point(362, 10)
$gbSched.Size     = New-Object System.Drawing.Size(626, 114)
$gbSched.Enabled  = $false

$chkDays = @()
for ($i = 0; $i -lt 7; $i++) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text     = $script:DayNames[$i]
    $c.Tag      = $i
    $c.AutoSize = $true
    $c.Location = New-Object System.Drawing.Point((14 + $i * 62), 24)
    $c.Checked  = ($i -ge 1 -and $i -le 5)
    $chkDays   += $c
}

$btnSegSex = New-Object System.Windows.Forms.Button
$btnSegSex.Text     = 'Seg-Sex'
$btnSegSex.Location = New-Object System.Drawing.Point(460, 20)
$btnSegSex.Size     = New-Object System.Drawing.Size(74, 26)

$btnTodos = New-Object System.Windows.Forms.Button
$btnTodos.Text     = 'Todos'
$btnTodos.Location = New-Object System.Drawing.Point(540, 20)
$btnTodos.Size     = New-Object System.Drawing.Size(74, 26)

$lblDas = New-Object System.Windows.Forms.Label
$lblDas.Text     = 'Liberar das'
$lblDas.AutoSize = $true
$lblDas.Location = New-Object System.Drawing.Point(14, 64)

$nudStart = New-Object System.Windows.Forms.NumericUpDown
$nudStart.Minimum  = 0
$nudStart.Maximum  = 23
$nudStart.Value    = 8
$nudStart.Location = New-Object System.Drawing.Point(84, 60)
$nudStart.Size     = New-Object System.Drawing.Size(55, 24)

$lblAte = New-Object System.Windows.Forms.Label
$lblAte.Text     = 'h  até'
$lblAte.AutoSize = $true
$lblAte.Location = New-Object System.Drawing.Point(142, 64)

$nudEnd = New-Object System.Windows.Forms.NumericUpDown
$nudEnd.Minimum  = 1
$nudEnd.Maximum  = 24
$nudEnd.Value    = 18
$nudEnd.Location = New-Object System.Drawing.Point(186, 60)
$nudEnd.Size     = New-Object System.Drawing.Size(55, 24)

$lblFim = New-Object System.Windows.Forms.Label
$lblFim.AutoSize = $true
$lblFim.Location = New-Object System.Drawing.Point(246, 64)

$off = [TimeZoneInfo]::Local.GetUtcOffset([DateTime]::Now)
$sinal = if ($off.Ticks -lt 0) { '-' } else { '+' }
$lblFuso = New-Object System.Windows.Forms.Label
$lblFuso.Text      = "Fuso local: UTC$sinal$($off.ToString('hh\:mm')) - convertido automaticamente para UTC ao gravar no AD."
$lblFuso.AutoSize  = $true
$lblFuso.ForeColor = [System.Drawing.Color]::DimGray
$lblFuso.Location  = New-Object System.Drawing.Point(14, 90)

$gbSched.Controls.AddRange(@($btnSegSex, $btnTodos, $lblDas, $nudStart, $lblAte, $nudEnd, $lblFim, $lblFuso))
$gbSched.Controls.AddRange([System.Windows.Forms.Control[]]$chkDays)

# --- Botões ---
$btnPreview = New-Object System.Windows.Forms.Button
$btnPreview.Text     = '1. Pré-visualizar'
$btnPreview.Location = New-Object System.Drawing.Point(12, 578)
$btnPreview.Size     = New-Object System.Drawing.Size(165, 34)

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text      = '2. Aplicar'
$btnApply.Location  = New-Object System.Drawing.Point(182, 578)
$btnApply.Size      = New-Object System.Drawing.Size(165, 34)
$btnApply.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnApply.ForeColor = [System.Drawing.Color]::White
$btnApply.FlatStyle = 'Flat'

# --- Pré-visualização ---
$lblPrev = New-Object System.Windows.Forms.Label
$lblPrev.Text     = 'Pré-visualização dos usuários-alvo'
$lblPrev.AutoSize = $true
$lblPrev.Location = New-Object System.Drawing.Point(362, 134)

$lblCount = New-Object System.Windows.Forms.Label
$lblCount.Text      = ''
$lblCount.AutoSize  = $false
$lblCount.TextAlign = 'MiddleRight'
$lblCount.Location  = New-Object System.Drawing.Point(800, 130)
$lblCount.Size      = New-Object System.Drawing.Size(188, 22)

$lvUsers = New-Object System.Windows.Forms.ListView
$lvUsers.View          = 'Details'
$lvUsers.FullRowSelect = $true
$lvUsers.GridLines     = $true
$lvUsers.Location      = New-Object System.Drawing.Point(362, 156)
$lvUsers.Size          = New-Object System.Drawing.Size(626, 414)
[void]$lvUsers.Columns.Add('Usuário', 130)
[void]$lvUsers.Columns.Add('Nome', 180)
[void]$lvUsers.Columns.Add('Ativo', 50)
[void]$lvUsers.Columns.Add('Logon atual', 240)

$btnRevoke = New-Object System.Windows.Forms.Button
$btnRevoke.Text     = 'Revogar sessões 365 (Entra ID)...'
$btnRevoke.Location = New-Object System.Drawing.Point(362, 576)
$btnRevoke.Size     = New-Object System.Drawing.Size(308, 36)

$btnAgenda = New-Object System.Windows.Forms.Button
$btnAgenda.Text     = 'Agendar bloqueio / liberação (férias)...'
$btnAgenda.Location = New-Object System.Drawing.Point(680, 576)
$btnAgenda.Size     = New-Object System.Drawing.Size(308, 36)

# --- Log ---
$script:txtLog = New-Object System.Windows.Forms.RichTextBox
$script:txtLog.Location  = New-Object System.Drawing.Point(12, 618)
$script:txtLog.Size      = New-Object System.Drawing.Size(976, 112)
$script:txtLog.ReadOnly  = $true
$script:txtLog.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$script:txtLog.Font      = New-Object System.Drawing.Font('Consolas', 9)

$form.Controls.AddRange(@($gbUsers, $gbOU, $gbAction, $gbSched, $btnPreview, $btnApply,
                          $lblPrev, $lblCount, $lvUsers, $btnRevoke, $btnAgenda, $script:txtLog))

# =========================================================
# EVENTOS
# =========================================================
$rbHorario.Add_CheckedChanged({ $gbSched.Enabled = $rbHorario.Checked })

$updateFim = {
    $lblFim.Text = "(último logon permitido: {0:00}:59)" -f ([int]$nudEnd.Value - 1)
}
$nudEnd.Add_ValueChanged($updateFim)
& $updateFim

$btnSegSex.Add_Click({ foreach ($c in $chkDays) { $c.Checked = ($c.Tag -ge 1 -and $c.Tag -le 5) } })
$btnTodos.Add_Click({ foreach ($c in $chkDays) { $c.Checked = $true } })

$btnRevoke.Add_Click({ Show-RevokeDialog })
$btnAgenda.Add_Click({ Show-ScheduleDialog })

$btnAddUser.Add_Click({
    Add-UserInputs -Text $txtAddUser.Text
    $txtAddUser.Clear()
    $txtAddUser.Focus()
})

$txtAddUser.Add_KeyDown({
    if ($_.KeyCode -eq 'Enter') {
        $_.SuppressKeyPress = $true
        $btnAddUser.PerformClick()
    }
})

$btnRemUser.Add_Click({
    $sel = @($lstUsers.SelectedItems)
    foreach ($s in $sel) { $lstUsers.Items.Remove($s) }
})

$btnClearUsers.Add_Click({ $lstUsers.Items.Clear() })

$btnAddOU.Add_Click({
    $v = $cmbOU.Text.Trim()
    if ($v -and -not $lstOUs.Items.Contains($v)) { [void]$lstOUs.Items.Add($v) }
    $cmbOU.Text = ''
})

$cmbOU.Add_KeyDown({
    if ($_.KeyCode -eq 'Enter') {
        $_.SuppressKeyPress = $true
        $btnAddOU.PerformClick()
    }
})

$btnRemOU.Add_Click({
    if ($lstOUs.SelectedIndex -ge 0) { $lstOUs.Items.RemoveAt($lstOUs.SelectedIndex) }
})

$btnPreview.Add_Click({
    $form.Cursor = 'WaitCursor'
    try {
        $lvUsers.Items.Clear()
        $targets = Get-Targets
        foreach ($t in $targets) {
            if ($t.User) {
                $u    = $t.User
                $item = New-Object System.Windows.Forms.ListViewItem($u.SamAccountName)
                $nome = if ($u.DisplayName) { $u.DisplayName } else { $u.Name }
                [void]$item.SubItems.Add($nome)
                [void]$item.SubItems.Add($(if ($u.Enabled) { 'Sim' } else { 'Não' }))
                [void]$item.SubItems.Add((Get-LogonStatus $u.logonHours))
            }
            else {
                $item = New-Object System.Windows.Forms.ListViewItem($t.Input)
                [void]$item.SubItems.Add('-')
                [void]$item.SubItems.Add('-')
                [void]$item.SubItems.Add($t.Erro)
                $item.ForeColor = [System.Drawing.Color]::Firebrick
            }
            [void]$lvUsers.Items.Add($item)
        }
        $lblCount.Text = "$($targets.Count) usuário(s)"
    }
    finally {
        $form.Cursor = 'Default'
    }
})

$btnApply.Add_Click({
    $tipo    = if ($rbBloquear.Checked) { 'bloquear' } elseif ($rbLiberar.Checked) { 'liberar' } else { 'horario' }
    $simular = $chkSim.Checked
    $targets = Get-Targets

    if ($targets.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Nenhum usuário informado.', 'Atenção', 'OK', 'Warning') | Out-Null
        return
    }

    $detalhe = ''
    if ($tipo -eq 'horario') {
        $dias = @($chkDays | Where-Object { $_.Checked } | ForEach-Object { [int]$_.Tag })
        $ini  = [int]$nudStart.Value
        $fim  = [int]$nudEnd.Value
        if ($dias.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('Marque ao menos um dia da semana.', 'Atenção', 'OK', 'Warning') | Out-Null
            return
        }
        if ($fim -le $ini) {
            [System.Windows.Forms.MessageBox]::Show('A hora final deve ser maior que a hora inicial.', 'Atenção', 'OK', 'Warning') | Out-Null
            return
        }
        $detalhe = ' ({0} {1:00}:00-{2:00}:59)' -f (Format-Days -Days $dias), $ini, ($fim - 1)
    }

    $acao = switch ($tipo) { 'bloquear' { 'BLOQUEAR' } 'liberar' { 'LIBERAR' } default { 'DEFINIR HORÁRIO' } }
    $modo = if ($simular) { ' (SIMULAÇÃO)' } else { '' }
    $qtd  = @($targets | Where-Object { $_.User }).Count
    $pergunta = switch ($tipo) {
        'bloquear' { "Deseja BLOQUEAR o logon de $qtd usuário(s)?" }
        'liberar'  { "Deseja LIBERAR o logon de $qtd usuário(s)?" }
        default    { "Deseja DEFINIR o horário de logon$detalhe para $qtd usuário(s)?" }
    }
    $resp = [System.Windows.Forms.MessageBox]::Show("$pergunta$modo", 'Confirmação', 'YesNo', 'Question')
    if ($resp -ne 'Yes') { return }

    $btnApply.Enabled   = $false
    $btnPreview.Enabled = $false
    $form.Cursor        = 'WaitCursor'

    try {
        # 21 bytes = 168 horas da semana; 0 = tudo negado
        $byteArray = New-Object byte[] 21
        if ($tipo -eq 'horario') {
            $byteHorario = New-LogonHoursBytes -Days $dias -StartHour $ini -EndHour $fim
        }

        Write-Log "Iniciando processo: $acao LogonHours$detalhe$modo" 'INFO'
        $sucessos = 0
        $erros    = 0

        foreach ($t in $targets) {
            if (-not $t.User) {
                Write-Log "Usuário '$($t.Input)' não processado: $($t.Erro)" 'ERROR'
                $erros++
                continue
            }
            $user = $t.User.SamAccountName
            if ($user -ieq $env:USERNAME) {
                Write-Log "Usuário '$user' é a conta atual - ignorado para evitar auto-bloqueio." 'WARNING'
                continue
            }
            try {
                if ($simular) {
                    Write-Log "SIMULAÇÃO: $acao$detalhe aplicado ao usuário '$user' (nenhuma alteração feita)." 'WARNING'
                }
                elseif ($tipo -eq 'bloquear') {
                    Set-ADUser -Identity $user -Replace @{ logonHours = $byteArray } -ErrorAction Stop
                    Write-Log "Bloqueio total aplicado com sucesso para o usuário: '$user'" 'SUCCESS'
                }
                elseif ($tipo -eq 'liberar') {
                    Set-ADUser -Identity $user -Clear logonHours -ErrorAction Stop
                    Write-Log "Restrição de horário removida para o usuário: '$user'" 'SUCCESS'
                }
                else {
                    Set-ADUser -Identity $user -Replace @{ logonHours = $byteHorario } -ErrorAction Stop
                    Write-Log "Horário configurado com sucesso$detalhe para o usuário: '$user'" 'SUCCESS'
                }
                $sucessos++
            }
            catch {
                Write-Log "Falha ao aplicar alterações no usuário '$user': $_" 'ERROR'
                $erros++
            }
        }

        Write-Log "Processo concluído. Sucessos: $sucessos | Falhas: $erros" 'INFO'
        Write-Log "Arquivo de log salvo em: $($script:LogPath)" 'INFO'
    }
    finally {
        $btnApply.Enabled   = $true
        $btnPreview.Enabled = $true
        $form.Cursor        = 'Default'
    }

    if (-not $simular) { $btnPreview.PerformClick() }
})

$form.Add_Shown({
    Write-Log "Interface iniciada. Log: $($script:LogPath)" 'INFO'
    try {
        $ous = Get-ADOrganizationalUnit -Filter * -ErrorAction Stop |
               Sort-Object DistinguishedName |
               Select-Object -ExpandProperty DistinguishedName
        if ($ous) { $cmbOU.Items.AddRange([object[]]$ous) }
        Write-Log "$(@($ous).Count) OUs carregadas na lista." 'INFO'
    }
    catch {
        Write-Log "Não foi possível listar as OUs: $_" 'WARNING'
    }
})

[void]$form.ShowDialog()
