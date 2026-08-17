Import-Module ActiveDirectory

# Caminho da OU
$OU = "OU=Grupos Gerais,OU=CRN3,DC=crn3,DC=sp"

# Lista de grupos com Nome, Descrição e E-mail
$Grupos = @(
    @{ 
        Name        = "gS_bAuru_aSsinaturas"
        Description = "Assinaturas Bauru"
        Email       = "noreply_bAuru_assinaturas@crn3.org.br"
    },
    @{ 
        Name        = "gS_cAmpinas_aSsinaturas"
        Description = "Assinaturas Campinas"
        Email       = "noreply_cAmpinas_assinaturas@crn3.org.br"
    },
    @{ 
        Name        = "gS_cAmpogRande_aSsinaturas"
        Description = "Assinaturas Campo Grande"
        Email       = "noreply_cAmpogRande_assinaturas@crn3.org.br"
    },
    @{ 
        Name        = "gS_pResidentepRudente_aSsinaturas"
        Description = "Assinaturas Presidente Prudente"
        Email       = "noreply_pResidentepRudente_assinaturas@crn3.org.br"
    }
    @{ 
        Name        = "gS_rIbeiraopReto_aSsinaturas"
        Description = "Assinaturas Ribeirão Preto"
        Email       = "noreply_rIbeiraopReto_assinaturas@crn3.org.br"
    }
    @{ 
        Name        = "gS_sAntos_aSsinaturas"
        Description = "Assinaturas Santos"
        Email       = "noreply_sAntos_assinaturas@crn3.org.br"
    }
    @{ 
        Name        = "gS_sAojOsEdOrIopReto_aSsinaturas"
        Description = "Assinaturas São José do Rio Preto"
        Email       = "noreply_sAojOsEdOrIopReto_assinaturas@crn3.org.br"
    }
    @{ 
        Name        = "gS_sAojOsedOscAmpos_aSsinaturas"
        Description = "Assinaturas São José dos Campos"
        Email       = "noreply_sAojOsedOscAmpos_assinaturas@crn3.org.br"
    }
    @{ 
        Name        = "gS_sOrocaba_aSsinaturas"
        Description = "Assinaturas Sorocaba"
        Email       = "noreply_sOrocaba_assinaturas@crn3.org.br"
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