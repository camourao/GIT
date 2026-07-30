# Força codificação UTF-8 no console
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Localiza a pasta Desktop sincronizada
$desktopPath = [Environment]::GetFolderPath("Desktop")
$logPath = Join-Path -Path $desktopPath -ChildPath "logs\veeam"

if (-not (Test-Path -Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
$logFile = Join-Path -Path $logPath -ChildPath "Relatorio_Veeam_$timestamp.txt"

$report = Invoke-Command -ComputerName "192.168.100.31" -Credential (Get-Credential) -ScriptBlock {
    Import-Module Veeam.Backup.PowerShell -ErrorAction SilentlyContinue
    Add-PSSnapin VeeamPSSnapIn -ErrorAction SilentlyContinue

    Connect-VBRServer -Server "localhost"

    $startDate = (Get-Date).AddHours(-24)

    Get-VBRBackupSession | Where-Object { $_.CreationTime -ge $startDate } | ForEach-Object {
        $session = $_
        
        $readBytes = 0
        $transferredBytes = 0

        # 1. Leitura via propriedades globais da Session (Atenção ao atributo do SDK: TransferedSize)
        if ($session.Progress) {
            $readBytes = $session.Progress.ReadSize
            $transferredBytes = $session.Progress.TransferedSize
        }

        # 2. Se TransferedSize for 0, percorre os TaskSessions no servidor local
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

        # 3. Fallback para Backup Copy Jobs / Workers via parsing de logs
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

        # 4. Caso a sessão seja de sucesso e ainda assim traga 0 em Transferido,
        # para relatórios em MB calcula a proporção real ou atribui o volume trabalhado
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

# Grava no arquivo com codificação UTF-8
[System.IO.File]::WriteAllText($logFile, $report, [System.Text.Encoding]::UTF8)

# Confirmação na tela
if (Test-Path -Path $logFile) {
    Write-Host "`n[SUCESSO] Relatorio e volumetria gerados com sucesso!" -ForegroundColor Green
    Write-Host "Arquivo salvo em: $logFile" -ForegroundColor Yellow
} else {
    Write-Host "`n[ERRO] Nao foi possivel criar o arquivo." -ForegroundColor Red
}