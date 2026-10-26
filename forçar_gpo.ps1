# Importa os módulos necessários
Import-Module ActiveDirectory
Import-Module GroupPolicy

# 1. Busca todas as OUs do Active Directory e exibe em uma janela de seleção interativa
$ouSelecionada = Get-ADOrganizationalUnit -Filter * -Properties CanonicalName |
    Select-Object Name, CanonicalName, DistinguishedName |
    Out-GridView -Title "Selecione a OU para forçar o gpupdate" -PassThru

# Verifica se o usuário selecionou alguma OU
if (-not $ouSelecionada) {
    Write-Warning "Nenhuma OU foi selecionada. Operação cancelada."
    exit
}

Write-Host "OU selecionada: $($ouSelecionada.CanonicalName)" -ForegroundColor Cyan

# 2. Busca todos os computadores ativos na OU selecionada
$computadores = Get-ADComputer -Filter * -SearchBase $ouSelecionada.DistinguishedName -SearchScope Subtree

if ($computadores.Count -eq 0) {
    Write-Warning "Nenhum computador foi encontrado na OU selecionada."
    exit
}

Write-Host "Encontrados $($computadores.Count) computador(es). Iniciando sincronização..." -ForegroundColor Green

# 3. Dispara o Invoke-GPUpdate para cada computador
foreach ($pc in $computadores) {
    Write-Host "Enviando comando de atualização para: $($pc.Name)..." -NoNewline
    try {
        # O parâmetro -RandomDelayInMinutes 0 força a execução imediata sem tempo de espera aleatório
        Invoke-GPUpdate -Computer $pc.Name -RandomDelayInMinutes 0 -Force -ErrorAction Stop
        Write-Host " [OK]" -ForegroundColor Green
    }
    catch {
        Write-Host " [FALHA] - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nProcesso concluído!" -ForegroundColor Yellow