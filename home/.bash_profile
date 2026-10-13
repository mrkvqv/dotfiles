# Login shells load shared environment settings, then interactive Bash settings.
if [ -r "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi
if [ -r "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
