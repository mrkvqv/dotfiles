# Compatible with macOS Bash 3.2 and newer Bash versions.
case $- in
    *i*) ;;
    *) return ;;
esac
[[ ${__MRKVQV_BASH_LOADED:-} == 1 ]] && return
__MRKVQV_BASH_LOADED=1

# Make installed tools available even when Bash starts outside Fish.
__bash_add_path() {
    [[ -d $1 ]] || return 0
    case :$PATH: in
        *:"$1":*) ;;
        *) PATH="$1${PATH:+:$PATH}" ;;
    esac
}
__bash_add_path /usr/local/bin
__bash_add_path /opt/homebrew/sbin
__bash_add_path /opt/homebrew/bin
__bash_add_path "$HOME/.cargo/bin"
__bash_add_path "$HOME/.npm-global/bin"
__bash_add_path "$HOME/.local/bin"
unset -f __bash_add_path
export PATH

# Load the editor once before Starship, and attach it after all shell setup.
if (( BASH_VERSINFO[0] >= 4 )) && [[ ${TERM:-dumb} != dumb ]] &&
    [[ -z ${BLE_VERSION:-} && -r "$HOME/.local/share/blesh/ble.sh" ]]; then
    source "$HOME/.local/share/blesh/ble.sh" --noattach
fi

# Append history instead of overwriting another tab's commands.
HISTSIZE=10000
HISTFILESIZE=50000
HISTCONTROL=ignoreboth
shopt -s histappend cmdhist checkwinsize
if [[ -z ${BLE_VERSION:-} ]]; then
    __bash_sync_history() {
        local previous_status=$?
        history -a
        history -n
        return "$previous_status"
    }
    PROMPT_COMMAND="__bash_sync_history${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi

# Readline settings apply only to Bash, leaving other applications alone.
if [[ -z ${BLE_VERSION:-} ]]; then
    bind 'set completion-ignore-case on'
    bind 'set show-all-if-ambiguous on'
    bind 'set mark-symlinked-directories on'
    bind 'set bell-style none'
    bind '"\e[A": history-search-backward'
    bind '"\e[B": history-search-forward'
    bind '"\eOA": history-search-backward'
    bind '"\eOB": history-search-forward'
    bind '"\C-r": reverse-search-history'
    bind '"\t": complete'
    bind '"\e[Z": menu-complete'
fi

# Use the same file listing and navigation tools as Fish.
if command -v nls >/dev/null 2>&1; then
    alias ls='nls'
fi
alias ll='ls -l'
alias la='ls -A'
alias ..='cd ..'
alias ...='cd ../..'
alias docs='cd "$HOME/Documents"'
alias config='cd "$HOME/.config"'
alias dotfiles='cd "$HOME/dotfiles"'
alias work='cd "$HOME/Documents/work"'
alias rust='cd "$HOME/Documents/sem5/rust"'
alias net='cd "$HOME/Documents/sem5/net"'

mkcd() {
    if [[ $# != 1 ]]; then
        printf '%s\n' 'Usage: mkcd DIRECTORY' >&2
        return 2
    fi
    command mkdir -p -- "$1" && builtin cd -- "$1"
}

zed() {
    if [[ $# == 0 ]]; then
        command zed .
    else
        command zed "$@"
    fi
}

# Share the existing Starship theme with Fish; provide a simple fallback.
if [[ ${TERM:-dumb} != dumb ]] && command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
elif [[ ${TERM:-dumb} == dumb ]]; then
    PS1='bash \w > '
else
    PS1='\n\[\033[1;38;2;158;184;216m\]bash\[\033[0m\] \[\033[37m\]\w\[\033[0m\]\n\[\033[35m\]❯\[\033[0m\] '
fi
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init bash)"
fi
if [[ ${BLE_VERSION:-} ]]; then
    ble-attach
fi
