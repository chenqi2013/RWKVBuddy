[CmdletBinding()]
param([string]$NodePath = '', [string]$LuaPath = '')
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskRuntime = Join-Path $taskRoot 'agent-service/runtime'
if (-not $NodePath) { $NodePath = (Get-Command node -ErrorAction Stop).Source }
if (-not $LuaPath) { $LuaPath = (Get-Command lua -ErrorAction Stop).Source }
$taskDll = Join-Path (Split-Path $LuaPath -Parent) 'lua54.dll'
if (-not (Test-Path -LiteralPath $taskDll)) { throw 'lua54.dll must be beside lua.exe. Use Lua 5.4.' }
$taskVersion = & $NodePath --version
if ([int]($taskVersion.TrimStart('v').Split('.')[0]) -lt 20) { throw 'Node.js 20.11+ is required.' }
New-Item -ItemType Directory -Path $taskRuntime -Force | Out-Null
Copy-Item -LiteralPath $NodePath -Destination (Join-Path $taskRuntime 'node.exe') -Force
Copy-Item -LiteralPath $LuaPath -Destination (Join-Path $taskRuntime 'lua.exe') -Force
Copy-Item -LiteralPath $taskDll -Destination (Join-Path $taskRuntime 'lua54.dll') -Force
Write-Host "Runtime prepared: $taskRuntime"
Write-Host 'Run flutter build windows --release; distribute the entire Release directory.'
