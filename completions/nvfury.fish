# nvfury fish completion
# Install: copy to ~/.config/fish/completions/nvfury.fish

# Disable file completion by default
complete -c nvfury -f

# Main commands
complete -c nvfury -n __fish_use_subcommand -a build -d 'Fetch and build optimized NVIDIA modules'
complete -c nvfury -n __fish_use_subcommand -a install -d 'Install built modules'
complete -c nvfury -n __fish_use_subcommand -a tune -d 'Apply module parameter preset'
complete -c nvfury -n __fish_use_subcommand -a patch -d 'Manage patches'
complete -c nvfury -n __fish_use_subcommand -a profile -d 'Export/import tuning profiles'
complete -c nvfury -n __fish_use_subcommand -a gpus -d 'Detect and list all GPUs'
complete -c nvfury -n __fish_use_subcommand -a recommend -d 'Show recommended patches for your GPU'
complete -c nvfury -n __fish_use_subcommand -a status -d 'Show current driver status'
complete -c nvfury -n __fish_use_subcommand -a versions -d 'List available driver versions'
complete -c nvfury -n __fish_use_subcommand -a rollback -d 'Restore previous driver'
complete -c nvfury -n __fish_use_subcommand -a check-update -d 'Check for available driver updates'
complete -c nvfury -n __fish_use_subcommand -a update-daemon -d 'Manage automatic update checking'
complete -c nvfury -n __fish_use_subcommand -a cache -d 'Manage ccache for compilation'
complete -c nvfury -n __fish_use_subcommand -a build-cache -d 'Manage source hash cache'
complete -c nvfury -n __fish_use_subcommand -a prime -d 'Manage hybrid graphics (PRIME)'
complete -c nvfury -n __fish_use_subcommand -a sign -d 'SecureBoot module signing'
complete -c nvfury -n __fish_use_subcommand -a benchmark -d 'Performance benchmarking'
complete -c nvfury -n __fish_use_subcommand -a config -d 'Configuration management'
complete -c nvfury -n __fish_use_subcommand -a preflight -d 'Pre-build compatibility checks'
complete -c nvfury -n __fish_use_subcommand -a uninstall -d 'Remove nvfury-installed drivers'
complete -c nvfury -n __fish_use_subcommand -a version -d 'Show version information'
complete -c nvfury -n __fish_use_subcommand -a help -d 'Show help message'

# build options
complete -c nvfury -n '__fish_seen_subcommand_from build' -l version -d 'Build specific version'
complete -c nvfury -n '__fish_seen_subcommand_from build' -l source -d 'Build from local source' -r -F
complete -c nvfury -n '__fish_seen_subcommand_from build' -l latest -d 'Fetch and build latest'
complete -c nvfury -n '__fish_seen_subcommand_from build' -l patches -d 'Apply patches' -r -a 'default clang-compat gaming-scheduler memory-optimize'
complete -c nvfury -n '__fish_seen_subcommand_from build' -l force -s f -d 'Force rebuild'
complete -c nvfury -n '__fish_seen_subcommand_from build' -l dry-run -d 'Show what would be done'
complete -c nvfury -n '__fish_seen_subcommand_from build' -l no-cache -d 'Ignore build cache'
complete -c nvfury -n '__fish_seen_subcommand_from build' -l benchmark -d 'Enable benchmark instrumentation'

# install options
complete -c nvfury -n '__fish_seen_subcommand_from install' -l dkms -d 'Install via DKMS'
complete -c nvfury -n '__fish_seen_subcommand_from install' -l direct -d 'Install directly'
complete -c nvfury -n '__fish_seen_subcommand_from install' -l no-backup -d 'Skip backup'
complete -c nvfury -n '__fish_seen_subcommand_from install' -l source -d 'Source directory' -r -F
complete -c nvfury -n '__fish_seen_subcommand_from install' -l version -d 'Driver version'
complete -c nvfury -n '__fish_seen_subcommand_from install' -l sign -d 'Sign modules for SecureBoot'

# tune presets
complete -c nvfury -n '__fish_seen_subcommand_from tune' -a gaming -d 'Low latency, max performance'
complete -c nvfury -n '__fish_seen_subcommand_from tune' -a balanced -d 'Balance of performance and efficiency'
complete -c nvfury -n '__fish_seen_subcommand_from tune' -a quiet -d 'Power saving, reduced heat/noise'
complete -c nvfury -n '__fish_seen_subcommand_from tune' -a benchmark -d 'Maximum performance for testing'
complete -c nvfury -n '__fish_seen_subcommand_from tune' -a status -d 'Show current tuning status'

# patch subcommands
complete -c nvfury -n '__fish_seen_subcommand_from patch' -a list -d 'List available patches'
complete -c nvfury -n '__fish_seen_subcommand_from patch' -a apply -d 'Apply a patch'
complete -c nvfury -n '__fish_seen_subcommand_from patch' -a status -d 'Show applied patches'

# profile subcommands
complete -c nvfury -n '__fish_seen_subcommand_from profile' -a list -d 'List available presets'
complete -c nvfury -n '__fish_seen_subcommand_from profile' -a show -d 'Show preset parameters'
complete -c nvfury -n '__fish_seen_subcommand_from profile' -a export -d 'Export preset to JSON'
complete -c nvfury -n '__fish_seen_subcommand_from profile' -a import -d 'Import profile from JSON'

# cache subcommands
complete -c nvfury -n '__fish_seen_subcommand_from cache' -a status -d 'Show ccache statistics'
complete -c nvfury -n '__fish_seen_subcommand_from cache' -a clear -d 'Clear ccache'

# build-cache subcommands
complete -c nvfury -n '__fish_seen_subcommand_from build-cache' -a status -d 'Show cached builds'
complete -c nvfury -n '__fish_seen_subcommand_from build-cache' -a clear -d 'Clear build cache'

# update-daemon subcommands
complete -c nvfury -n '__fish_seen_subcommand_from update-daemon' -a enable -d 'Install systemd timer'
complete -c nvfury -n '__fish_seen_subcommand_from update-daemon' -a disable -d 'Remove systemd timer'
complete -c nvfury -n '__fish_seen_subcommand_from update-daemon' -a status -d 'Show timer status'

# check-update options
complete -c nvfury -n '__fish_seen_subcommand_from check-update' -l notify -d 'Send desktop notification'
complete -c nvfury -n '__fish_seen_subcommand_from check-update' -l force -s f -d 'Force recheck'

# prime subcommands
complete -c nvfury -n '__fish_seen_subcommand_from prime' -a status -d 'Show current graphics mode'
complete -c nvfury -n '__fish_seen_subcommand_from prime' -a offload -d 'Run application on NVIDIA GPU'
complete -c nvfury -n '__fish_seen_subcommand_from prime' -a setup -d 'Configure PRIME with system files'

# sign subcommands
complete -c nvfury -n '__fish_seen_subcommand_from sign' -a status -d 'Show signing key status'
complete -c nvfury -n '__fish_seen_subcommand_from sign' -a setup -d 'Generate MOK signing key'
complete -c nvfury -n '__fish_seen_subcommand_from sign' -a enroll -d 'Enroll MOK certificate'
complete -c nvfury -n '__fish_seen_subcommand_from sign' -a sign -d 'Sign kernel modules'

# benchmark subcommands
complete -c nvfury -n '__fish_seen_subcommand_from benchmark' -a run -d 'Run performance benchmark'
complete -c nvfury -n '__fish_seen_subcommand_from benchmark' -a compare -d 'Compare with stock driver'
complete -c nvfury -n '__fish_seen_subcommand_from benchmark' -a export -d 'Export results to JSON'

# config subcommands
complete -c nvfury -n '__fish_seen_subcommand_from config' -a show -d 'Show current configuration'
complete -c nvfury -n '__fish_seen_subcommand_from config' -a set -d 'Set configuration value'
complete -c nvfury -n '__fish_seen_subcommand_from config' -a reset -d 'Reset to defaults'
complete -c nvfury -n '__fish_seen_subcommand_from config' -a path -d 'Show config file path'

# rollback options
complete -c nvfury -n '__fish_seen_subcommand_from rollback' -l backup -d 'Backup path' -r -F

# uninstall subcommands and options
complete -c nvfury -n '__fish_seen_subcommand_from uninstall' -a status -d 'Show what would be removed'
complete -c nvfury -n '__fish_seen_subcommand_from uninstall' -l dry-run -d 'Show what would be done'
complete -c nvfury -n '__fish_seen_subcommand_from uninstall' -s n -d 'Show what would be done'
complete -c nvfury -n '__fish_seen_subcommand_from uninstall' -l all -d 'Also remove cache and config'
complete -c nvfury -n '__fish_seen_subcommand_from uninstall' -l keep-dkms -d 'Keep DKMS entries'
complete -c nvfury -n '__fish_seen_subcommand_from uninstall' -l keep-config -d 'Keep modprobe config'
complete -c nvfury -n '__fish_seen_subcommand_from uninstall' -l remove-cache -d 'Remove cache directory'
complete -c nvfury -n '__fish_seen_subcommand_from uninstall' -l remove-config -d 'Remove config directory'
complete -c nvfury -n '__fish_seen_subcommand_from uninstall' -l restore -d 'Restore from backup'
complete -c nvfury -n '__fish_seen_subcommand_from uninstall' -l backup -d 'Backup path' -r -F
