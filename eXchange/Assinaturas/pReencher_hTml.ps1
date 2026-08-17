# Importa o módulo do Active Directory
Import-Module ActiveDirectory

# Caminho do modelo HTML e pasta de saída
$templatePath = "C:\git\eXchange\rEspostas_aSsinaturas.html"
$outputPath   = "C:\git\eXchange\Assinaturas"

if (!(Test-Path -Path $outputPath)) {
    New-Item -ItemType Directory -Path $outputPath | Out-Null
}

$htmlTemplate = Get-Content -Path $templatePath -Raw -Encoding UTF8

# Define a OU base onde estão os usuários
# Ajuste o DC conforme o nome exato do seu domínio (ex: DC=crn3,DC=sp ou DC=crn3,DC=org,DC=br)
$ouBase = "OU=Usuários,OU=Administrativo,OU=Sede,OU=CRN3,DC=crn3,DC=sp"

# Busca usuários especificamente dentro da OU informada
$users = Get-ADUser -Filter * -SearchBase $ouBase -SearchScope Subtree -Properties DisplayName, Department, Title, StreetAddress, City, State, PostalCode, TelephoneNumber

foreach ($user in $users) {
    # Ignora contas desabilitadas (opcional, remova a verificação se quiser incluir todas)
    if ($user.Enabled -eq $false) { continue }

    $userHtml = $htmlTemplate

    $userHtml = $userHtml -replace '%%DisplayName%%', ($user.DisplayName ?? '')
    $userHtml = $userHtml -replace '%%Department%%', ($user.Department ?? '')
    $userHtml = $userHtml -replace '%%Title%%', ($user.Title ?? '')
    $userHtml = $userHtml -replace '%%Street%%', ($user.StreetAddress ?? '')
    $userHtml = $userHtml -replace '%%City%%', ($user.City ?? '')
    $userHtml = $userHtml -replace '%%StateOrProvince%%', ($user.State ?? '')
    $userHtml = $userHtml -replace '%%PostalCode%%', ($user.PostalCode ?? '')
    $userHtml = $userHtml -replace '%%PhoneNumber%%', ($user.TelephoneNumber ?? '')

    $fileDestination = Join-Path -Path $outputPath -ChildPath "$($user.SamAccountName).html"
    Set-Content -Path $fileDestination -Value $userHtml -Encoding UTF8
}