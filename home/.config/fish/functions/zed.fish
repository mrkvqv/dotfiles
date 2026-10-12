function zed --wraps zed --description 'Open the current directory or the supplied paths in Zed'
    if test (count $argv) -eq 0
        command zed .
    else
        command zed $argv
    end
end
