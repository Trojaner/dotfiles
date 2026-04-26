# Claude Code statusLine command
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$rawInput = [Console]::In.ReadToEnd()
$data = $rawInput | ConvertFrom-Json

# --- ANSI colors (light theme) ---
$E = [char]27
$RST = "$E[0m"
$BOLD = "$E[1m"
$GREEN = "$E[32m"
$YELLOW = "$E[33m"
$LGREEN = "$E[92m"
$LRED = "$E[91m"
$LGREEN_BG = "$E[48;5;157;30m"
$LRED_BG = "$E[48;5;217;30m"
$YELLOW_BG = "$E[48;5;229;30m"
$GREY_BG = "$E[48;5;252;30m"
$BLUE_BG = "$E[48;5;153;34m"
$RED_BG_USAGE = "$E[48;5;217;31m"
$LABEL_BG = "$E[48;5;240;97m"
$GREY = "$E[38;5;242m"
$CYAN_BG = "$E[48;5;159;30m"
$DIM_BG = "$E[48;5;238;37m"

# --- Parse JSON ---
$cwd = if ($data.cwd) { $data.cwd } elseif ($data.workspace -and $data.workspace.current_dir) { $data.workspace.current_dir } else { '' }
$model = if ($data.model -and $data.model.display_name) { $data.model.display_name } else { '' }
$usedPct = if ($null -ne $data.context_window -and $null -ne $data.context_window.used_percentage) { $data.context_window.used_percentage } else { 0 }
$cost = if ($null -ne $data.cost -and $null -ne $data.cost.total_cost_usd) { $data.cost.total_cost_usd } else { $null }
$linesAdd = if ($null -ne $data.cost -and $data.cost.total_lines_added) { $data.cost.total_lines_added } else { 0 }
$linesDel = if ($null -ne $data.cost -and $data.cost.total_lines_removed) { $data.cost.total_lines_removed } else { 0 }
$rate5h = if ($null -ne $data.rate_limits -and $null -ne $data.rate_limits.five_hour) { $data.rate_limits.five_hour.used_percentage } else { 0 }
$rate7d = if ($null -ne $data.rate_limits -and $null -ne $data.rate_limits.seven_day) { $data.rate_limits.seven_day.used_percentage } else { 0 }
$reset5h = if ($null -ne $data.rate_limits -and $null -ne $data.rate_limits.five_hour) { $data.rate_limits.five_hour.resets_at } else { 0 }
$reset7d = if ($null -ne $data.rate_limits -and $null -ne $data.rate_limits.seven_day) { $data.rate_limits.seven_day.resets_at } else { 0 }
$thinkingEnabled = if ($null -ne $data.thinking -and $data.thinking.enabled -eq $true) { $true } else { $false }
$effortLevel = if ($null -ne $data.effort -and $data.effort.level) { $data.effort.level } else { $null }

# --- Context bg color by percentage ---
function Get-CtxBgColor($pct) {
    if ($pct -ge 85) { $LRED_BG }
    elseif ($pct -ge 65) { $YELLOW_BG }
    else { $GREY_BG }
}

# --- Usage bar bg color ---
function Get-UsageBg($pct) {
    if ($pct -ge 70) { $RED_BG_USAGE }
    else { $BLUE_BG }
}

# --- Git (best-effort, no timeout on Windows) ---
$gitIndicator = "${GREEN}✔${RST}"
$gitBranch = '—'
$gitExtra = ''
$gitFiles = ''

try {
    $isGit = & git -C $cwd rev-parse --is-inside-work-tree 2>$null
    if ($isGit -eq 'true') {
        $branch = & git -C $cwd --no-optional-locks symbolic-ref --short HEAD 2>$null
        if ($branch) {
            $gitBranch = $branch
            $dirty = $false

            & git -C $cwd --no-optional-locks diff --quiet 2>$null
            $diffDirty = $LASTEXITCODE -ne 0
            & git -C $cwd --no-optional-locks diff --cached --quiet 2>$null
            $cachedDirty = $LASTEXITCODE -ne 0

            if ($diffDirty -or $cachedDirty) {
                $gitIndicator = "${YELLOW}!${RST}"
                $dirty = $true
            }

            $upstream = & git -C $cwd --no-optional-locks rev-parse --abbrev-ref '@{u}' 2>$null
            if ($upstream) {
                $ab = & git -C $cwd --no-optional-locks rev-list --left-right --count 'HEAD...@{u}' 2>$null
                if ($ab) {
                    $parts = $ab -split '\s+'
                    $ahead = [int]$parts[0]
                    $behind = [int]$parts[1]
                    if ($ahead -gt 0) { $gitExtra += " ↑$ahead" }
                    if ($behind -gt 0) { $gitExtra += " ↓$behind" }
                }
            }

            if ($dirty) {
                $stats = & git -C $cwd --no-optional-locks diff --name-status HEAD 2>$null
                $untracked = & git -C $cwd --no-optional-locks ls-files --others --exclude-standard 2>$null

                $nNew = if ($untracked) { @($untracked).Count } else { 0 }
                $nMod = if ($stats) { @($stats | Where-Object { $_ -match '^M' }).Count } else { 0 }
                $nDel = if ($stats) { @($stats | Where-Object { $_ -match '^D' }).Count } else { 0 }
                $stagedNew = & git -C $cwd --no-optional-locks diff --cached --name-status 2>$null
                if ($stagedNew) { $nNew += @($stagedNew | Where-Object { $_ -match '^A' }).Count }

                $fileParts = @()
                if ($nNew -gt 0) { $fileParts += "${LGREEN}+${nNew}${RST}" }
                if ($nMod -gt 0) { $fileParts += "${YELLOW}~${nMod}${RST}" }
                if ($nDel -gt 0) { $fileParts += "${LRED}-${nDel}${RST}" }
                if ($fileParts.Count -gt 0) { $gitFiles = ' ' + ($fileParts -join ' ') }
            }
        }
    }
} catch {}

# --- Progress bar with % overlaid at the end ---
function Get-RawBar($pct, $w = 20) {
    $label = " ${pct}% "
    $labelLen = $label.Length
    $filled = [math]::Floor($pct * $w / 100)
    $barBefore = $w - $labelLen
    $bar = ''
    for ($i = 0; $i -lt $barBefore; $i++) {
        if ($i -lt $filled) { $bar += '█' } else { $bar += '▁' }
    }
    return "${bar}${label}"
}

# --- Time left ---
function Get-TimeLeft($ts) {
    if ($ts -eq 0) { return '--' }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $d = $ts - $now
    if ($d -le 0) { return 'now' }
    elseif ($d -lt 3600) { return "$([math]::Floor($d / 60))m" }
    elseif ($d -lt 86400) { return "$([math]::Floor($d / 3600))h$([math]::Floor(($d % 3600) / 60))m" }
    else { return "$([math]::Floor($d / 86400))d$([math]::Floor(($d % 86400) / 3600))h" }
}

# --- Computed values ---
$ctxInt = [math]::Round($usedPct)
$r5 = [math]::Round($rate5h)
$r7 = [math]::Round($rate7d)
$costFmt = if ($null -ne $cost) { '$' + ('{0:F2}' -f [double]$cost) } else { '—' }
$ctxBg = Get-CtxBgColor $ctxInt
$bg5h = Get-UsageBg $r5
$bg7d = Get-UsageBg $r7
$cwdBase = Split-Path $cwd -Leaf

# --- Thinking segment ---
function Get-ThinkValueBg($level) {
    switch ($level) {
        'off'    { return "$E[48;5;240;37m" }   # grey/dim
        'low'    { return "$E[48;5;34;97m"   }   # green
        'medium' { return "$E[48;5;38;97m"   }   # cyan/blue
        'high'   { return "$E[48;5;220;30m"  }   # yellow
        'xhigh'  { return "$E[48;5;129;97m"  }   # magenta
        'max'    { return "$E[48;5;196;97m"  }   # red
        default  { return "$E[48;5;159;30m"  }   # cyan (on/fallback)
    }
}

if ($thinkingEnabled) {
    $valueText = if ($effortLevel) { $effortLevel } else { 'on' }
    $valueBg   = Get-ThinkValueBg $valueText
    $thinkingSegment = "${BOLD}think:${RST} ${valueBg} ${valueText} ${RST}"
} else {
    $valueBg = Get-ThinkValueBg 'off'
    $thinkingSegment = "${BOLD}think:${RST} ${valueBg} off ${RST}"
}

# --- Output ---
$ttl5h = Get-TimeLeft $reset5h
$ttl7d = Get-TimeLeft $reset7d
$bar5h = Get-RawBar $r5 20
$bar7d = Get-RawBar $r7 20

[Console]::Out.WriteLine("${BOLD}workspace:${RST} ${BOLD}$E[0;32m${cwdBase}${RST} · ${BOLD}model:${RST} ${model} · ${thinkingSegment} · ${BOLD}git:${RST} ${gitBranch} ${gitIndicator}${gitExtra}${gitFiles} · ${BOLD}context:${RST} ${ctxBg} ${ctxInt}% ${RST} · ${LGREEN_BG} +${linesAdd} ${RST} ${LRED_BG} -${linesDel} ${RST} · ${BOLD}cost:${RST} ${costFmt}")
[Console]::Out.WriteLine("${BOLD}usage:${RST} ${LABEL_BG} 5h [${ttl5h}] ${RST}${bg5h}${bar5h}${RST} | ${LABEL_BG} 7d [${ttl7d}] ${RST}${bg7d}${bar7d}${RST}")
[Console]::Out.Write("${GREY}    Alt+P model  Alt+T think  Alt+O fast  Shift+Tab mode${RST}")
