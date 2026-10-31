# Sends Ctrl+C to the console a process runs in, the Windows equivalent of
# `tmux send-keys C-c`. claude rc only stops cleanly (keeping its sessions
# resumable) on Ctrl+C, and Windows has no signal for it, so this attaches to
# the target's console and raises CTRL_C_EVENT there.
#
# Usage: powershell -NoProfile -File Send-CtrlC.ps1 -ProcessId <pid>
#
# Run it as its own powershell process: it frees and re-attaches the console of
# the process it runs in, which would detach an interactive shell.
param([Parameter(Mandatory)][int]$ProcessId)

Add-Type -Namespace ClaudeRc -Name Kernel32 -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool FreeConsole();
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool AttachConsole(uint dwProcessId);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleCtrlHandler(System.IntPtr handler, bool add);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GenerateConsoleCtrlEvent(uint dwCtrlEvent, uint dwProcessGroupId);
'@

[ClaudeRc.Kernel32]::FreeConsole() | Out-Null
if (-not [ClaudeRc.Kernel32]::AttachConsole([uint32]$ProcessId)) {
  Write-Error "AttachConsole($ProcessId) failed (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"
  exit 1
}
# Ignore the event in this process, then send it to every process on the console.
[ClaudeRc.Kernel32]::SetConsoleCtrlHandler([IntPtr]::Zero, $true) | Out-Null
$sent = [ClaudeRc.Kernel32]::GenerateConsoleCtrlEvent(0, 0)
Start-Sleep -Milliseconds 500
[ClaudeRc.Kernel32]::FreeConsole() | Out-Null
if (-not $sent) { exit 1 }
