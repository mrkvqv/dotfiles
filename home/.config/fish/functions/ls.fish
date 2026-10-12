function ls --wraps nls --description 'List files with the shared Zed and Ghostty colors'
    command /usr/bin/python3 (path resolve (status dirname)/../nls_table.py) $argv
end
