# Trojaner's dotfiles

Dotfiles that install my personal configurations to make life easier.  
Includes various configs and their setup scripts for Windows & Linux. The Linux scripts only support Debian based systems.

All configurations are symlinked to the local repo directory for easy updates, so don't delete the repo after running the setup scripts.

**Disclaimer**: the setup scripts automatically add my public key to the authorized keys, which is something you likely don't wanna do, but if you do, I wouldn't mind it :)

## [zsh configuration](https://github.com/Trojaner/dotfiles/blob/main/.zshrc)

![image](https://user-images.githubusercontent.com/1809172/205993917-b928250b-2b1c-4492-9aa1-632a65976ad5.png)

- oh-my-zsh with various [plugins](https://github.com/Trojaner/dotfiles/blob/main/.zshrc#L73) and Agnoster theme
- Windows like terminal input controls (navigation, text selection etc. with ctrl and/or shift + arrow keys)
- Improved command history (ctrl-r)
- Autocomplete for various commands
- Lots of colorization (ls, man-pages, etc.)
- Uses nano as default editor
- Timer that shows how long it took to execute commands
- Needs a [nerd font](https://github.com/ryanoasis/nerd-fonts)

## [Powershell configuration](https://github.com/Trojaner/dotfiles/blob/main/profile.ps1)

![image](https://user-images.githubusercontent.com/1809172/205998160-4117c590-5e66-4732-81a0-1793a8793cdd.png)

- oh-my-posh with Agnoster theme
- Posh-Git / PSReadLine / Get-ChildItemColor / Terminal-Icons plugins
- Removes wget/curl aliases
- Needs a [nerd font](https://github.com/ryanoasis/nerd-fonts) ("Hack" font is installed automatically)

## [Nano config](https://github.com/Trojaner/dotfiles/blob/main/.nanorc)

- Auto intendation, smooth scrolling, soft wrapping, tab-to-space, etc.
- Auto backup @ ~/.nano/backup
- File lock enabled
- Syntax highlighting with [scopatz/nanorc](https://github.com/scopatz/nanorc)

## [Git config](https://github.com/Trojaner/dotfiles/blob/main/.gitconfig)

- nano as default editor
- colored output + color adjustments
- GitHub aliases
- GPG commit signing
- Rebase on pull and merge

## Codex configuration

The setup scripts link `codex/config.toml` and `codex/AGENTS.md` into
`~/.codex` (or `CODEX_HOME` when set). Linked files stay in sync with this repo.
Existing files are preserved in a `dotfiles-backup.*` directory before linking.
Authentication, sessions, and other runtime files remain local.
To link only Codex configuration on Linux or macOS, run `zsh codex/setup.sh`.

Codex setup also installs hourly memory maintenance on macOS, Linux and Windows.
The runner keeps its own stdio app-server alive until consolidation finishes, so
short-lived sessions cannot interrupt it. It uses Python's standard library and a
SQLite lock to prevent overlapping runs, with no Unix socket or file-lock module.
An installed, authenticated Codex CLI and `uv` are required; setup creates a Python
3.12 environment automatically. The Windows installer installs `uv` with WinGet
when needed.

| Platform | Scheduler | Logs |
|---|---|---|
| macOS | User LaunchAgent | `~/Library/Logs/codex-memory-consolidation/` |
| Linux (including WSL with systemd) | systemd user service and hourly timer | `${XDG_STATE_HOME:-~/.local/state}/codex-memory-consolidation/` |
| Windows | Task Scheduler, current interactive user, hourly and after login | `%LOCALAPPDATA%\CodexMemoryConsolidation\logs\` |

To install memory maintenance independently, run `sh codex/setup-memory.sh` on
macOS/Linux or `.\codex\setup-memory.ps1` in Windows PowerShell. Linux requires a
working systemd user manager. User schedulers run within your login session;
Linux users who need operation after logout can configure systemd user lingering
separately. Windows tasks use the current user without storing a password or
requiring administrator privileges. Windows copies the runner; rerun setup to
refresh it after repo changes. Unix installs a symlink.

Existing runners and changed scheduler configuration are backed up under
`$CODEX_HOME/memory-maintenance/` before replacement. An already loaded macOS
LaunchAgent keeps its current settings until the next login. Authentication,
memory contents, database snapshots and logs stay outside the repo. The runner
targets the memory schema used by Codex 0.163.0 (`memories_1.sqlite`).

Run the regression tests with `python3 codex/test_memory_consolidate.py` (or
`python codex/test_memory_consolidate.py` on Windows). Tests use temporary memory
state and a local protocol test server; they do not submit memories to a model.

In zsh and PowerShell, bare `codex` opens the agents view with `codex agents`.
The shared configuration defaults to Approve for me: automatic approval review
with on-request approvals and the workspace-write sandbox.
Calls with arguments, including `codex resume` and `codex --help`, pass through
unchanged. Reload your shell after updating its profile.
