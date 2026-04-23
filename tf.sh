#!/bin/bash

function _help {
    echo "Usage: $0 -p (n|t) | -s (n|f) | -a (n|f) | -d (n|t) | -c (a|f|k) [-o FILE]"
    echo "  -p (n: none | t: targets): plan"
    echo "  -s (n: none | f: filter):  show plan"
    echo "  -a (n: none | f: filter):  apply (f: pick targets by filter)"
    echo "  -d (n: none | t: targets): destroy (t: pick targets → plan → confirm → apply)"
    echo "  -c (a: all | f: pick | k: keep N newest): clean tfplan files"
    echo "  -o FILE: plan filename (plan/destroy mode) | output file (show mode) | N to keep (clean -k mode, default 5)"
    echo "  -h: show usage examples"
    exit 1
}

function _examples {
    echo "Examples:"
    echo
    echo "  # Plan"
    echo "  $0 -p n               # plan, auto-named output"
    echo "  $0 -p n -o myplan     # plan, custom output filename"
    echo "  $0 -p t               # plan with fzf target selection"
    echo
    echo "  # Show"
    echo "  $0 -s n               # show picked plan (full)"
    echo "  $0 -s f               # show picked plan filtered by change type"
    echo "  $0 -s n -o out.txt    # show picked plan, save to file"
    echo
    echo "  # Apply"
    echo "  $0 -a n               # pick plan → optional show → confirm → apply"
    echo "  $0 -a n               # pick 'novo' → run new plan → apply"
    echo "  $0 -a f               # pick plan → filter by change type → pick targets → apply"
    echo
    echo "  # Destroy"
    echo "  $0 -d n               # plan destroy, save plan"
    echo "  $0 -d t               # pick targets → plan destroy → confirm → apply"
    echo
    echo "  # Clean"
    echo "  $0 -c a               # delete all tfplans (with confirmation)"
    echo "  $0 -c f               # fzf multiselect → delete picked"
    echo "  $0 -c k               # keep 5 most recent, delete rest"
    echo "  $0 -c k -o 10         # keep 10 most recent, delete rest"
    exit 0
}

mode=''
use_targets=''
filter=''
output_file=''
clean_mode=''

while getopts "p:s:o:a:d:c:h" opt; do
    case ${opt} in
    a)
        mode="apply"
        [ "$OPTARG" == "f" ] && use_targets=1
        ;;
    c)
        mode="clean"
        clean_mode="$OPTARG"
        ;;
    d)
        mode="destroy"
        [ "$OPTARG" == "t" ] && use_targets=1
        ;;
    p)
        mode="plan"
        [ "$OPTARG" == "t" ] && use_targets=1
        ;;
    s)
        mode="show"
        [ "$OPTARG" == "f" ] && filter=1
        ;;
    h)
        _examples
        ;;
    o)
        output_file="$OPTARG"
        ;;
    *)
        _help
        ;;
    esac
done

[ -z "$mode" ] && _help

function selectFilter() {
    local selected
    selected=$(printf "%s\n" created updated destroyed replaced | fzf -m --height=40% --border) || return 1
    local -a arr
    mapfile -t arr <<<"$selected"
    [ "${#arr[@]}" -eq 0 ] && return 1

    if [ "${#arr[@]}" -eq 1 ]; then
        printf "%s\n" "${arr[0]}"
    else
        local joined
        joined=$(
            IFS='|'
            echo "${arr[*]}"
        )
        printf "(%s)\n" "$joined"
    fi
}

function pickPlan() {
    local extra="$1"
    local list
    list="$(find . -name '*.tfplan' | sort -r)"
    [ -n "$extra" ] && list="${list:+$list$'\n'}$extra"
    local tfplan
    tfplan="$(echo "$list" | fzf --height=40% --border)" || return 1
    [ -z "$tfplan" ] && return 1
    echo "$tfplan"
}

function showPlanPrompt() {
    local tfplan="$1"
    read -r -p "Mostrar plan? [y/N] " show_plan
    [[ "$show_plan" =~ ^[Yy]$ ]] && terraform show "$tfplan"
}

function newPlanFile() {
    local suffix="${1:-}"
    [ -n "$suffix" ] && echo "$(date +'%y%m%d-%H%M%S')-${suffix}.tfplan" || echo "$(date +'%y%m%d-%H%M%S').tfplan"
}

function runPlan() {
    local out="$1"
    shift
    terraform plan "$@" -out="$out"
}

function buildTargetFlags() {
    local -a flags=()
    while IFS= read -r resource; do
        [ -n "$resource" ] && flags+=("-target=$resource")
    done <<<"$1"
    printf '%s\n' "${flags[@]}"
}

if [ "$mode" == "plan" ]; then
    [ -z "$output_file" ] && output_file="$(newPlanFile)"

    if [ -n "$use_targets" ]; then
        resources=$(terraform state list) || exit 1
        selected=$(echo "$resources" | fzf -m --height=60% --border --prompt="Select targets: ") || exit 1
        [ -z "$selected" ] && echo "Nada selecionado." && exit 0

        mapfile -t target_flags < <(buildTargetFlags "$selected")
        runPlan "$output_file" "${target_flags[@]}"
    else
        runPlan "$output_file"
    fi
fi

if [ "$mode" == "show" ]; then
    tfplan=$(pickPlan) || exit 1

    if [ -n "$filter" ]; then
        filter_pat=$(selectFilter) || exit 1
        echo "Aplicando filtros: $filter_pat"
        if [ -n "$output_file" ]; then
            terraform show -no-color "$tfplan" | grep -E "be $filter_pat" | tee "$output_file"
        else
            terraform show -no-color "$tfplan" | grep -E "be $filter_pat"
        fi
    else
        if [ -n "$output_file" ]; then
            terraform show -no-color "$tfplan" | tee "$output_file"
        else
            terraform show -no-color "$tfplan"
        fi
    fi
fi

if [ "$mode" == "destroy" ]; then
    [ -z "$output_file" ] && output_file="$(newPlanFile "destroy")"

    if [ -n "$use_targets" ]; then
        resources=$(terraform state list) || exit 1
        selected=$(echo "$resources" | fzf -m --height=60% --border --prompt="Select resources to destroy: ") || exit 1
        [ -z "$selected" ] && echo "Nada selecionado." && exit 0

        mapfile -t target_flags < <(buildTargetFlags "$selected")

        runPlan "$output_file" -destroy "${target_flags[@]}" || exit 1

        echo
        read -r -p "Aplicar destroy? [y/N] " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            terraform apply "$output_file"
        fi
    else
        runPlan "$output_file" -destroy
    fi
fi

if [ "$mode" == "apply" ]; then
    tfplan=$(pickPlan "novo") || exit 1

    if [ "$tfplan" == "novo" ]; then
        tfplan="$(newPlanFile)"
        runPlan "$tfplan" -detailed-exitcode
        case $? in
            1) exit 1 ;;
            0) exit 0 ;;
        esac
    else
        showPlanPrompt "$tfplan"
    fi

    if [ -n "$use_targets" ]; then
        filter_pat=$(selectFilter) || exit 1

        resources=$(terraform show -no-color "$tfplan" | grep -E "be $filter_pat" |
            grep '^ *#' |
            sed -E 's/^ *# ([^ ]+).*/\1/')

        selected=$(echo "$resources" | fzf -m --height=60% --border --prompt="Selecione resources para target: ") || exit 1
        [ -z "$selected" ] && echo "Nada selecionado." && exit 0

        mapfile -t target_flags < <(buildTargetFlags "$selected")
        cmd=(terraform apply "${target_flags[@]}")

        echo
        echo "Comando gerado:"
        echo "${cmd[*]}"
        echo

        read -r -p "Executar? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] && "${cmd[@]}"
    else
        read -r -p "Aplicar? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] && terraform apply "$tfplan"
    fi
fi

if [ "$mode" == "clean" ]; then
    case "$clean_mode" in
    a)
        mapfile -t files < <(find . -name '*.tfplan' | sort -r)
        [ "${#files[@]}" -eq 0 ] && echo "Nenhum tfplan encontrado." && exit 0
        printf '%s\n' "${files[@]}"
        echo
        read -r -p "Deletar ${#files[@]} tfplan(s)? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] && rm "${files[@]}"
        ;;
    f)
        selected=$(find . -name '*.tfplan' | sort -r |
            fzf -m --height=60% --border --prompt="Selecione para deletar: ") || exit 1
        [ -z "$selected" ] && echo "Nada selecionado." && exit 0
        echo "$selected"
        echo
        read -r -p "Deletar selecionados? [y/N] " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            while IFS= read -r f; do rm "$f"; done <<<"$selected"
        fi
        ;;
    k)
        keep="${output_file:-5}"
        mapfile -t files < <(find . -name '*.tfplan' | sort -r)
        [ "${#files[@]}" -le "$keep" ] && echo "Só ${#files[@]} tfplan(s), nada a deletar (keep=$keep)." && exit 0
        to_delete=("${files[@]:$keep}")
        printf '%s\n' "${to_delete[@]}"
        echo
        read -r -p "Deletar ${#to_delete[@]} tfplan(s) (mantendo $keep mais recentes)? [y/N] " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] && rm "${to_delete[@]}"
        ;;
    *)
        _help
        ;;
    esac
fi
