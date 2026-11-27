<#
Runs every MobileCaret test.

Layout: this repository folder sits inside a Godot project used for
development, so the addon is at res://<repo folder>/addons/MobileCaret. The script creates that outer
project when it is missing, imports it, checks that every script compiles under the strict warnings
(an untyped or inferred variable is an error), and runs the test scenes in a window (handles,
dragging and the toolbar need one).

A suite passes only with "0 failures" and no script error: a script that does not compile never
runs its checks, so its suite could otherwise still say "0 failures".

  .\run_tests.ps1                   every suite
  .\run_tests.ps1 -Suite toolbar    one suite: scripts, custom, toolbar, carets, multicaret, bidi,
                                    setups, viewports, focus, keyboard

Godot: -Godot <path> or the GODOT environment variable; defaults to the 4.7.2 build next to the
projects folder.
#>
param(
	[string]$Suite = "all",
	[string]$Godot = $env:GODOT,
	[int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"
$Repo = $PSScriptRoot
$Project = Split-Path $Repo -Parent
$RepoName = Split-Path $Repo -Leaf

if (-not $Godot) {
	$Godot = Join-Path (Split-Path $Project -Parent) "Godot/Godot_v4.7.2-stable_mono_win64_console.exe"
}
if (-not (Test-Path $Godot)) {
	throw "Godot not found at '$Godot'. Pass -Godot <path> or set the GODOT environment variable."
}

function Write-Step([string]$Text) {
	Write-Host ""
	Write-Host "=== $Text" -ForegroundColor Cyan
}

# Runs Godot (stopped after $TimeoutSeconds), returns @{ Code; Text; TimedOut }.
function Invoke-Godot([string[]]$Arguments) {
	$out = [System.IO.Path]::GetTempFileName()
	$err = [System.IO.Path]::GetTempFileName()
	$quoted = $Arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
	$process = Start-Process -FilePath $Godot -ArgumentList $quoted -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
	# read the handle now: without it PowerShell reports no exit code after WaitForExit
	$null = $process.Handle
	$timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
	if ($timedOut) { $process.Kill() }
	$text = (Get-Content $out -Raw) + (Get-Content $err -Raw)
	Remove-Item $out, $err -ErrorAction SilentlyContinue
	return @{ Code = $process.ExitCode; Text = "$text"; TimedOut = $timedOut }
}

$Addon = "res://$RepoName/addons/MobileCaret"

# 1. The outer development project.
if (-not (Test-Path (Join-Path $Project "project.godot"))) {
	Write-Step "Creating the development project at $Project"
	@"
; Development project for MobileCaret. Not part of the git repo (the repo is the $RepoName/ folder
; inside this one). $RepoName/run_tests.ps1 recreates this file when it is missing.

config_version=5

[application]

config/name="MobileCaret Dev"
config/features=PackedStringArray("4.7", "Forward Plus")

[autoload]

MobileCaret="*$Addon/CaretsController/carets_controller.tscn"
MobileCaretToolbar="*$Addon/Toolbar/caret_toolbar.tscn"

[debug]

gdscript/warnings/untyped_declaration=2
gdscript/warnings/inferred_declaration=2

[display]

window/size/viewport_width=720
window/size/viewport_height=1280
window/size/window_width_override=450
window/size/window_height_override=800
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[editor_plugins]

enabled=PackedStringArray("$Addon/plugin.cfg")
"@ | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $Project "project.godot"), $_, [System.Text.UTF8Encoding]::new($false)) }
}

$Results = [System.Collections.Generic.List[object]]::new()
$AllPassed = $true

function Add-Result([string]$Name, [bool]$Passed, [string]$Detail) {
	$script:Results.Add([pscustomobject]@{ Suite = $Name; Result = $(if ($Passed) { "PASS" } else { "FAIL" }); Detail = $Detail })
	if (-not $Passed) { $script:AllPassed = $false }
}

# 2. Import (builds the class cache so class_name types resolve).
Write-Step "Importing the development project"
$import = Invoke-Godot @("--headless", "--path", $Project, "--import")
if ($import.Code -ne 0) {
	# the first import after a change sometimes crashes; the second one completes
	$import = Invoke-Godot @("--headless", "--path", $Project, "--import")
}

# 3. Every script must compile under the strict warnings.
if ($Suite -eq "all" -or $Suite -eq "scripts") {
	Write-Step "Checking every script"
	$bad = @()
	$scripts = Get-ChildItem $Repo -Recurse -Filter *.gd
	foreach ($file in $scripts) {
		$relative = $file.FullName.Substring($Project.Length + 1).Replace("\", "/")
		$check = Invoke-Godot @("--headless", "--path", $Project, "--check-only", "--script", "res://$relative")
		if ($check.Code -ne 0 -or $check.Text -match "SCRIPT ERROR|Parse Error|Failed to load") {
			$bad += $relative
			Write-Host $check.Text
		}
	}
	Add-Result "scripts" ($bad.Count -eq 0) "$($scripts.Count) scripts, $($bad.Count) with errors $($bad -join ', ')"
}

# 4. Test scenes (in a window).
$scenes = @("custom", "toolbar", "carets", "multicaret", "bidi", "setups", "viewports", "focus", "keyboard")
foreach ($name in $scenes) {
	if ($Suite -ne "all" -and $Suite -ne $name) { continue }
	Write-Step "Suite: $name"
	$run = Invoke-Godot @("--path", $Project, "res://$RepoName/tests/test_$name.tscn")
	$lines = $run.Text -split "`r?`n"
	$errors = @($lines | Where-Object { $_ -match "SCRIPT ERROR|Parse Error" })
	foreach ($line in $lines) {
		if ($line -match "FAIL|SCRIPT ERROR|Parse Error") { Write-Host $line -ForegroundColor Red }
	}
	$summary = $lines | Where-Object { $_ -match "\d+ checks, \d+ failures" } | Select-Object -Last 1
	if ($run.TimedOut) {
		Add-Result $name $false "stopped after $TimeoutSeconds s"
		continue
	}
	if (-not $summary) {
		Write-Host $run.Text
		Add-Result $name $false "no summary line (crashed?)"
		continue
	}
	$checks = [regex]::Match($summary, "(\d+) checks, (\d+) failures")
	$passed = ($checks.Groups[2].Value -eq "0") -and ($errors.Count -eq 0)
	Add-Result $name $passed "$($checks.Groups[1].Value) checks, $($checks.Groups[2].Value) failures, $($errors.Count) script errors"
}

Write-Host ""
foreach ($r in $Results) {
	$color = if ($r.Result -eq "PASS") { "Green" } else { "Red" }
	Write-Host ("{0,-12} {1,-6} {2}" -f $r.Suite, $r.Result, $r.Detail) -ForegroundColor $color
}
Write-Host ""
if ($AllPassed) {
	Write-Host "All suites passed." -ForegroundColor Green
	exit 0
}
Write-Host "Some suites failed." -ForegroundColor Red
exit 1
