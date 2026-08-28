# ==============================================================================
# 1. CONSULTA AO ACTIVE DIRECTORY
# ==============================================================================
$CurrentUserName = $env:USERNAME

$DisplayName     = $CurrentUserName
$Department      = ""
$Title           = ""
$Street          = ""
$City            = ""
$StateOrProvince = ""
$PostalCode      = ""
$PhoneNumber     = ""

try {
    $ADUser = [adsisearcher]"(sAMAccountName=$CurrentUserName)"
    $Result = $ADUser.FindOne()

    if ($Result) {
        $Prop = $Result.Properties
        if ($Prop["displayname"])     { $DisplayName     = $Prop["displayname"][0] }
        if ($Prop["department"])      { $Department      = $Prop["department"][0] }
        if ($Prop["title"])           { $Title           = $Prop["title"][0] }
        if ($Prop["streetaddress"])   { $Street          = $Prop["streetaddress"][0] }
        if ($Prop["l"])               { $City            = $Prop["l"][0] }
        if ($Prop["st"])              { $StateOrProvince = $Prop["st"][0] }
        if ($Prop["postalcode"])      { $PostalCode      = $Prop["postalcode"][0] }
        if ($Prop["telephonenumber"]) { $PhoneNumber     = $Prop["telephonenumber"][0] }
    }
} catch {
    # Fallback silencioso em caso de desconexão temporária do AD
}

# ==============================================================================
# 2. GERAÇÃO DOS ARQUIVOS DA ASSINATURA (HTM, TXT, RTF)
# ==============================================================================
$SignatureName = "AssinaturaResposta"
$AppDataPath = "$env:APPDATA\Microsoft\Signatures"

if (!(Test-Path -Path $AppDataPath)) {
    New-Item -ItemType Directory -Path $AppDataPath -Force | Out-Null
}

$HTMLContent = @"
<table cellpadding="0" cellspacing="0" border="0" style="font-family: Arial, Helvetica, sans-serif; font-size: 13px; color: #000000; line-height: 1.4;">
  <tr>
    <td valign="middle" style="padding-right: 20px;">
      <img src="https://stgcrn3apptmp.blob.core.windows.net/assinatura/LOGOCRN3PRETO.png" alt="Logo CRN3" width="180" style="display: block; border: 0; width: 180px; height: auto;" />
    </td>
    <td valign="middle" style="border-left: 1px solid #000000; padding-left: 20px;">
      <table cellpadding="0" cellspacing="0" border="0" style="font-family: Arial, Helvetica, sans-serif; font-size: 13px; color: #000000;">
        <tr>
          <td style="font-weight: bold; font-size: 15px; padding-bottom: 2px;">
            $DisplayName
          </td>
        </tr>
        <tr>
          <td style="color: #333333; font-size: 14px; padding-bottom: 6px; font-weight: 500;">
            $Department | $Title
          </td>
        </tr>
        <tr>
          <td style="color: #333333; font-size: 12px;">
            $Street
          </td>
        </tr>
        <tr>
          <td style="color: #333333; font-size: 12px;">
            $City/$StateOrProvince – (CEP: $PostalCode)
          </td>
        </tr>
        <tr>
          <td style="color: #333333; font-size: 12px; padding-top: 2px;">
            Atendimento (2ª a 6ª feira):<br>
            Chatbot e telefone: $PhoneNumber - 10h às 16h <br>
            Presencial (com agendamento prévio) 9h às 16h
          </td>
        </tr>
        <tr>
          <td style="padding-top: 4px;">
            <a href="https://www.crn3.org.br" style="color: #000000; text-decoration: none; font-weight: bold;">www.crn3.org.br</a>
          </td>
        </tr>
      </table>
    </td>
  </tr>
</table>
"@

$TXTContent = @"
$DisplayName
$Department | $Title
$Street
$City/$StateOrProvince – (CEP: $PostalCode)
Atendimento (2ª a 6ª feira):
Chatbot e telefone: $PhoneNumber - 10h às 16h
Presencial (com agendamento prévio) 9h às 16h
www.crn3.org.br
"@

# Grava os arquivos
$Utf8Encoding = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText("$AppDataPath\$SignatureName.htm", $HTMLContent, $Utf8Encoding)
[System.IO.File]::WriteAllText("$AppDataPath\$SignatureName.txt", $TXTContent, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText("$AppDataPath\$SignatureName.rtf", "{\rtf1\ansi $TXTContent}", [System.Text.Encoding]::ASCII)

# ==============================================================================
# 3. VÍNCULO COMPLETO NO REGISTRO DO OUTLOOK
# ==============================================================================

# 1. Configurações globais de e-mail e desativação do Roaming Signatures
$OptionsPath = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Options\Mail"
if (!(Test-Path $OptionsPath)) {
    New-Item -Path $OptionsPath -Force | Out-Null
}
Set-ItemProperty -Path $OptionsPath -Name "DisableRoamingSignaturesTemporaryToggle" -Value 1 -Type DWord -ErrorAction SilentlyContinue
Set-ItemProperty -Path $OptionsPath -Name "ReplySignature" -Value $SignatureName -Type String -ErrorAction SilentlyContinue
Set-ItemProperty -Path $OptionsPath -Name "NewSignature" -Value "" -Type String -ErrorAction SilentlyContinue

# 2. Conversão em formato binário MAPI
$SigBinary   = [System.Text.Encoding]::Unicode.GetBytes($SignatureName) + @(0, 0)
$EmptyBinary = [System.Text.Encoding]::Unicode.GetBytes("") + @(0, 0)

# 3. Aplicação em todas as subchaves de perfis
$ProfilesPath = "HKCU:\SOFTWARE\Microsoft\Office\16.0\Outlook\Profiles"
if (Test-Path $ProfilesPath) {
    Get-ChildItem -Path $ProfilesPath -Recurse | ForEach-Object {
        try {
            Set-ItemProperty -Path $_.PSPath -Name "Reply-Forward Signature" -Value $SigBinary -Type Binary -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $_.PSPath -Name "New Signature" -Value $EmptyBinary -Type Binary -ErrorAction SilentlyContinue
        } catch {}
    }
}