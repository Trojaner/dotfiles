[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

if ([Environment]::GetCommandLineArgs().Contains("-NonInteractive")) {
  return
}

$env:POSH_GIT_ENABLED = $true

oh-my-posh init pwsh --config "$HOME\Documents\PowerShell\posh-theme.json" | Invoke-Expression

if (Test-Path alias:Curl) { 
  Remove-Item alias:Curl 
}

if (Test-Path alias:WGet) { 
  Remove-Item alias:WGet 
}

Import-Module -Name PSReadLine
Import-Module -Name posh-git
Import-Module -Name Get-ChildItemColor
Import-Module -Name Terminal-Icons
Import-Module -Name Microsoft.WinGet.Client
Import-Module -Name Microsoft.WinGet.CommandNotFound
Import-Module -Name CompletionPredictor

# # Invoke-Expression "$(direnv hook pwsh)"

Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
  param($wordToComplete, $commandAst, $cursorPosition)
  dotnet complete --position $cursorPosition "$commandAst" | ForEach-Object {
    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
  }
}

$PSDefaultParameterValues["Out-File:Encoding"] = "utf8"
$PSReadLineOptions = @{
  EditMode            = 'Windows'
  PredictionSource    = 'HistoryAndPlugin'
  PredictionViewStyle = 'ListView' 
  HistorySearchCursorMovesToEnd = $true
}

Set-PSReadLineOption @PSReadLineOptions

Set-PSReadLineKeyHandler -Chord 'Ctrl+LeftArrow' -Function BackwardWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+RightArrow' -Function ForwardWord
Set-PSReadLineKeyHandler -Chord 'Ctrl+z' -Function Undo
Set-PSReadLineKeyHandler -Chord 'Ctrl+y' -Function Redo
Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadlineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadlineKeyHandler -Key DownArrow -Function HistorySearchForward

if ($env:TERM_PROGRAM -eq "vscode") { 
  . "$(code-insiders --locate-shell-integration-path pwsh)"
} else { 
  fastfetch 
}