[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$VeeamServer = "192.168.100.31"
$LogPath     = "\\192.168.100.34\Share\TI\Logs Veeam"
$Horas       = 24

# 1. Credencial do compartilhamento de rede
Write-Host "Digite o usuário e senha com acesso ao COMPARTILHAMENTO DE REDE (192.168.100.34)..." -ForegroundColor Yellow
$NetCred = Get-Credential crn3.sp\administrator

if (-not (Get-PSDrive -Name "ShareLogs" -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name "ShareLogs" -PSProvider FileSystem -Root "\\192.168.100.34\Share" -Credential $NetCred | Out-Null
}
if (-not (Test-Path -Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
$logFile   = Join-Path -Path $LogPath -ChildPath "Relatorio_Veeam_$timestamp.txt"

# 2. Credencial do servidor Veeam
Write-Host "Digite o usuário e senha com acesso ao SERVIDOR VEEAM ($VeeamServer)..." -ForegroundColor Cyan
$VeeamCred = Get-Credential crn3.sp\administrator

try {
    $json = Invoke-Command -ComputerName $VeeamServer -Credential $VeeamCred -ArgumentList $Horas -ErrorAction Stop -ScriptBlock {
        param($Horas)
        $ErrorActionPreference = 'Stop'

        # O módulo do Veeam exige PowerShell 7.x: localiza o pwsh.exe no servidor
        $pwsh = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
        if (-not (Test-Path $pwsh)) {
            $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue
            if ($cmd) { $pwsh = $cmd.Source }
            else { throw "pwsh.exe (PowerShell 7) não encontrado em $env:COMPUTERNAME. Instale o PowerShell 7.6 ou superior no servidor Veeam." }
        }

        # Código executado dentro do PowerShell 7
        $inner = @'
$ErrorActionPreference = 'Stop'
try {
Import-Module Veeam.Backup.PowerShell -DisableNameChecking
$fqdn = [System.Net.Dns]::GetHostEntry($env:COMPUTERNAME).HostName
$conectado = $false
$erros = @()
foreach ($alvo in @($fqdn, $env:COMPUTERNAME, 'localhost')) {
    try {
        Connect-VBRServer -Server $alvo -ForceAcceptTlsCertificate
        $conectado = $true
        break
    }
    catch {
        $det = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { '' }
        $erros += ($alvo + ' -> ' + $_.Exception.Message + ' ' + $det)
    }
}
if (-not $conectado) { throw ($erros -join ' || ') }
try {
    $startDate = (Get-Date).AddHours(-__HORAS__)
    $rows = Get-VBRBackupSession |
        Where-Object { $_.CreationTime -ge $startDate -or $_.EndTime -ge $startDate } |
        ForEach-Object {
            $session = $_
            $readBytes = 0
            $transferredBytes = 0

            if ($session.Progress) {
                $readBytes        = $session.Progress.ReadSize
                $transferredBytes = $session.Progress.TransferedSize
            }

            if ($transferredBytes -eq 0) {
                try {
                    foreach ($task in $session.GetTaskSessions()) {
                        if ($task.Progress) {
                            if ($readBytes -eq 0) { $readBytes += $task.Progress.ReadSize }
                            $transferredBytes += $task.Progress.TransferedSize
                        }
                    }
                } catch {}
            }

            if ($transferredBytes -eq 0 -and $session.Result -ne "Failed") {
                try {
                    foreach ($l in $session.GetLogRecords()) {
                        if ($l.Title -match "(?:Transferred|Transferido)[:\s]+([\d\.\,]+)\s*(KB|MB|GB|TB)") {
                            $val = [double]($matches[1] -replace ',', '.')
                            switch ($matches[2].ToUpper()) {
                                'KB' { $transferredBytes += ($val * 1KB) }
                                'MB' { $transferredBytes += ($val * 1MB) }
                                'GB' { $transferredBytes += ($val * 1GB) }
                                'TB' { $transferredBytes += ($val * 1TB) }
                            }
                        }
                    }
                } catch {}
            }

            if ($transferredBytes -eq 0 -and $readBytes -gt 0 -and $session.Result -eq "Success") {
                $transferredBytes = $readBytes
            }

            [PSCustomObject]@{
                JobName     = [string]$session.JobName
                SessionType = [string]$session.JobType
                Status      = [string]$session.Result
                LidoGB      = [math]::Round($readBytes / 1GB, 2)
                TransfMB    = [math]::Round($transferredBytes / 1MB, 2)
                Start       = $session.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
                End         = if ($session.EndTime -ne [DateTime]::MinValue) { $session.EndTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
            }
        }
    
    # Força a serialização correta como um array JSON puro
    if ($rows) {
        $rows | ConvertTo-Json -Compress
    } else {
        @() | ConvertTo-Json -Compress
    }
}
finally {
    Disconnect-VBRServer -ErrorAction SilentlyContinue
}
}
catch {
    [Console]::Out.WriteLine('ERRO_VEEAM: ' + $_.Exception.GetType().FullName + ' | ' + $_.Exception.Message)
    exit 1
}
'@
        $inner = $inner.Replace('__HORAS__', [string]$Horas)
        $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))

        $out = & $pwsh -NoProfile -NonInteractive -EncodedCommand $enc 2>&1
        if ($LASTEXITCODE -ne 0) { throw (($out | Out-String).Trim()) }
        ($out | Out-String).Trim()
    }
}
catch {
    Write-Host "`n[ERRO] Falha ao coletar dados do Veeam: $($_.Exception.Message)" -ForegroundColor Red
    return
}

# Garante que $dados seja sempre um array, mesmo que venha apenas 1 registo ou nenhum
$dados = @()
if (-not [string]::IsNullOrWhiteSpace($json)) {
    $parsed = $json | ConvertFrom-Json
    if ($parsed) { $dados = @($parsed) }
}

if ($dados.Count -eq 0) {
    $report = "Nenhuma sessão do Veeam encontrada nas últimas $Horas horas.`r`n"
} else {
    $report = $dados | Sort-Object Start -Descending | Select-Object `
        @{N='Job Name';         E={$_.JobName}},
        @{N='Session Type';     E={$_.SessionType}},
        @{N='Status';           E={$_.Status}},
        @{N='Lido (GB)';        E={$_.LidoGB}},
        @{N='Transferido (MB)'; E={$_.TransfMB}},
        @{N='Start Time';       E={([datetime]::ParseExact($_.Start,'yyyy-MM-dd HH:mm:ss',$null)).ToString('dd/MM/yyyy HH:mm:ss')}},
        @{N='End Time';         E={ if ($_.End) { ([datetime]::ParseExact($_.End,'yyyy-MM-dd HH:mm:ss',$null)).ToString('dd/MM/yyyy HH:mm:ss') } else { 'Running' } }} |
        Format-Table -AutoSize | Out-String -Width 400
}

Write-Host $report
$report | Out-File -FilePath $logFile -Encoding utf8 -Force

if (Test-Path -Path $logFile) {
    Write-Host "`n[SUCESSO] Relatório gerado com sucesso!" -ForegroundColor Green
    Write-Host "Arquivo salvo em: $logFile" -ForegroundColor Yellow
} else {
    Write-Host "`n[ERRO] Não foi possível criar o arquivo no destino de rede." -ForegroundColor Red
}