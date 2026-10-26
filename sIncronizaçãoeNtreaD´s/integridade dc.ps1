# Execute este script em cada DC:

Write-Host "=== Verificando saúde do DC ===" -ForegroundColor Green

# 1. Nome do DC
$dcName = $env:COMPUTERNAME
Write-Host "`nDC: $dcName" -ForegroundColor Yellow

# 2. Verificar serviços críticos
$services = @('NTDS', 'kdc', 'Netlogon', 'DNS', 'W32Time')
foreach ($svc in $services) {
    $status = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($status) {
        Write-Host "$svc : $($status.Status)" -ForegroundColor $(if($status.Status -eq 'Running'){'Green'}else{'Red'})
    }
}

# 3. Verificar sincronização de tempo
Write-Host "`n=== Sincronização de Tempo ===" -ForegroundColor Green
w32tm /query /status

# 4. Verificar FSMO Roles
Write-Host "`n=== FSMO Roles neste DC ===" -ForegroundColor Green
netdom query fsmo

# 5. Verificar replicação
Write-Host "`n=== Status de Replicação ===" -ForegroundColor Green
repadmin /showrepl $dcName

# 6. Verificar conectividade com outros DCs
Write-Host "`n=== Testando conectividade entre DCs ===" -ForegroundColor Green
$allDCs = (Get-ADDomainController -Filter *).Name
foreach ($dc in $allDCs) {
    if ($dc -ne $dcName) {
        $ping = Test-Connection -ComputerName $dc -Count 2 -Quiet
        Write-Host "Ping para $dc : $(if($ping){'OK'}else{'FALHOU'})" -ForegroundColor $(if($ping){'Green'}else{'Red'})
    }
}