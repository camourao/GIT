$destination = "C:\Windows\Web\Screen\img100.jpg"
$source = "\\192.168.100.34\Share\Publico\TI\Imagem_gpo\Campanha Agosto Block_Tela.jpg.jpg"

# Verifica se a imagem de origem existe no compartilhamento
if (Test-Path $source) {
    # Garante que o arquivo de destino nao esteja marcado como Leitura Apenas (Read-Only)
    if (Test-Path $destination) {
        Set-ItemProperty -Path $destination -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    }

    # Copia a nova imagem sobrescrevendo a imagem padrao do sistema
    Copy-Item -Path $source -Destination $destination -Force

    # Limpa o cache global de telas de bloqueio de todos os perfis do sistema
    $systemCache = "C:\ProgramData\Microsoft\Windows\SystemData"
    if (Test-Path $systemCache) {
        # Concede acesso temporario do SYSTEM para apagar as pastas de cache
        takeown /f $systemCache /r /d Y 2>$null
        icacls $systemCache /grant "NT AUTHORITY\SYSTEM:(OI)(CI)F" /t /q 2>$null
        
        # Apaga os caches gerados previamente para forcar a atualizacao
        Get-ChildItem -Path $systemCache -Recurse -File | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}