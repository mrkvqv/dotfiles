if not status is-interactive
    return
end

if not set -q auto_directory_root
    set -g auto_directory_root $HOME
end

# Resolve folder names when typed; folders created in Finder/Zed work immediately.
# Manual abbreviations in config.fish are added later and keep priority.
abbr --add __auto_directory --position command \
    --regex '^[\p{L}\p{N}_][\p{L}\p{N}_.-]*$' \
    --function __auto_directory
