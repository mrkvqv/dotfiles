zed() {
    if (( $# == 0 )); then
        command zed .
    else
        command zed "$@"
    fi
}
alias ab="cd ~/Documents/sem4/ab"
alias asd2="cd ~/Documents/sem4/asd2"
alias ajzo="cd ~/Documents/sem4/ajzo"
alias pum="cd ~/Documents/sem4/pum"
alias ip="cd ~/Documents/sem4/ip"
alias am="cd ~/Documents/sem4/am"

if (( $+commands[zoxide] )); then
    eval "$(zoxide init zsh)"
fi
