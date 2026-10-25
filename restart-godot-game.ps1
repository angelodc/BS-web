[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
	[ValidateRange(1, 120)]
	[int]$CloseTimeoutSeconds = 15,
	[ValidateRange(1, 60)]
	[int]$StartupCheckSeconds = 45
)

$ErrorActionPreference = "Stop"
$projectPath = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd("\")

function Get-ArgumentValue {
	param(
		[string]$CommandLine,
		[string]$Name
	)

	$pattern = "(?i)(?:^|\s)--$([regex]::Escape($Name))\s+(?:`"([^`"]+)`"|(\S+))"
	if ($CommandLine -match $pattern) {
		return $(if ($Matches[1]) { $Matches[1] } else { $Matches[2] })
	}

	return $null
}

function ConvertTo-NormalizedPath {
	param([string]$Path)

	if (-not $Path) {
		return $null
	}

	try {
		return [System.IO.Path]::GetFullPath($Path.Replace("/", "\")).TrimEnd("\")
	} catch {
		return $null
	}
}

$processes = @(Get-CimInstance Win32_Process)
$editors = @(
	$processes | Where-Object {
		$_.Name -like "Godot*.exe" -and
		$_.CommandLine -match "(?i)(?:^|\s)--editor(?:\s|$)" -and
		[string]::Equals(
			(ConvertTo-NormalizedPath (Get-ArgumentValue -CommandLine $_.CommandLine -Name "path")),
			$projectPath,
			[System.StringComparison]::OrdinalIgnoreCase
		)
	}
)

if ($editors.Count -ne 1) {
	throw "Esperava encontrar exatamente um editor Godot aberto para '$projectPath'; encontrei $($editors.Count). Nenhum processo foi encerrado."
}

$editor = $editors[0]
$games = @(
	$processes | Where-Object {
		$debugEditorPid = Get-ArgumentValue -CommandLine $_.CommandLine -Name "allow_focus_steal_pid"
		$remoteDebug = Get-ArgumentValue -CommandLine $_.CommandLine -Name "remote-debug"
		$gameProjectPath = ConvertTo-NormalizedPath (
			Get-ArgumentValue -CommandLine $_.CommandLine -Name "path"
		)

		$_.Name -eq $editor.Name -and
		$_.ProcessId -ne $editor.ProcessId -and
		$remoteDebug -and
		$debugEditorPid -eq [string]$editor.ProcessId -and
		[string]::Equals(
			$gameProjectPath,
			$projectPath,
			[System.StringComparison]::OrdinalIgnoreCase
		)
	}
)

if ($games.Count -ne 1) {
	throw "Esperava encontrar exatamente um jogo iniciado pelo F5 para este projeto e editor; encontrei $($games.Count). Nenhum processo foi encerrado."
}

$gameInfo = $games[0]
$remoteDebugAddress = Get-ArgumentValue -CommandLine $gameInfo.CommandLine -Name "remote-debug"
$position = Get-ArgumentValue -CommandLine $gameInfo.CommandLine -Name "position"
$action = "Fechar normalmente o jogo PID $($gameInfo.ProcessId) e reabri-lo pelo projeto '$projectPath'; manter o editor PID $($editor.ProcessId) aberto"
$logDirectory = Join-Path `
	([Environment]::GetFolderPath("LocalApplicationData")) `
	"Godot\BS-web\logs"
$logTimestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$stdoutLog = Join-Path $logDirectory "game-$logTimestamp-stdout.log"
$stderrLog = Join-Path $logDirectory "game-$logTimestamp-stderr.log"

if ($PSCmdlet.ShouldProcess($action, "Reiniciar jogo Godot")) {
	$game = Get-Process -Id $gameInfo.ProcessId -ErrorAction SilentlyContinue
	if (-not $game) {
		throw "O processo do jogo PID $($gameInfo.ProcessId) encerrou antes de ser reiniciado."
	}

	if (-not $game.CloseMainWindow()) {
		throw "Nao foi possivel solicitar o fechamento normal do jogo PID $($gameInfo.ProcessId). O editor continua aberto."
	}

	if (-not $game.WaitForExit($CloseTimeoutSeconds * 1000)) {
		throw "O jogo PID $($gameInfo.ProcessId) nao fechou normalmente em $CloseTimeoutSeconds segundos. Nao foi encerrado a forca; o editor continua aberto."
	}

	$arguments = @(
		"--path"
		"`"$projectPath`""
		"--remote-debug"
		"`"$remoteDebugAddress`""
		"--allow_focus_steal_pid"
		[string]$editor.ProcessId
	)
	if ($position) {
		$arguments += @("--position", "`"$position`"")
	}

	[void][System.IO.Directory]::CreateDirectory($logDirectory)
	$startedGame = Start-Process `
		-FilePath $editor.ExecutablePath `
		-ArgumentList $arguments `
		-WorkingDirectory $projectPath `
		-RedirectStandardOutput $stdoutLog `
		-RedirectStandardError $stderrLog `
		-PassThru

	$restartedGame = Get-CimInstance Win32_Process -Filter "ProcessId = $($startedGame.Id)" -ErrorAction SilentlyContinue
	if (-not $restartedGame) {
		throw "O jogo foi fechado, mas a nova execucao nao permaneceu aberta. Consulte os logs: '$stdoutLog' e '$stderrLog'."
	}

	Write-Host "Jogo reiniciado (PID anterior: $($gameInfo.ProcessId); novo PID: $($startedGame.Id)). O editor permanece aberto (PID: $($editor.ProcessId))."
	Write-Host "Verificando erros e avisos do arranque por $StartupCheckSeconds segundos..."
	Start-Sleep -Seconds $StartupCheckSeconds
	$findings = @()
	foreach ($logPath in @($stdoutLog, $stderrLog)) {
		if (-not (Test-Path $logPath)) {
			continue
		}

		foreach ($line in Get-Content $logPath) {
			if ($line -match "(?i)\b(ERROR|SCRIPT ERROR|WARNING):|^Warning:") {
				$findings += $line
			}
		}
	}

	if ($findings.Count -eq 0) {
		Write-Host "Tudo certo no arranque: nenhum ERROR, SCRIPT ERROR ou WARNING foi detectado."
	} else {
		$groupedFindings = @($findings | Group-Object)
		Write-Warning "Foram encontradas $($findings.Count) ocorrencias em $($groupedFindings.Count) tipos de erro/aviso:"
		foreach ($finding in $groupedFindings) {
			Write-Host ("{0}x {1}" -f $finding.Count, $finding.Name)
		}
	}
	Write-Host "Logs completos: '$stdoutLog' e '$stderrLog'."
}
