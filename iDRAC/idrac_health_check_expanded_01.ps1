# ============================================================
# iDRAC 9 - Full Health Check & Metrics (Versão Expandida)
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

# Função auxiliar para chamadas na API do Redfish
function Get-RedfishData {
    param(
        [string]$Url,
        [PSCredential]$Credential
    )
    try {
        return Invoke-RestMethod -Uri $Url -Credential $Credential -Method Get -SkipCertificateCheck -ErrorAction Stop
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
    Write-Log "----------------------------------------"
    Write-Log "Servidor : $($S.Nome)"
    Write-Log "IP       : $($S.IP)"

    # Cria credencial segura para a requisição
    $secpasswd = ConvertTo-SecureString $S.Senha -AsPlainText -Force
    $Cred = New-Object System.Management.Automation.PSCredential ($S.Usuario, $secpasswd)
    
    $BaseUrl = "https://$($S.IP)/redfish/v1"

    # ---------- TESTE iDRAC ----------
    $BaseTest = Get-RedfishData -Url $BaseUrl -Credential $Cred
    if ($null -eq $BaseTest) {
        Write-Log "iDRAC Status     : OFFLINE / Auth Failure"
        Write-Log ""
        continue
    }

    Write-Log "iDRAC Status     : ONLINE"

    # ---------- SISTEMA GERAL ----------
    $SystemInfo = Get-RedfishData -Url "$BaseUrl/Systems/System.Embedded.1" -Credential $Cred
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
    $ProcessorsJson = Get-RedfishData -Url "$BaseUrl/Systems/System.Embedded.1/Processors" -Credential $Cred
    foreach ($Proc in $ProcessorsJson.Members) {
        $ProcDetail = Get-RedfishData -Url "https://$($S.IP)$($Proc.'@odata.id')" -Credential $Cred
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
    $MemoryJson = Get-RedfishData -Url "$BaseUrl/Systems/System.Embedded.1/Memory" -Credential $Cred
    foreach ($Mem in $MemoryJson.Members) {
        $MemDetail = Get-RedfishData -Url "https://$($S.IP)$($Mem.'@odata.id')" -Credential $Cred
        if ($MemDetail -and $MemDetail.Status.State -ne "Absent") {
            Write-Log "Slot: $($MemDetail.Id) | Size: $($MemDetail.CapacityMiB / 1024) GB | Type: $($MemDetail.MemoryDeviceType) | Health: $($MemDetail.Status.Health)"
        }
    }
    Write-Log ""

    # ---------- STORAGE ----------
    Write-Log "[ STORAGE / DISCOS ]"
    $StorageJson = Get-RedfishData -Url "$BaseUrl/Systems/System.Embedded.1/Storage" -Credential $Cred
    foreach ($Controller in $StorageJson.Members) {
        $CtrlDetail = Get-RedfishData -Url "https://$($S.IP)$($Controller.'@odata.id')" -Credential $Cred
        if ($CtrlDetail) {
            Write-Log "Controller: $($CtrlDetail.Name) | Health: $($CtrlDetail.Status.Health)"
            foreach ($Drive in $CtrlDetail.Drives) {
                $DriveDetail = Get-RedfishData -Url "https://$($S.IP)$($Drive.'@odata.id')" -Credential $Cred
                $SizeTB = if ($DriveDetail.CapacityBytes) { [math]::Round(($DriveDetail.CapacityBytes / 1TB), 2) } else { "N/A" }
                Write-Log "  - Disco: $($DriveDetail.Id) | Modelo: $($DriveDetail.Model) | Size: $SizeTB TB | Health: $($DriveDetail.Status.Health)"
            }
        }
    }
    Write-Log ""

    # ---------- REDE (Network Adapters) ----------
    Write-Log "[ REDE / ADAPTADORES ]"
    $NetworkJson = Get-RedfishData -Url "$BaseUrl/Systems/System.Embedded.1/NetworkAdapters" -Credential $Cred
    foreach ($Net in $NetworkJson.Members) {
        $NetDetail = Get-RedfishData -Url "https://$($S.IP)$($Net.'@odata.id')" -Credential $Cred
        if ($NetDetail) {
            Write-Log "Adapter: $($NetDetail.Id) | Modelo: $($NetDetail.Model) | Health: $($NetDetail.Status.Health)"
        }
    }
    Write-Log ""

    # ---------- ENERGIA (Power) ----------
    Write-Log "[ ENERGIA / FONTES ]"
    $PowerJson = Get-RedfishData -Url "$BaseUrl/Chassis/System.Embedded.1/Power" -Credential $Cred
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
    $ThermalJson = Get-RedfishData -Url "$BaseUrl/Chassis/System.Embedded.1/Thermal" -Credential $Cred
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
    $iDRACInfo = Get-RedfishData -Url "$BaseUrl/Managers/iDRAC.Embedded.1" -Credential $Cred
    if ($iDRACInfo) {
        Write-Log "iDRAC Health: $($iDRACInfo.Status.Health)"
        Write-Log "Firmware: $($iDRACInfo.FirmwareVersion)"
    }
    Write-Log ""
}

Write-Log "========================================"
Write-Log "FIM DO CHECK"
Write-Log "========================================"