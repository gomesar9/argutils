# shellcheck shell=bash

aws-ch-profile() {
    command -v aws >/dev/null 2>&1 || { echo "aws cli não encontrado"; return 1; }
    command -v fzf >/dev/null 2>&1 || { echo "fzf não encontrado"; return 1; }

    local profiles profile resp

    profiles="$(aws configure list-profiles 2>/dev/null)"

    if [ -z "$profiles" ]; then
        echo "Nenhum profile AWS encontrado."
        printf "Criar novo profile SSO agora? [s/N] "
        read -r resp
        case "$resp" in
            [sS]*)
                aws configure sso || return 1
                profiles="$(aws configure list-profiles 2>/dev/null)"
                if [ -z "$profiles" ]; then
                    echo "Nenhum profile criado. Abortando."
                    return 1
                fi
                ;;
            *)
                echo "Execute 'aws configure sso' para criar um profile."
                return 1
                ;;
        esac
    fi

    profile="$(echo "$profiles" | fzf --prompt="Selecionar profile: ")" || return 1
    [ -z "$profile" ] && return 1

    echo "Checando autenticação SSO: $profile..."

    if aws sts get-caller-identity --profile "$profile" >/dev/null 2>&1; then
        echo "✅ Já autenticado."
    else
        echo "SSO não autenticado. Executando login..."
        aws sso login --profile "$profile" || return 1
    fi

    export AWS_PROFILE="$profile"
    echo "✅ Profile configurado: $profile"
}
