function __auto_directory --argument-names name --description 'Expand a unique folder name to a cd command'
    test (count $argv) -eq 1; or return 1
    string match --quiet --regex '^[\p{L}\p{N}_][\p{L}\p{N}_.-]*$' -- "$name"; or return 1

    # Never replace commands, shell syntax or an explicit abbreviation.
    if type --query -- "$name"; or abbr --query "$name"
        return 1
    end
    if contains -- "$name" and or not if else end for while switch case begin function command builtin exec time
        return 1
    end
    set -q auto_directory_root; or return 1
    test -d "$auto_directory_root"; or return 1

    # Do not follow symlinks, descend into application data or project dependencies.
    set -l matches (command /usr/bin/find "$auto_directory_root" -type d \( \
        -name '.*' -o -name Library -o -name Applications -o -name config-backups \
        -o -name node_modules -o -name target -o -name build -o -name dist \
        -o -name vendor -o -name venv -o -name __pycache__ -o -name Pods \
        -o -name DerivedData -o -name '*.app' -o -name '*.photoslibrary' \
        -o -name '*.musiclibrary' \) -prune \
        -o -type d -name "$name" -print0 2>/dev/null | string split0)

    if test (count $matches) -gt 1
        printf 'auto-cd: несколько папок с именем "%s"; используй cd с полным путём.\n' "$name" >&2
        return 1
    end
    test (count $matches) -eq 1; or return 1

    if test "$matches[1]" = "$HOME"
        printf 'cd ~\n'
        return 0
    end
    set -l prefix "$HOME/"
    set -l prefix_length (string length -- "$prefix")
    if test (string sub --length $prefix_length -- "$matches[1]") = "$prefix"
        set -l relative (string sub --start (math $prefix_length + 1) -- "$matches[1]")
        printf 'cd ~/%s\n' (string escape -- "$relative")
    else
        printf 'cd %s\n' (string escape -- "$matches[1]")
    end
end
