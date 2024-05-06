# $POSH_CONFIG=(Join-Path $HOME "oh-my-posh.json")

oh-my-posh init pwsh --config 'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/agnoster.omp.json' | Invoke-Expression

$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"

Import-Module posh-git
Import-Module PSReadLine
Import-Module Get-ChildItemColor
Import-Module Terminal-Icons

if (Test-Path($ChocolateyProfile)) {
  Import-Module "$ChocolateyProfile"
}

if (Test-Path alias:Curl) { 
  Remove-Item alias:Curl 
}

if (Test-Path alias:WGet) { 
  Remove-Item alias:WGet 
}

$PSDefaultParameterValues["Out-File:Encoding"] = "utf8"
Set-PSReadlineKeyHandler -Key Tab -Function Complete

function prompt
{
  $loc = Get-Location

  $prompt = & $GitPromptScriptBlock
  $prompt += "$([char]27)]9;12$([char]7)"

  # if ($loc.Provider.Name -eq "FileSystem")
  # {
  #   $prompt += "$([char]27)]9;9;`"$($loc.ProviderPath)`"$([char]27)\"
  # }

  $prompt
}
