if status is-interactive
    function fish_user_key_bindings
        bind tab accept-autosuggestion
        bind shift-tab complete
        bind -M insert tab accept-autosuggestion
        bind -M insert shift-tab complete
        bind ctrl-r history-pager
        bind -M insert ctrl-r history-pager
    end
end
