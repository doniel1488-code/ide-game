param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$GodotArguments
)

$ErrorActionPreference = 'Stop'
$logDirectory = Join-Path $env:RUNNER_TEMP 'godot-diagnostics'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$stdoutPath = Join-Path $logDirectory "$Name.stdout.log"
$stderrPath = Join-Path $logDirectory "$Name.stderr.log"

Write-Host "Running Godot diagnostic '$Name': $($GodotArguments -join ' ')"
$process = Start-Process -FilePath $env:GODOT_EXE -ArgumentList $GodotArguments -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
Write-Host "Godot diagnostic '$Name' exit code: $($process.ExitCode)"
Write-Host "----- stdout: $Name -----"
if (Test-Path -LiteralPath $stdoutPath) { Get-Content -LiteralPath $stdoutPath | ForEach-Object { Write-Host $_ } }
Write-Host "----- stderr: $Name -----"
if (Test-Path -LiteralPath $stderrPath) { Get-Content -LiteralPath $stderrPath | ForEach-Object { Write-Host $_ } }

if ($process.ExitCode -ne 0) { exit $process.ExitCode }
