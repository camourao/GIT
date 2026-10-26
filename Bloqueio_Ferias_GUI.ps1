\xEF\xBB\xBF#Requires -Version 5.1
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
$script:UserProps = @('logonHours', 'DisplayName', 'Enabled')

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

function Get-LogonStatus {
    param($LogonHours)
    if ($null -eq $LogonHours -or $LogonHours.Count -eq 0) { return 'Sem restrição' }
    $nonZero = @($LogonHours | Where-Object { $_ -ne 0 }).Count
    $notFull = @($LogonHours | Where-Object { $_ -ne 255 }).Count
    if ($nonZero -eq 0) { return 'Bloqueado total' }
    if ($notFull -eq 0) { return 'Sem restrição' }
    return 'Horário parcial'
}

# =========================================================
# INTERFACE
# =========================================================
$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Bloqueio de Logon (Férias) - Active Directory'
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
$gbAction.Size     = New-Object System.Drawing.Size(335, 108)

$rbBloquear = New-Object System.Windows.Forms.RadioButton
$rbBloquear.Text     = 'Bloquear logon (todos os horários)'
$rbBloquear.Checked  = $true
$rbBloquear.AutoSize = $true
$rbBloquear.Location = New-Object System.Drawing.Point(14, 24)

$rbLiberar = New-Object System.Windows.Forms.RadioButton
$rbLiberar.Text     = 'Liberar logon (remove a restrição)'
$rbLiberar.AutoSize = $true
$rbLiberar.Location = New-Object System.Drawing.Point(14, 50)

$chkSim = New-Object System.Windows.Forms.CheckBox
$chkSim.Text     = 'Modo simulação (não altera o AD)'
$chkSim.AutoSize = $true
$chkSim.Location = New-Object System.Drawing.Point(14, 78)

$gbAction.Controls.AddRange(@($rbBloquear, $rbLiberar, $chkSim))

# --- Botões ---
$btnPreview = New-Object System.Windows.Forms.Button
$btnPreview.Text     = '1. Pré-visualizar'
$btnPreview.Location = New-Object System.Drawing.Point(12, 572)
$btnPreview.Size     = New-Object System.Drawing.Size(165, 36)

$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text      = '2. Aplicar'
$btnApply.Location  = New-Object System.Drawing.Point(182, 572)
$btnApply.Size      = New-Object System.Drawing.Size(165, 36)
$btnApply.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnApply.ForeColor = [System.Drawing.Color]::White
$btnApply.FlatStyle = 'Flat'

# --- Pré-visualização ---
$lblPrev = New-Object System.Windows.Forms.Label
$lblPrev.Text     = 'Pré-visualização dos usuários-alvo'
$lblPrev.AutoSize = $true
$lblPrev.Location = New-Object System.Drawing.Point(362, 16)

$lblCount = New-Object System.Windows.Forms.Label
$lblCount.Text      = ''
$lblCount.AutoSize  = $false
$lblCount.TextAlign = 'MiddleRight'
$lblCount.Location  = New-Object System.Drawing.Point(800, 12)
$lblCount.Size      = New-Object System.Drawing.Size(188, 22)

$lvUsers = New-Object System.Windows.Forms.ListView
$lvUsers.View          = 'Details'
$lvUsers.FullRowSelect = $true
$lvUsers.GridLines     = $true
$lvUsers.Location      = New-Object System.Drawing.Point(362, 38)
$lvUsers.Size          = New-Object System.Drawing.Size(626, 570)
[void]$lvUsers.Columns.Add('Usuário', 160)
[void]$lvUsers.Columns.Add('Nome', 220)
[void]$lvUsers.Columns.Add('Ativo', 55)
[void]$lvUsers.Columns.Add('Logon atual', 170)

# --- Log ---
$script:txtLog = New-Object System.Windows.Forms.RichTextBox
$script:txtLog.Location  = New-Object System.Drawing.Point(12, 618)
$script:txtLog.Size      = New-Object System.Drawing.Size(976, 112)
$script:txtLog.ReadOnly  = $true
$script:txtLog.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$script:txtLog.Font      = New-Object System.Drawing.Font('Consolas', 9)

$form.Controls.AddRange(@($gbUsers, $gbOU, $gbAction, $btnPreview, $btnApply,
                          $lblPrev, $lblCount, $lvUsers, $script:txtLog))

# =========================================================
# EVENTOS
# =========================================================
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
    $bloquear = $rbBloquear.Checked
    $simular  = $chkSim.Checked
    $targets  = Get-Targets

    if ($targets.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Nenhum usuário informado.', 'Atenção', 'OK', 'Warning') | Out-Null
        return
    }

    $acao = if ($bloquear) { 'BLOQUEAR' } else { 'LIBERAR' }
    $modo = if ($simular) { ' (SIMULAÇÃO)' } else { '' }
    $resp = [System.Windows.Forms.MessageBox]::Show(
        "Deseja $acao o logon de $(@($targets | Where-Object { $_.User }).Count) usuário(s)?$modo",
        'Confirmação', 'YesNo', 'Question')
    if ($resp -ne 'Yes') { return }

    $btnApply.Enabled   = $false
    $btnPreview.Enabled = $false
    $form.Cursor        = 'WaitCursor'

    try {
        # 21 bytes = 168 horas da semana; 0 = tudo negado
        $byteArray = New-Object byte[] 21

        Write-Log "Iniciando processo: $acao LogonHours$modo" 'INFO'
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
                    Write-Log "SIMULAÇÃO: $acao aplicado ao usuário '$user' (nenhuma alteração feita)." 'WARNING'
                }
                elseif ($bloquear) {
                    Set-ADUser -Identity $user -Replace @{ logonHours = $byteArray } -ErrorAction Stop
                    Write-Log "Bloqueio total aplicado com sucesso para o usuário: '$user'" 'SUCCESS'
                }
                else {
                    Set-ADUser -Identity $user -Clear logonHours -ErrorAction Stop
                    Write-Log "Restrição de horário removida para o usuário: '$user'" 'SUCCESS'
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
