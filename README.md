# Конфиги Mac

Личные настройки Fish, Zsh, Ghostty, Zed, GitHub CLI, Karabiner, OpenCode,
qBittorrent, Starship и скрипт распределения приложений по рабочим столам.
Тема **Midnight MacBook** в Zed служит источником цветов для Ghostty и `ls`.

## Содержимое

- `home/` — 32 рабочих файла настроек и скриптов с исходными путями относительно домашней папки.
- `snapshots/` — отдельные настройки и списки расширений Zen, Raycast и Zed.
- `Brewfile` — установленный набор приложений и утилит; при чистке пакеты не менялись.
- `scripts/sync.py` — повторный сбор конфигов по явному списку.
- `scripts/check_secrets.py` — проверка снимка и подготовленных к коммиту файлов.
- `scripts/restore.py` — восстановление рабочих конфигов с резервной копией существующих файлов.

История, cookies, пароли, токены, учётные записи, базы данных, кэши,
`node_modules`, скачанные расширения и резервные копии в репозиторий не входят.
Снимок Raycast содержит доступные обычные настройки внешнего вида и список
расширений; авторизация, чаты и данные расширений остаются локально.
Снимок Zen содержит выбранные постоянные настройки, сочетания клавиш, CSS и
список расширений. Он не содержит полного браузерного профиля.

## Обновить репозиторий

```sh
cd ~/dotfiles
/usr/bin/python3 scripts/sync.py
/usr/bin/python3 scripts/check_secrets.py
git add home snapshots managed-files.json
git commit -m "Update device configuration"
git push
```

После нового клонирования включить проверку перед коммитом:

```sh
git config core.hooksPath .githooks
```

Проверка покрывает известные форматы токенов и чувствительные ключи; добавляй
новые файлы настроек в список `PATTERNS`, а не всю домашнюю папку.

## Восстановить конфиги

Просмотр списка файлов:

```sh
/usr/bin/python3 scripts/restore.py --dry-run
```

Восстановление:

```sh
/usr/bin/python3 scripts/restore.py
```

Прежние файлы сохраняются в `~/config-backups/<дата>_before-dotfiles-restore`.
Настройки qBittorrent объединяются с существующими; локальные пароли и cookies
сохраняются. После восстановления открой новую вкладку терминала, перезагрузи
конфиг Ghostty через **⌘⇧,** и при необходимости перезапусти Zed.

Zen/Raycast снимки восстанавливаются отдельно средствами приложений. При
переносе сочетаний клавиш Zen используй текущий профиль, указанный в
`~/.config/zen/installs.ini`, после закрытия браузера. Профили не переносились.

## Темы и рабочие столы

Меняй палитру в `~/.config/zed/themes/midnight-macbook.json`, затем выполняй
`theme-sync` и **⌘⇧,** в Ghostty. `ls` читает палитру при каждом запуске;
заголовки и номера строк жирные, `target` белый, Git-состояния имеют свои цвета.

Исходник Desktop Assignments хранится в `home/.config/desktop-assignments-sync.swift`.
Сборка после восстановления:

```sh
mkdir -p ~/.local/bin
swiftc -O ~/.config/desktop-assignments-sync.swift -o ~/.local/bin/desktop-assignments-sync
```

LaunchAgent-файлы используют `__HOME__`, который заменяет скрипт восстановления.
Скрипт не загружает агенты автоматически и не меняет распределение рабочих
столов. Подробности — в `home/.config/desktop-assignments.README.md`.

## Проверки

```sh
/usr/bin/python3 scripts/test_nls.py
/usr/bin/python3 scripts/check_secrets.py
```

Тесты проверяют Git-цвета, белый `target`, отсутствие цветов при `NO_COLOR` и
`--no-color`, обычный вывод в pipe и передачу кода ошибки из `nls`.

Результаты чистки перечислены в `CLEANUP.md`.
