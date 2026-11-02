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

if (-not ("GodotWindowHelper" -as [type])) {
	Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class GodotWindowHelper {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, StringBuilder cls, int max);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int max);
}
"@
}

# Godot 4 roda o F5 embutido na janela do editor (--wid). Nesse caso o jogo
# nao tem MainWindowHandle, mas ainda tem uma janela propria, filha da janela
# do editor. Procura apenas janelas do PID do jogo: a janela do editor nunca
# e alvo.
function Find-ProcessWindow {
	param([uint32]$ProcessId)

	$script:searchPid = $ProcessId
	$script:foundWindow = [IntPtr]::Zero
	$script:foundEngine = $false
	$collect = [GodotWindowHelper+EnumProc]{
		param($hWnd, $lParam)
		$owner = [uint32]0
		[void][GodotWindowHelper]::GetWindowThreadProcessId($hWnd, [ref]$owner)
		if ($owner -eq $script:searchPid) {
			$cls = New-Object System.Text.StringBuilder 64
			[void][GodotWindowHelper]::GetClassName($hWnd, $cls, 64)
			if ($cls.ToString() -eq "Engine" -and -not $script:foundEngine) {
				$script:foundWindow = $hWnd
				$script:foundEngine = $true
			} elseif ($script:foundWindow -eq [IntPtr]::Zero `
					-and [GodotWindowHelper]::IsWindowVisible($hWnd)) {
				$script:foundWindow = $hWnd
			}
		}
		return $true
	}
	[void][GodotWindowHelper]::EnumWindows($collect, [IntPtr]::Zero)
	if ($script:foundWindow -eq [IntPtr]::Zero) {
		$top = [GodotWindowHelper+EnumProc]{
			param($hWnd, $lParam)
			[void][GodotWindowHelper]::EnumChildWindows($hWnd, $collect, [IntPtr]::Zero)
			return $true
		}
		[void][GodotWindowHelper]::EnumWindows($top, [IntPtr]::Zero)
	}
	return $script:foundWindow
}

# Janela principal do editor: a visivel cujo titulo traz "Godot Engine".
# As janelas auxiliares do jogo embutido nao trazem esse titulo.
function Find-EditorMainWindow {
	param([uint32]$ProcessId)

	$script:editorWindow = [IntPtr]::Zero
	$script:editorFallback = [IntPtr]::Zero
	$collect = [GodotWindowHelper+EnumProc]{
		param($hWnd, $lParam)
		$owner = [uint32]0
		[void][GodotWindowHelper]::GetWindowThreadProcessId($hWnd, [ref]$owner)
		if ($owner -eq $script:searchPid `
				-and [GodotWindowHelper]::IsWindowVisible($hWnd)) {
			$title = New-Object System.Text.StringBuilder 512
			[void][GodotWindowHelper]::GetWindowText($hWnd, $title, 512)
			$text = $title.ToString()
			if ($script:editorFallback -eq [IntPtr]::Zero -and $text) {
				$script:editorFallback = $hWnd
			}
			if ($text -match "(?i)Godot Engine") {
				$script:editorWindow = $hWnd
			}
		}
		return $true
	}
	$script:searchPid = $ProcessId
	[void][GodotWindowHelper]::EnumWindows($collect, [IntPtr]::Zero)
	if ($script:editorWindow -ne [IntPtr]::Zero) {
		return $script:editorWindow
	}
	return $script:editorFallback
}

# F8 e o atalho de Stop do editor. O jogo embutido ignora WM_CLOSE, entao
# quem o encerra e o proprio editor, exatamente como o botao Stop.
function Send-EditorStopShortcut {
	param([IntPtr]$EditorWindow)

	$down = [GodotWindowHelper]::PostMessage(
			$EditorWindow, 0x0100, [IntPtr]0x77, [IntPtr]0x00420001)
	$up = [GodotWindowHelper]::PostMessage(
			$EditorWindow, 0x0101, [IntPtr]0x77, [IntPtr]0xC0420001)
	return ($down -and $up)
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
		if (-not $debugEditorPid) {
			# Godot 4 launches the F5 game with --editor-pid instead of the
			# Godot 3 flag --allow_focus_steal_pid.
			$debugEditorPid = Get-ArgumentValue -CommandLine $_.CommandLine -Name "editor-pid"
		}
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

if ($games.Count -gt 1) {
	throw "Esperava no maximo um jogo iniciado pelo F5 para este projeto e editor; encontrei $($games.Count). Nenhum processo foi encerrado."
}

$gameInfo = $null
$remoteDebugAddress = $null
$position = $null
$scene = $null
$resolution = $null
if ($games.Count -eq 1) {
	$gameInfo = $games[0]
	$remoteDebugAddress = Get-ArgumentValue -CommandLine $gameInfo.CommandLine -Name "remote-debug"
	$position = Get-ArgumentValue -CommandLine $gameInfo.CommandLine -Name "position"
	$scene = Get-ArgumentValue -CommandLine $gameInfo.CommandLine -Name "scene"
	$resolution = Get-ArgumentValue -CommandLine $gameInfo.CommandLine -Name "resolution"
}
if (-not $remoteDebugAddress) {
	# Sem jogo em execucao nao ha argumentos para copiar; usa a porta padrao
	# do depurador remoto do editor para a nova execucao continuar conectada.
	$remoteDebugAddress = "tcp://127.0.0.1:6007"
}
$action = if ($gameInfo) {
	"Fechar normalmente o jogo PID $($gameInfo.ProcessId) e reabri-lo pelo projeto '$projectPath'; manter o editor PID $($editor.ProcessId) aberto"
} else {
	"Abrir o jogo pelo projeto '$projectPath' (nenhuma execucao F5 encontrada); manter o editor PID $($editor.ProcessId) aberto"
}
$logDirectory = Join-Path `
	([Environment]::GetFolderPath("LocalApplicationData")) `
	"Godot\BS-web\logs"
$logTimestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$stdoutLog = Join-Path $logDirectory "game-$logTimestamp-stdout.log"
$stderrLog = Join-Path $logDirectory "game-$logTimestamp-stderr.log"

if ($PSCmdlet.ShouldProcess($action, "Reiniciar jogo Godot")) {
	if ($gameInfo) {
		$game = Get-Process -Id $gameInfo.ProcessId -ErrorAction SilentlyContinue
		if (-not $game) {
			throw "O processo do jogo PID $($gameInfo.ProcessId) encerrou antes de ser reiniciado."
		}

		$closeRequested = $false
		if ($game.MainWindowHandle -ne [IntPtr]::Zero) {
			$closeRequested = $game.CloseMainWindow()
		}
		if (-not $closeRequested) {
			$gameWindow = Find-ProcessWindow -ProcessId ([uint32]$gameInfo.ProcessId)
			if ($gameWindow -eq [IntPtr]::Zero) {
				throw "Nao encontrei a janela do jogo PID $($gameInfo.ProcessId) para pedir o fechamento normal. O editor continua aberto."
			}
			$gameParent = [GodotWindowHelper]::GetParent($gameWindow)
			if ($gameParent -ne [IntPtr]::Zero) {
				# F5 embutido: a janela do jogo e filha de uma janela do
				# editor e ignora WM_CLOSE. O Stop do editor (F8) encerra a
				# execucao, sem fechar o editor.
				$editorWindow = Find-EditorMainWindow -ProcessId ([uint32]$editor.ProcessId)
				if ($editorWindow -ne [IntPtr]::Zero) {
					$closeRequested = Send-EditorStopShortcut -EditorWindow $editorWindow
				}
			} else {
				# Janela propria do jogo: WM_CLOSE vai apenas para ela.
				$closeRequested = [GodotWindowHelper]::PostMessage(
						$gameWindow, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
			}
		}
		if (-not $closeRequested) {
			throw "Nao foi possivel solicitar o fechamento normal do jogo PID $($gameInfo.ProcessId). O editor continua aberto."
		}

		if (-not $game.WaitForExit($CloseTimeoutSeconds * 1000)) {
			throw "O jogo PID $($gameInfo.ProcessId) nao fechou normalmente em $CloseTimeoutSeconds segundos. Nao foi encerrado a forca; o editor continua aberto."
		}
	}

	$arguments = @(
		"--path"
		"`"$projectPath`""
	)
	# O editor so aceita o depurador remoto enquanto tem uma execucao viva.
	# Ao abrirmos o jogo por conta propria a porta 6007 esta fechada, e passar
	# os argumentos so produziria um erro de conexao no arranque.
	$debugPortOpen = @(
		Get-NetTCPConnection -OwningProcess $editor.ProcessId -State Listen `
			-ErrorAction SilentlyContinue |
			Where-Object { $_.LocalPort -eq 6007 }
	).Count -gt 0
	if ($debugPortOpen -and $remoteDebugAddress) {
		$arguments += @(
			"--remote-debug"
			"`"$remoteDebugAddress`""
			"--editor-pid"
			[string]$editor.ProcessId
		)
	}
	if ($scene) {
		$arguments += @("--scene", "`"$scene`"")
	}
	if ($position) {
		$arguments += @("--position", "`"$position`"")
	}
	if ($resolution) {
		$arguments += @("--resolution", "`"$resolution`"")
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

	if ($gameInfo) {
		Write-Host "Jogo reiniciado (PID anterior: $($gameInfo.ProcessId); novo PID: $($startedGame.Id)). O editor permanece aberto (PID: $($editor.ProcessId))."
	} else {
		Write-Host "Jogo aberto (novo PID: $($startedGame.Id)). O editor permanece aberto (PID: $($editor.ProcessId))."
	}
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
