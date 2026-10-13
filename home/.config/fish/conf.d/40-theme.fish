# Fish-specific styles; shared input colors are read from shell/colors.conf.
if not status is-interactive
    return
end

set --global fish_color_cancel --reverse
set --global fish_color_cwd green
set --global fish_color_cwd_root red
set --global fish_color_gray
set --global fish_color_history_current --bold
set --global fish_color_host --reset
set --global fish_color_host_remote yellow
set --global fish_color_normal --reset
set --global fish_color_search_match white --bold --background=brblack
set --global fish_color_selection white --bold --background=brblack
set --global fish_color_status red
set --global fish_color_user brgreen
set --global fish_color_valid_path --underline=single
set --global fish_pager_color_completion BBB
set --global fish_pager_color_description yellow --italics
set --global fish_pager_color_prefix --bold --underline=single
set --global fish_pager_color_progress brwhite --bold --background=cyan
set --global fish_pager_color_selected_background --reverse
set --global fish_pager_color_selected_completion
set --global fish_pager_color_selected_description
set --global fish_pager_color_selected_prefix

begin
    set -l palette_file (path dirname (status filename))/../../shell/colors.conf
    if test -r "$palette_file"
        while read -l line
            set -l fields (string split --max 1 = -- "$line")
            test (count $fields) -eq 2; or continue
            string match --quiet --regex '^[0-9a-fA-F]{6}$' -- "$fields[2]"; or continue
            switch "$fields[1]"
                case command
                    set -g fish_color_command "$fields[2]"
                case parameter
                    set -g fish_color_param "$fields[2]"
                case path
                    # Fish adds this color to parameters that are valid paths.
                    set -g fish_color_valid_path "$fields[2]" --underline=single
                case suggestion
                    set -g fish_color_autosuggestion "$fields[2]"
                case error comment keyword option quote operator escape end
                    set -g fish_color_$fields[1] "$fields[2]"
                    if test "$fields[1]" = operator
                        set -g fish_color_redirection "$fields[2]" --bold
                    end
            end
        end < "$palette_file"
    end
end
