# ==============================================================================
# CAMINHO DA PASTA: Altere o caminho entre aspas para a pasta que quer analisar
# ==============================================================================
$pasta = "\\192.168.100.34\D$\Share\Comissao_Eventos"

# Define o caminho do arquivo de saída
$arquivoSaida = "C:\logscan\arquivos_antigos.txt"

# Calcula a data limite (90 dias atrás)
$dataLimite = (Get-Date).AddDays(-90)

try {
    # Garante que a pasta de log de destino exista antes de gravar
    $pastaLog = Split-Path $arquivoSaida
    if (!(Test-Path -Path $pastaLog)) {
        New-Item -ItemType Directory -Force -Path $pastaLog | Out-Null
    }

    Write-Host "Iniciando varredura na pasta: $pasta..."

    # Obtém os arquivos e ignora erros de permissão/pastas bloqueadas para não travar
    $arquivos = Get-ChildItem -Path $pasta -Recurse -File -ErrorAction SilentlyContinue | 
                Where-Object { $_.LastAccessTime -lt $dataLimite }

    # Verifica se há arquivos para listar
    if ($arquivos) {
        # Calcula o tamanho total dos arquivos
        $tamanhoTotalBytes = ($arquivos | Measure-Object -Property Length -Sum).Sum
        $tamanhoTotalGB = [math]::Round($tamanhoTotalBytes / 1GB, 2)

        # Cria ou sobrescreve o arquivo .txt
        $saida = @()
        $saida += "Relatório de Arquivos Não Acessados nos Últimos 90 Dias"
        $saida += "Data de geração: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $saida += "Volumetria total: $tamanhoTotalGB GB ($tamanhoTotalBytes bytes)"
        $saida += "=" * 50

        foreach ($arquivo in $arquivos) {
            $saida += "Arquivo: $($arquivo.FullName)"
            $saida += "Último acesso: $($arquivo.LastAccessTime.ToString('yyyy-MM-dd HH:mm:ss'))"
            $saida += "-" * 50
        }

        # Grava no arquivo de saída
        $saida | Out-File -FilePath $arquivoSaida -Encoding UTF8

        Write-Host "Lista de arquivos gerada com sucesso em: $arquivoSaida"
    } else {
        Write-Host "Nenhum arquivo encontrado que não foi acessado nos últimos 90 dias."
        # Cria um arquivo vazio com mensagem
        "Nenhum arquivo encontrado que não foi acessado nos últimos 90 dias." | Out-File -FilePath $arquivoSaida -Encoding UTF8
    }
}
catch {
    Write-Host "Erro ao acessar a pasta ou gravar o arquivo: $_"
}