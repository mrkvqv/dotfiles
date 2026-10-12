if not status is-interactive
    return
end

# uni
abbr -a ab "cd ~/Documents/sem4/ab"
abbr -a asd2 "cd ~/Documents/sem4/asd2"
abbr -a ajzo "cd ~/Documents/sem4/ajzo"
abbr -a pum "cd ~/Documents/sem4/pum"
abbr -a io "cd ~/Documents/sem4/io"
abbr -a am "cd ~/Documents/sem4/am"
abbr -a ab_poprawa "cd ~/Documents/sem4/ab_poprawa"
abbr -a rust "cd ~/Documents/sem5/rust"
abbr -a net "cd ~/Documents/sem5/net"

# work
abbr -a work "cd ~/Documents/work"
abbr -a gbw "cd ~/Documents/work/gbw"

# study & own projects
abbr -a ts 'cd ~/Documents/"js&ts"'
abbr -a games "cd ~/Documents/movanicka/games"

# features
abbr -a config "cd ~/.config"
abbr -a docs "cd ~/Documents"
set -g fish_greeting ""
if command -q starship
    starship init fish | source
end
if command -q zoxide
    zoxide init fish | source
end
