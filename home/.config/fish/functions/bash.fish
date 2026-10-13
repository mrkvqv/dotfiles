function bash --wraps bash --description 'Run modern Homebrew Bash'
    if test -x /opt/homebrew/bin/bash
        command /opt/homebrew/bin/bash $argv
    else
        command bash $argv
    end
end
