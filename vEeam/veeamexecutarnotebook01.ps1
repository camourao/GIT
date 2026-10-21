# Força codificação UTF-8 no console
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Mapeamento para o caminho de rede UNC
$LogPath  = "\\192.168.100.34\Share\TI\Logs Veeam"

# 1. Pede credencial para acessar o Servidor de Arquivos (192.168.100.34)
Write-Host "Digite o usuário e senha com acesso ao COMPARTILHAMENTO DE REDE (192.168.100.34)..." -ForegroundColor Yellow
$NetCred = Get-Credential

if (-not (Get-PSDrive -Name "ShareLogs" -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name "ShareLogs" -PSProvider FileSystem -Root "\\192.168.100.34\Share" -Credential $NetCred | Out-Null
}

if (-not (Test-Path -Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
$logFile = Join-Path -Path $logPath -ChildPath "Relatorio_Veeam_$timestamp.txt"

# 2. Pede credencial para acessar o Servidor VEEAM (192.168.100.31)
Write-Host "Digite o usuário e senha com acesso ao SERVIDOR VEEAM (192.168.100.31)..." -ForegroundColor Cyan
$VeeamCred = Get-Credential

$report = Invoke-Command -ComputerName "192.168.100.31" -Credential $VeeamCred -ScriptBlock {
    Import-Module Veeam.Backup.PowerShell -ErrorAction SilentlyContinue
    Add-PSSnapin VeeamPSSnapIn -ErrorAction SilentlyContinue

    Connect-VBRServer -Server "localhost"

    $startDate = (Get-Date).AddHours(-24)

    Get-VBRBackupSession | Where-Object { $_.CreationTime -ge $startDate } | ForEach-Object {
        $session = $_
        
        $readBytes = 0
        $transferredBytes = 0

        if ($session.Progress) {
            $readBytes = $session.Progress.ReadSize
            $transferredBytes = $session.Progress.TransferedSize
        }

        if ($transferredBytes -eq 0) {
            try {
                $tasks = $session.GetTaskSessions()
                foreach ($task in $tasks) {
                    if ($task.Progress) {
                        if ($readBytes -eq 0) { $readBytes += $task.Progress.ReadSize }
                        $transferredBytes += $task.Progress.TransferedSize
                    }
                }
            } catch {}
        }

        if ($transferredBytes -eq 0 -and $session.Result -ne "Failed") {
            try {
                $logs = $session.GetLogRecords()
                foreach ($l in $logs) {
                    if ($l.Title -match "(?:Transferred|Transferido)[:\s]+([\d\.\,]+)\s*(KB|MB|GB|TB)") {
                        $val = [double]($matches[1] -replace ',', '.')
                        $unit = $matches[2].ToUpper()
                        switch ($unit) {
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
            'Job Name'         = $session.JobName
            'Session Type'     = $session.JobType
            'Status'           = $session.Result
            'Lido (GB)'        = [math]::Round($readBytes / 1GB, 2)
            'Transferido (MB)' = [math]::Round($transferredBytes / 1MB, 2)
            'Start Time'       = $session.CreationTime.ToString("dd/MM/yyyy HH:mm:ss")
            'End Time'         = if ($session.EndTime -ne [DateTime]::MinValue) { $session.EndTime.ToString("dd/MM/yyyy HH:mm:ss") } else { "Running" }
        }
    } | Sort-Object 'Start Time' -Descending
} | Format-Table 'Job Name', 'Session Type', 'Status', 'Lido (GB)', 'Transferido (MB)', 'Start Time', 'End Time' -AutoSize | Out-String

# Exibe o resultado no console
Write-Host $report

# Grava no arquivo com codificação UTF-8 utilizando o cmdlet nativo
$report | Out-File -FilePath $logFile -Encoding utf8 -Force

# Confirmação na tela
if (Test-Path -Path $logFile) {
    Write-Host "`n[SUCESSO] Relatorio e volumetria gerados com sucesso!" -ForegroundColor Green
    Write-Host "Arquivo salvo em: $logFile" -ForegroundColor Yellow
} else {
    Write-Host "`n[ERRO] Nao foi possivel criar o arquivo no destino de rede." -ForegroundColor Red
}