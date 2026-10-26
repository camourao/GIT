# Importa os módulos necessários
Import-Module ActiveDirectory
Import-Module GroupPolicy

Write-Host "Iniciando varredura em TODAS as OUs do Active Directory..." -ForegroundColor Cyan

# 1. Busca todos os computadores cadastrados no Active Directory
$computadores = Get-ADComputer -Filter * -Properties Name, Enabled | Where-Object { $_.Enabled -eq $true }

if (-not $computadores) {
    Write-Warning "Nenhum computador ativo foi encontrado no Active Directory."
    exit
}

Write-Host "Encontrados $($computadores.Count) computadores ativos no domínio. Iniciando sincronização..." -ForegroundColor Green
Write-Host "----------------------------------------------------------------------"

# Variables para estatísticas finais
$sucesso = 0
$falha = 0

# 2. Dispara o Invoke-GPUpdate para cada computador
foreach ($pc in $computadores) {
    Write-Host "Enviando gpupdate para: $($pc.Name)..." -NoNewline
    try {
        # RandomDelayInMinutes 0 força a execução imediata
        Invoke-GPUpdate -Computer $pc.Name -RandomDelayInMinutes 0 -Force -ErrorAction Stop
        Write-Host " [OK]" -ForegroundColor Green
        $sucesso++
    }
    catch {
        Write-Host " [FALHA] - $($_.Exception.Message)" -ForegroundColor Red
        $falha++
    }
}

# 3. Resumo final
Write-Host "----------------------------------------------------------------------"
Write-Host "Processo concluído!" -ForegroundColor Yellow
Write-Host "Sucesso: $sucesso | Falhas: $falha" -ForegroundColor Cyan