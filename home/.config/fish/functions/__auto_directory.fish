function __auto_directory --argument-names name --description 'Expand a unique folder name prefixed with ! to a cd command'
    test (count $argv) -eq 1; or return 1
    string match --quiet --regex '^![\p{L}\p{N}_][\p{L}\p{N}_.-]*$' -- "$name"; or return 1

    # Preserve explicit abbreviations and commands with the full prefixed name.
    if type --query -- "$name"; or abbr --query "$name"
        return 1
    end
    set name (string sub --start 2 -- "$name")
    set -l error
    set -l matches
    if not set -q auto_directory_root; or not test -d "$auto_directory_root"
        set error 'Directory shortcut error: the search root does not exist.'
    else
        # Do not follow symlinks, descend into application data or project dependencies.
        set matches (command /usr/bin/find "$auto_directory_root" -type d \( \
        -name '.*' -o -name Library -o -name Applications -o -name config-backups \
        -o -name node_modules -o -name target -o -name build -o -name dist \
        -o -name vendor -o -name venv -o -name __pycache__ -o -name Pods \
        -o -name DerivedData -o -name '*.app' -o -name '*.photoslibrary' \
        -o -name '*.musiclibrary' \) -prune \
        -o -type d -name "$name" -print0 2>/dev/null | string split0)

        if test (count $matches) -gt 1
            set error "Directory shortcut error: multiple folders named '$name'. Use cd with the full path or create a manual abbreviation."
        else if test (count $matches) -eq 0
            set error "Directory shortcut error: folder '$name' was not found among searchable folders."
        end
    end

    # Print errors only when the expanded command runs, not during line editing.
    if set -q error[1]
        printf "printf '%%s\\n' %s >&2; false\n" (string escape -- "$error")
        return 0
    end

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
