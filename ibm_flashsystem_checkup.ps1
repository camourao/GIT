# Script PowerShell para Checkup da IBM FlashSystem 5045
# Este script se conecta via SSH a uma IBM FlashSystem 5045 (ou qualquer sistema IBM Spectrum Virtualize)
# e executa comandos CLI para coletar informações de saúde e status, gerando um relatório em TXT.

# Requisitos: Módulo Posh-SSH. Instale com: Install-Module -Name Posh-SSH -Scope CurrentUser

param(
    [Parameter(Mandatory=$true)]
    [string]$IPAddress,

    # Usuário configurado como padrão conforme solicitado
    [Parameter(Mandatory=$false)]
    [string]$Username = "superuser",

    # Senha configurada como padrão conforme solicitado
    [Parameter(Mandatory=$false)]
    [string]$Password = "wcpPV4L6PLyks7lsoQMh",

    [Parameter(Mandatory=$false)]
    [string]$SSHKeyPath = "",

    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "./IBM_FlashSystem_Checkup_Report.txt"
)

Function Get-FlashSystemCLIOutput {
    param(
        [Parameter(Mandatory=$true)]
        $SSHSession,
        [string]$Command
    )
    Write-Host "Executando comando: $Command"
    try {
        $result = Invoke-SSHCommand -SSHSession $SSHSession -Command $Command -ErrorAction Stop
        return $result.Output
    }
    catch {
        Write-Warning "Erro ao executar '$Command': $($_.Exception.Message)"
        return "Erro ao executar comando: $($_.Exception.Message)"
    }
}

# --- Início do Script ---
Write-Host "Iniciando checkup da IBM FlashSystem 5045 em $IPAddress..."

# Verificar e carregar o módulo Posh-SSH
if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    Write-Warning "Módulo Posh-SSH não encontrado. Tentando instalar..."
    try {
        Install-Module -Name Posh-SSH -Scope CurrentUser -Force -Confirm:$false -ErrorAction Stop
        Import-Module Posh-SSH -ErrorAction Stop
        Write-Host "Módulo Posh-SSH instalado e carregado com sucesso."
    }
    catch {
        Write-Error "Falha ao instalar/carregar o módulo Posh-SSH. Por favor, instale-o manualmente ou verifique as permissões. Erro: $($_.Exception.Message)"
        exit 1
    }
} else {
    Import-Module Posh-SSH -ErrorAction SilentlyContinue
    Write-Host "Módulo Posh-SSH carregado."
}

$reportContent = New-Object System.Text.StringBuilder
$reportContent.AppendLine("IBM FlashSystem 5045 Health Check Report - Cluster_STG-IBM")
$reportContent.AppendLine("Data e Hora: $(Get-Date)")
$reportContent.AppendLine("IP do Sistema (Gerenciamento): $IPAddress")
$reportContent.AppendLine("IP do Node 1: 192.168.100.91")
$reportContent.AppendLine("IP do Node 2: 192.168.100.92")
$reportContent.AppendLine("===================================================")

$sshSession = $null
try {
    # Conectar via SSH
    Write-Host "Tentando conectar via SSH a $IPAddress..."
    if ($Password) {
        $credential = New-Object System.Management.Automation.PSCredential($Username, (ConvertTo-SecureString $Password -AsPlainText -Force))
        $sshSession = New-SSHSession -ComputerName $IPAddress -Credential $credential -AcceptKey -ErrorAction Stop
    } elseif ($SSHKeyPath) {
        $sshSession = New-SSHSession -ComputerName $IPAddress -Username $Username -KeyFile $SSHKeyPath -AcceptKey -ErrorAction Stop
    } else {
        Write-Error "Nenhuma senha ou chave SSH fornecida. Por favor, forneça um dos dois."
        exit 1
    }
    
    $reportContent.AppendLine("Conexão SSH estabelecida com sucesso.")
    $reportContent.AppendLine("\n")

    # Comandos CLI para coletar informações
    $cliCommands = @(
        "lshealth",
        "lssystem",
        "lsnode",
        "lsdrive",
        "lsmdiskgrp",
        "lsvdisk",
        "lseventlog -sev error -fixed 10", 
        "lseventlog -sev warning -fixed 10", 
        "lsportfc",
        "lsportethernet",
        "lsfirmware",
        "lshost",
        "lsmdiskgrp Pool0",
        "lsmdiskgrp Pool1",
        "lsvdisk QUORUM",
        "lsvdisk VOL0",
        "lsvdisk VOL1",
        "lsvdisk VOL-BACKUP"
    )

    foreach ($cmd in $cliCommands) {
        $reportContent.AppendLine("--- Output de '$cmd' ---")
        $output = Get-FlashSystemCLIOutput -SSHSession $sshSession -Command $cmd
        $reportContent.AppendLine($output)
        $reportContent.AppendLine("\n")
    }

    # Salvar relatório
    $reportContent.ToString() | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "Relatório de checkup salvo em: $OutputPath"

} catch {
    Write-Error "Erro durante a execução do script: $($_.Exception.Message)"
    $reportContent.AppendLine("\nErro fatal durante a execução do script: $($_.Exception.Message)")
    $reportContent.ToString() | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "Relatório parcial salvo em: $OutputPath (com erros)"
} finally {
    if ($sshSession) {
        Write-Host "Fechando conexão SSH..."
        Remove-SSHSession -SSHSession $sshSession -ErrorAction SilentlyContinue
    }
}

Write-Host "Checkup concluído."