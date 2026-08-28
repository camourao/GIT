# ============================================================
# iDRAC 9 - Full Health Check & Metrics (Versão Corrigida)
# Saída: TXT (Rede UNC)
# ============================================================

# Força o uso de TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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

# Função com tratamento explícito de Header Basic Auth para Redfish
function Get-RedfishData {
    param(
        [string]$Url,
        [string]$Usuario,
        [string]$Senha
    )
    try {
        # Converte Usuário e Senha para o cabeçalho Authorization Basic em Base64
        $Pair = "${Usuario}:${Senha}"
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Pair)
        $Base64 = [Convert]::ToBase64String($Bytes)
        $Headers = @{ Authorization = "Basic $Base64" }

        return Invoke-RestMethod -Uri $Url -Headers $Headers -Method Get -SkipCertificateCheck -ErrorAction Stop
    } catch {
        return $null
    }
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
    # Sanitiza strings removendo espaços acidentais trazidos do CSV
    $ServerName = $S.Nome.Trim()
    $ServerIP   = $S.IP.Trim()
    $User       = $S.Usuario.Trim()
    $Pass       = $S.Senha.Trim()

    Write-Log "----------------------------------------"
    Write-Log "Servidor : $ServerName"
    Write-Log "IP       : $ServerIP"

    $BaseUrl = "https://${ServerIP}/redfish/v1"

    # ---------- TESTE iDRAC ----------
    $BaseTest = Get-RedfishData -Url $BaseUrl -Usuario $User -Senha $Pass
    if ($null -eq $BaseTest) {
        Write-Log "iDRAC Status     : OFFLINE / Auth Failure"
        Write-Log ""
        continue
    }

    Write-Log "iDRAC Status     : ONLINE"

    # ---------- SISTEMA GERAL ----------
    $SystemInfo = Get-RedfishData -Url "$BaseUrl/Systems/System.Embedded.1" -Usuario $User -Senha $Pass
    if ($SystemInfo) {
        Write-Log "Health Geral     : $($SystemInfo.Status.Health)"
        Write-Log "Power State      : $($SystemInfo.PowerState)"
        Write-Log "Modelo           : $($SystemInfo.Model)"
        Write-Log "Service Tag      : $($SystemInfo.SKU)"
        Write-Log "BIOS Version     : $($SystemInfo.BiosVersion)"
        Write-Log ""
    }

    # ---------- CPU / PROCESSADORES ----------
    Write-Log "[ CPU / PROCESSADORES ]"
    $ProcessorsJson = Get-RedfishData -Url "$BaseUrl/Systems/System.Embedded.1/Processors" -Usuario $User -Senha $Pass
    foreach ($Proc in $ProcessorsJson.Members) {
        $ProcDetail = Get-RedfishData -Url "https://${ServerIP}$($Proc.'@odata.id')" -Usuario $User -Senha $Pass
        if ($ProcDetail) {
            Write-Log "ID: $($ProcDetail.Id) | Modelo: $($ProcDetail.Model) | Cores: $($ProcDetail.TotalCores) | Health: $($ProcDetail.Status.Health)"
        }
    }
    Write-Log ""

    # ---------- MEMORIA ----------
    Write-Log "[ MEMORIA ]"
    if ($SystemInfo.MemorySummary.TotalSystemMemoryGiB) {
        Write-Log "Total: $($SystemInfo.MemorySummary.TotalSystemMemoryGiB) GB | Health: $($SystemInfo.MemorySummary.Status.Health)"
    }
    $MemoryJson = Get-RedfishData -Url "$BaseUrl/Systems/System.Embedded.1/Memory" -Usuario $User -Senha $Pass
    foreach ($Mem in $MemoryJson.Members) {
        $MemDetail = Get-RedfishData -Url "https://${ServerIP}$($Mem.'@odata.id')" -Usuario $User -Senha $Pass
        if ($MemDetail -and $MemDetail.Status.State -ne "Absent") {
            Write-Log "Slot: $($MemDetail.Id) | Size: $($MemDetail.CapacityMiB / 1024) GB | Type: $($MemDetail.MemoryDeviceType) | Health: $($MemDetail.Status.Health)"
        }
    }
    Write-Log ""

    # ---------- STORAGE ----------
    Write-Log "[ STORAGE / DISCOS ]"
    $StorageJson = Get-RedfishData -Url "$BaseUrl/Systems/System.Embedded.1/Storage" -Usuario $User -Senha $Pass
    foreach ($Controller in $StorageJson.Members) {
        $CtrlDetail = Get-RedfishData -Url "https://${ServerIP}$($Controller.'@odata.id')" -Usuario $User -Senha $Pass
        if ($CtrlDetail) {
            Write-Log "Controller: $($CtrlDetail.Name) | Health: $($CtrlDetail.Status.Health)"
            foreach ($Drive in $CtrlDetail.Drives) {
                $DriveDetail = Get-RedfishData -Url "https://${ServerIP}$($Drive.'@odata.id')" -Usuario $User -Senha $Pass
                $SizeTB = if ($DriveDetail.CapacityBytes) { [math]::Round(($DriveDetail.CapacityBytes / 1TB), 2) } else { "N/A" }
                Write-Log "  - Disco: $($DriveDetail.Id) | Modelo: $($DriveDetail.Model) | Size: $SizeTB TB | Health: $($DriveDetail.Status.Health)"
            }
        }
    }
    Write-Log ""

    # ---------- REDE (Network Adapters) ----------
    Write-Log "[ REDE / ADAPTADORES ]"
    $NetworkJson = Get-RedfishData -Url "$BaseUrl/Systems/System.Embedded.1/NetworkAdapters" -Usuario $User -Senha $Pass
    foreach ($Net in $NetworkJson.Members) {
        $NetDetail = Get-RedfishData -Url "https://${ServerIP}$($Net.'@odata.id')" -Usuario $User -Senha $Pass
        if ($NetDetail) {
            Write-Log "Adapter: $($NetDetail.Id) | Modelo: $($NetDetail.Model) | Health: $($NetDetail.Status.Health)"
        }
    }
    Write-Log ""

    # ---------- ENERGIA (Power) ----------
    Write-Log "[ ENERGIA / FONTES ]"
    $PowerJson = Get-RedfishData -Url "$BaseUrl/Chassis/System.Embedded.1/Power" -Usuario $User -Senha $Pass
    if ($PowerJson) {
        foreach ($PSU in $PowerJson.PowerSupplies) {
            Write-Log "PSU: $($PSU.MemberId) | Status: $($PSU.Status.State) | Health: $($PSU.Status.Health) | Input: $($PSU.LastPowerOutputWatts)W"
        }
        if ($PowerJson.PowerControl) {
            Write-Log "Consumo Atual: $($PowerJson.PowerControl[0].PowerConsumedWatts) Watts"
        }
    }
    Write-Log ""

    # ---------- TERMICO E FANS (Thermal) ----------
    Write-Log "[ TERMICO / FANS ]"
    $ThermalJson = Get-RedfishData -Url "$BaseUrl/Chassis/System.Embedded.1/Thermal" -Usuario $User -Senha $Pass
    if ($ThermalJson) {
        foreach ($Fan in $ThermalJson.Fans) {
            Write-Log "Fan: $($Fan.FanName) | Speed: $($Fan.Reading) $($Fan.ReadingUnits) | Health: $($Fan.Status.Health)"
        }
        foreach ($Temp in $ThermalJson.Temperatures) {
            Write-Log "Sensor: $($Temp.Name) | Temp: $($Temp.ReadingCelsius) C | Health: $($Temp.Status.Health)"
        }
    }
    Write-Log ""

    # ---------- iDRAC HEALTH ----------
    Write-Log "[ iDRAC / CONTROLLER ]"
    $iDRACInfo = Get-RedfishData -Url "$BaseUrl/Managers/iDRAC.Embedded.1" -Usuario $User -Senha $Pass
    if ($iDRACInfo) {
        Write-Log "iDRAC Health: $($iDRACInfo.Status.Health)"
        Write-Log "Firmware: $($iDRACInfo.FirmwareVersion)"
    }
    Write-Log ""
}

Write-Log "========================================"
Write-Log "FIM DO CHECK"
Write-Log "========================================"