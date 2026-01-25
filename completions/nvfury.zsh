#compdef nvfury

# nvfury zsh completion
# Install: copy to a directory in $fpath, e.g., ~/.zsh/completions/

_nvfury() {
    local -a commands
    local -a tune_presets
    local -a patch_subcmds
    local -a profile_subcmds
    local -a cache_subcmds
    local -a daemon_subcmds
    local -a prime_subcmds
    local -a sign_subcmds
    local -a benchmark_subcmds
    local -a config_subcmds
    local -a uninstall_subcmds

    commands=(
        'build:Fetch and build optimized NVIDIA modules'
        'install:Install built modules'
        'tune:Apply module parameter preset'
        'patch:Manage patches'
        'profile:Export/import tuning profiles'
        'gpus:Detect and list all GPUs'
        'recommend:Show recommended patches for your GPU'
        'status:Show current driver status'
        'versions:List available driver versions'
        'rollback:Restore previous driver'
        'check-update:Check for available driver updates'
        'update-daemon:Manage automatic update checking'
        'cache:Manage ccache for compilation'
        'build-cache:Manage source hash cache'
        'prime:Manage hybrid graphics (PRIME)'
        'sign:SecureBoot module signing'
        'benchmark:Performance benchmarking'
        'config:Configuration management'
        'preflight:Pre-build compatibility checks'
        'uninstall:Remove nvfury-installed drivers'
        'version:Show version information'
        'help:Show help message'
    )

    tune_presets=(
        'gaming:Low latency, max performance'
        'balanced:Balance of performance and efficiency'
        'quiet:Power saving, reduced heat/noise'
        'benchmark:Maximum performance for testing'
        'status:Show current tuning status'
    )

    patch_subcmds=(
        'list:List available patches'
        'apply:Apply a patch'
        'status:Show applied patches'
    )

    profile_subcmds=(
        'list:List available presets'
        'show:Show preset parameters'
        'export:Export preset to JSON'
        'import:Import profile from JSON'
    )

    cache_subcmds=(
        'status:Show ccache statistics'
        'clear:Clear ccache'
    )

    daemon_subcmds=(
        'enable:Install systemd timer'
        'disable:Remove systemd timer'
        'status:Show timer status'
    )

    prime_subcmds=(
        'status:Show current graphics mode'
        'offload:Run application on NVIDIA GPU'
        'setup:Configure PRIME with system files'
    )

    sign_subcmds=(
        'status:Show signing key status'
        'setup:Generate MOK signing key'
        'enroll:Enroll MOK certificate'
        'sign:Sign kernel modules'
    )

    benchmark_subcmds=(
        'run:Run performance benchmark'
        'compare:Compare with stock driver'
        'export:Export results to JSON'
    )

    config_subcmds=(
        'show:Show current configuration'
        'set:Set configuration value'
        'reset:Reset to defaults'
        'path:Show config file path'
    )

    uninstall_subcmds=(
        'status:Show what would be removed'
    )

    _arguments -C \
        '1: :->command' \
        '*:: :->args'

    case $state in
        command)
            _describe -t commands 'nvfury command' commands
            ;;
        args)
            case $words[1] in
                build)
                    _arguments \
                        '--version[Build specific version]:version:' \
                        '--source[Build from local source]:directory:_files -/' \
                        '--latest[Fetch and build latest]' \
                        '--patches[Apply patches]:patches:(default clang-compat gaming-scheduler memory-optimize)' \
                        '--force[Force rebuild]' \
                        '--dry-run[Show what would be done]' \
                        '--no-cache[Ignore build cache]' \
                        '--benchmark[Enable benchmark instrumentation]'
                    ;;
                install)
                    _arguments \
                        '--dkms[Install via DKMS]' \
                        '--direct[Install directly]' \
                        '--no-backup[Skip backup]' \
                        '--source[Source directory]:directory:_files -/' \
                        '--version[Driver version]:version:' \
                        '--sign[Sign modules for SecureBoot]'
                    ;;
                tune)
                    _describe -t presets 'tune preset' tune_presets
                    ;;
                patch)
                    _describe -t subcmds 'patch subcommand' patch_subcmds
                    ;;
                profile)
                    _describe -t subcmds 'profile subcommand' profile_subcmds
                    ;;
                cache)
                    _describe -t subcmds 'cache subcommand' cache_subcmds
                    ;;
                build-cache)
                    _describe -t subcmds 'build-cache subcommand' cache_subcmds
                    ;;
                update-daemon|daemon)
                    _describe -t subcmds 'daemon subcommand' daemon_subcmds
                    ;;
                check-update)
                    _arguments \
                        '--notify[Send desktop notification]' \
                        '--force[Force recheck]'
                    ;;
                prime)
                    _describe -t subcmds 'prime subcommand' prime_subcmds
                    ;;
                sign)
                    _describe -t subcmds 'sign subcommand' sign_subcmds
                    ;;
                benchmark)
                    _describe -t subcmds 'benchmark subcommand' benchmark_subcmds
                    ;;
                config)
                    _describe -t subcmds 'config subcommand' config_subcmds
                    ;;
                uninstall)
                    _arguments \
                        'status[Show what would be removed]' \
                        '--dry-run[Show what would be done]' \
                        '-n[Show what would be done]' \
                        '--all[Also remove cache and config]' \
                        '--keep-dkms[Keep DKMS entries]' \
                        '--keep-config[Keep modprobe config]' \
                        '--remove-cache[Remove cache directory]' \
                        '--remove-config[Remove config directory]' \
                        '--restore[Restore from backup]' \
                        '--backup[Backup path]:directory:_files -/'
                    ;;
                preflight|check)
                    # No subcommands
                    ;;
                rollback)
                    _arguments \
                        '--backup[Backup path]:directory:_files -/'
                    ;;
            esac
            ;;
    esac
}

_nvfury "$@"
