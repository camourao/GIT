Import-Module ActiveDirectory

# Caminho da OU
$OU = "OU=Grupos Gerais,OU=CRN3,DC=crn3,DC=sp"

# Lista de grupos com Nome, Descrição e E-mail
$Grupos = @(
    @{ 
        Name        = "gS_cAdastro_aSsinaturas"
        Description = "Assinaturas Cadastro"
        Email       = "noreply_cAdastro_assinaturas@crn3.org.br"
    },
    @{ 
        Name        = "gS_cAllcEnter_aSsinaturas"
        Description = "Assinaturas CallCenter"
        Email       = "noreply_callcenter_assinaturas@crn3.org.br"
    },
    @{ 
        Name        = "gS_cOmunicação & eVentos_aSsinaturas"
        Description = "Assinaturas Comunicação & Eventos"
        Email       = "noreply_comunicacao_eventos_assinaturas@crn3.org.br"
    },
    @{ 
        Name        = "gS_eTica_aSsinaturas"
        Description = "Assinaturas Ética"
        Email       = "noreply_etica_assinaturas@crn3.org.br"
    }
)

foreach ($Grupo in $Grupos) {
    $NomeGrupo = $Grupo.Name
    $Descricao = $Grupo.Description
    $Email     = $Grupo.Email

    $Existe = Get-ADGroup -Filter "Name -eq '$NomeGrupo'" -ErrorAction SilentlyContinue

    if (-not $Existe) {
        New-ADGroup `
            -Name $NomeGrupo `
            -GroupScope Global `
            -GroupCategory Distribution `
            -Path $OU `
            -Description $Descricao `
            -DisplayName $NomeGrupo `
            -OtherAttributes @{ mail = $Email }

        Write-Host "Grupo '$NomeGrupo' criado com e-mail '$Email'!" -ForegroundColor Green
    } else {
        # Se o grupo já existir, atualiza o e-mail e descrição
        Set-ADGroup -Identity $NomeGrupo -Description $Descricao -OtherAttributes @{ mail = $Email }
        Write-Host "Grupo '$NomeGrupo' já existia. Atributos atualizados!" -ForegroundColor Yellow
    }
}