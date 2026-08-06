# Importa o módulo do Active Directory
Import-Module ActiveDirectory

# Define o nome do grupo e o caminho da OU
$GroupName = "Assinaturas"
$OUPath = "OU=Usuários,OU=Administrativo,OU=Sede,OU=CRN3,DC=crn3,DC=sp"

# Busca os usuários da OU e adiciona ao grupo
Get-ADUser -SearchBase $OUPath -Filter * | ForEach-Object {
    try {
        Add-ADGroupMember -Identity $GroupName -Members $_.sAMAccountName -ErrorAction Stop
        Write-Host "Usuário '$($_.sAMAccountName)' adicionado ao grupo '$GroupName'." -ForegroundColor Green
    }
    catch {
        Write-Host "Falha ao adicionar '$($_.sAMAccountName)': $_" -ForegroundColor Yellow
    }
}