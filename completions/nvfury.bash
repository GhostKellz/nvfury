# nvfury bash completion
# Install: source this file or copy to /etc/bash_completion.d/nvfury

_nvfury() {
    local cur prev words cword
    _init_completion || return

    local commands="build install tune patch profile gpus recommend status versions rollback uninstall check-update update-daemon cache build-cache prime sign benchmark config preflight version help"
    local tune_presets="gaming balanced quiet benchmark status"
    local patch_subcmds="list apply status"
    local profile_subcmds="list show export import"
    local cache_subcmds="status clear"
    local build_cache_subcmds="status clear"
    local daemon_subcmds="enable disable status"
    local prime_subcmds="status discrete integrated hybrid offload setup"
    local sign_subcmds="status setup enroll sign"
    local benchmark_subcmds="run compare export"
    local config_subcmds="show set reset path"
    local uninstall_subcmds="status --dry-run --all --keep-dkms --keep-config --remove-cache --remove-config --restore --backup"

    case "${prev}" in
        nvfury)
            COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
            return
            ;;
        build)
            COMPREPLY=($(compgen -W "--version --source --latest --patches --force --dry-run --no-cache --benchmark" -- "${cur}"))
            return
            ;;
        install)
            COMPREPLY=($(compgen -W "--dkms --direct --no-backup --source --version --sign" -- "${cur}"))
            return
            ;;
        tune)
            COMPREPLY=($(compgen -W "${tune_presets}" -- "${cur}"))
            return
            ;;
        patch)
            COMPREPLY=($(compgen -W "${patch_subcmds}" -- "${cur}"))
            return
            ;;
        profile)
            COMPREPLY=($(compgen -W "${profile_subcmds}" -- "${cur}"))
            return
            ;;
        cache)
            COMPREPLY=($(compgen -W "${cache_subcmds}" -- "${cur}"))
            return
            ;;
        build-cache)
            COMPREPLY=($(compgen -W "${build_cache_subcmds}" -- "${cur}"))
            return
            ;;
        update-daemon|daemon)
            COMPREPLY=($(compgen -W "${daemon_subcmds}" -- "${cur}"))
            return
            ;;
        check-update|update-check)
            COMPREPLY=($(compgen -W "--notify --force" -- "${cur}"))
            return
            ;;
        prime)
            COMPREPLY=($(compgen -W "${prime_subcmds}" -- "${cur}"))
            return
            ;;
        sign)
            COMPREPLY=($(compgen -W "${sign_subcmds}" -- "${cur}"))
            return
            ;;
        benchmark)
            COMPREPLY=($(compgen -W "${benchmark_subcmds}" -- "${cur}"))
            return
            ;;
        config)
            COMPREPLY=($(compgen -W "${config_subcmds}" -- "${cur}"))
            return
            ;;
        uninstall)
            COMPREPLY=($(compgen -W "${uninstall_subcmds}" -- "${cur}"))
            return
            ;;
        preflight|check)
            # No subcommands
            return
            ;;
        rollback)
            COMPREPLY=($(compgen -W "--backup" -- "${cur}"))
            return
            ;;
        show|export)
            if [[ "${words[1]}" == "profile" ]]; then
                COMPREPLY=($(compgen -W "gaming balanced quiet benchmark" -- "${cur}"))
            fi
            return
            ;;
        --version)
            # Could complete with known versions but that requires network
            return
            ;;
        --source|--backup)
            _filedir -d
            return
            ;;
        --patches)
            COMPREPLY=($(compgen -W "default clang-compat gaming-scheduler memory-optimize" -- "${cur}"))
            return
            ;;
        *)
            ;;
    esac

    # Handle second-level subcommands
    if [[ ${cword} -ge 3 ]]; then
        case "${words[1]}" in
            profile)
                case "${words[2]}" in
                    export|show)
                        COMPREPLY=($(compgen -W "gaming balanced quiet benchmark" -- "${cur}"))
                        ;;
                    import)
                        _filedir json
                        ;;
                esac
                ;;
            prime)
                case "${words[2]}" in
                    offload)
                        COMPREPLY=($(compgen -W "--app" -- "${cur}"))
                        ;;
                esac
                ;;
            benchmark)
                case "${words[2]}" in
                    run|compare)
                        COMPREPLY=($(compgen -W "--iterations --output" -- "${cur}"))
                        ;;
                    export)
                        _filedir json
                        ;;
                esac
                ;;
            sign)
                case "${words[2]}" in
                    setup)
                        COMPREPLY=($(compgen -W "--key --cert" -- "${cur}"))
                        ;;
                esac
                ;;
        esac
    fi
}

complete -F _nvfury nvfury
