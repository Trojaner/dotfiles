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
