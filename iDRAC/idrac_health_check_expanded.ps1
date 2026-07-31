# ============================================================
# iDRAC 9 - Full Health Check & Metrics (Versão Expandida)
# Saída: TXT (Rede UNC)
# Coleta: CPU, Memória, Storage, Rede, Energia, Térmico, Fans e iDRAC
# ============================================================

# ---------- CAMINHOS ----------
$BasePath = "C:\git\iDRAC"
$CsvFile  = "$BasePath\idrac_list.csv"

# Mapeamento para o caminho de rede UNC
$LogPath  = "\\192.168.100.34\Share\TI\Logs Idrac"
$LogFile  = "$LogPath\idrac_full_$(Get-Date -Format yyyyMMdd).txt"

# ---------- PREPARO ----------
if (!(Test-Path -Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

$Date = Get-Date -Format "dd/MM/yyyy HH:mm"

function Write-Log {
    param([string]$Message)
    Add-Content -Path $LogFile -Value $Message
}

Write-Log "========================================"
Write-Log "iDRAC FULL HEALTH CHECK & METRICS"
Write-Log "Data: $Date"
Write-Log "========================================"
Write-Log ""

# ---------- IMPORTA CSV ----------
if (!(Test-Path -Path $CsvFile)) {
    Write-Error "Arquivo CSV não encontrado: $CsvFile"
    exit 1
}

$Servers = Import-Csv $CsvFile

# ---------- LOOP SERVIDORES ----------
foreach ($S in $Servers) {
    Write-Log "----------------------------------------"
    Write-Log "Servidor : $($S.Nome)"
    Write-Log "IP       : $($S.IP)"

    $Auth = "$($S.Usuario):$($S.Senha)"
    $BaseUrl = "https://$($S.IP)/redfish/v1"

    # ---------- TESTE iDRAC ----------
    try {
        $BaseTest = cmd.exe /c "curl -k -u $Auth $BaseUrl -s"
        if ([string]::IsNullOrWhiteSpace($BaseTest)) { throw "Offline" }
    } catch {
        Write-Log "iDRAC Status     : OFFLINE"
        Write-Log ""
        continue
    }

    Write-Log "iDRAC Status     : ONLINE"

    # ---------- SISTEMA GERAL ----------
    $SystemInfo = cmd.exe /c "curl -k -u $Auth $BaseUrl/Systems/System.Embedded.1 -s" | ConvertFrom-Json
    Write-Log "Health Geral     : $($SystemInfo.Status.Health)"
    Write-Log "Power State      : $($SystemInfo.PowerState)"
    Write-Log "Modelo           : $($SystemInfo.Model)"
    Write-Log "Service Tag      : $($SystemInfo.SKU)"
    Write-Log "BIOS Version     : $($SystemInfo.BiosVersion)"
    Write-Log ""

    # ---------- CPU / PROCESSADORES ----------
    Write-Log "[ CPU / PROCESSADORES ]"
    $ProcessorsJson = cmd.exe /c "curl -k -u $Auth $BaseUrl/Systems/System.Embedded.1/Processors -s" | ConvertFrom-Json
    foreach ($Proc in $ProcessorsJson.Members) {
        $ProcDetail = cmd.exe /c "curl -k -u $Auth https://$($S.IP)$($Proc.'@odata.id') -s" | ConvertFrom-Json
        Write-Log "ID: $($ProcDetail.Id) | Modelo: $($ProcDetail.Model) | Cores: $($ProcDetail.TotalCores) | Health: $($ProcDetail.Status.Health)"
    }
    Write-Log ""

    # ---------- MEMORIA ----------
    Write-Log "[ MEMORIA ]"
    if ($SystemInfo.MemorySummary.TotalSystemMemoryGiB) {
        Write-Log "Total: $($SystemInfo.MemorySummary.TotalSystemMemoryGiB) GB | Health: $($SystemInfo.MemorySummary.Status.Health)"
    }
    $MemoryJson = cmd.exe /c "curl -k -u $Auth $BaseUrl/Systems/System.Embedded.1/Memory -s" | ConvertFrom-Json
    foreach ($Mem in $MemoryJson.Members) {
        $MemDetail = cmd.exe /c "curl -k -u $Auth https://$($S.IP)$($Mem.'@odata.id') -s" | ConvertFrom-Json
        if ($MemDetail.Status.State -ne "Absent") {
            Write-Log "Slot: $($MemDetail.Id) | Size: $($MemDetail.CapacityMiB / 1024) GB | Type: $($MemDetail.MemoryDeviceType) | Health: $($MemDetail.Status.Health)"
        }
    }
    Write-Log ""

    # ---------- STORAGE ----------
    Write-Log "[ STORAGE / DISCOS ]"
    $StorageJson = cmd.exe /c "curl -k -u $Auth $BaseUrl/Systems/System.Embedded.1/Storage -s" | ConvertFrom-Json
    foreach ($Controller in $StorageJson.Members) {
        $CtrlDetail = cmd.exe /c "curl -k -u $Auth https://$($S.IP)$($Controller.'@odata.id') -s" | ConvertFrom-Json
        Write-Log "Controller: $($CtrlDetail.Name) | Health: $($CtrlDetail.Status.Health)"
        foreach ($Drive in $CtrlDetail.Drives) {
            $DriveDetail = cmd.exe /c "curl -k -u $Auth https://$($S.IP)$($Drive.'@odata.id') -s" | ConvertFrom-Json
            $SizeTB = if ($DriveDetail.CapacityBytes) { [math]::Round(($DriveDetail.CapacityBytes / 1TB), 2) } else { "N/A" }
            Write-Log "  - Disco: $($DriveDetail.Id) | Modelo: $($DriveDetail.Model) | Size: $SizeTB TB | Health: $($DriveDetail.Status.Health)"
        }
    }
    Write-Log ""

    # ---------- REDE (Network Adapters) ----------
    Write-Log "[ REDE / ADAPTADORES ]"
    $NetworkJson = cmd.exe /c "curl -k -u $Auth $BaseUrl/Systems/System.Embedded.1/NetworkAdapters -s" | ConvertFrom-Json
    foreach ($Net in $NetworkJson.Members) {
        $NetDetail = cmd.exe /c "curl -k -u $Auth https://$($S.IP)$($Net.'@odata.id') -s" | ConvertFrom-Json
        Write-Log "Adapter: $($NetDetail.Id) | Modelo: $($NetDetail.Model) | Health: $($NetDetail.Status.Health)"
    }
    Write-Log ""

    # ---------- ENERGIA (Power) ----------
    Write-Log "[ ENERGIA / FONTES ]"
    $PowerJson = cmd.exe /c "curl -k -u $Auth $BaseUrl/Chassis/System.Embedded.1/Power -s" | ConvertFrom-Json
    foreach ($PSU in $PowerJson.PowerSupplies) {
        Write-Log "PSU: $($PSU.MemberId) | Status: $($PSU.Status.State) | Health: $($PSU.Status.Health) | Input: $($PSU.LastPowerOutputWatts)W"
    }
    if ($PowerJson.PowerControl) {
        Write-Log "Consumo Atual: $($PowerJson.PowerControl[0].PowerConsumedWatts) Watts"
    }
    Write-Log ""

    # ---------- TERMICO E FANS (Thermal) ----------
    Write-Log "[ TERMICO / FANS ]"
    $ThermalJson = cmd.exe /c "curl -k -u $Auth $BaseUrl/Chassis/System.Embedded.1/Thermal -s" | ConvertFrom-Json
    foreach ($Fan in $ThermalJson.Fans) {
        Write-Log "Fan: $($Fan.FanName) | Speed: $($Fan.Reading) $($Fan.ReadingUnits) | Health: $($Fan.Status.Health)"
    }
    foreach ($Temp in $ThermalJson.Temperatures) {
        Write-Log "Sensor: $($Temp.Name) | Temp: $($Temp.ReadingCelsius) C | Health: $($Temp.Status.Health)"
    }
    Write-Log ""

    # ---------- iDRAC HEALTH ----------
    Write-Log "[ iDRAC / CONTROLLER ]"
    $iDRACInfo = cmd.exe /c "curl -k -u $Auth $BaseUrl/Managers/iDRAC.Embedded.1 -s" | ConvertFrom-Json
    Write-Log "iDRAC Health: $($iDRACInfo.Status.Health)"
    Write-Log "Firmware: $($iDRACInfo.FirmwareVersion)"
    Write-Log ""
}

Write-Log "========================================"
Write-Log "FIM DO CHECK"
Write-Log "========================================"