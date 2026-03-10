# oh-my-cursor Windows installer (PowerShell)
# Mirrors install.sh: installs agents, rules, commands, hooks, skills to Cursor config directory.
# Run from repo root: .\install.ps1 [OPTIONS]
# If execution is restricted: powershell -ExecutionPolicy Bypass -File install.ps1 [OPTIONS]
# User scope: $env:USERPROFILE\.cursor

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2

$VERSION = "0.2.0"
$CURSOR_MODE_LABEL = "Team Avatar (Cursor 2.5+)"

$AGENT_FILES = @(
  "aang.md", "sokka.md", "katara.md", "zuko.md", "toph.md", "appa.md", "momo.md", "iroh.md"
)
$PROTOCOL_FILES = @("protocols/team-avatar.md")
$COMMAND_FILES = @(
  "plan.md", "build.md", "search.md", "fix.md", "tasks.md", "scout.md", "cactus-juice.md", "doc.md"
)
$HOOK_FILES = @("post-edit-lint.sh", "pre-commit-check.sh")
$RULE_FILE = "orchestrator.mdc"
$SKILL_DIRS = @(
  "architect", "codebase-search", "create-an-asset", "debugging", "design-patterns-implementation",
  "docs-write", "documentation-engineer", "documentation-writing", "exploring-codebases",
  "frontend-builder", "implementing-figma-designs", "mgrep-code-search", "planning",
  "refactoring", "refactoring-patterns", "technical-roadmap-planning",
  "vercel-composition-patterns", "vercel-react-best-practices", "web-design-guidelines"
)
$LEGACY_AGENT_FILES = @(
  "atlas.md", "explore.md", "generalPurpose.md", "hephaestus.md", "librarian.md", "metis.md",
  "momus.md", "multimodal-looker.md", "oracle.md", "prometheus.md", "sisyphus.md"
)
$LEGACY_PROTOCOL_FILES = @("protocols/swarm-coordinator.md")

$SCRIPT:FORCE = $false
$SCRIPT:DRY_RUN = $false
$SCRIPT:VERBOSE = $false
$SCRIPT:SCOPE = "user"
$SCRIPT:UNINSTALL = $false
$SCRIPT:DISABLE = $false
$SCRIPT:ENABLE = $false
$SCRIPT:ALSO_CLAUDE = $false
$SCRIPT:ALSO_CODEX = $false
$SCRIPT:WITH_SKILLS = $true
$SCRIPT:WORK_DIR = $null
$SOURCE_BASE_URL = if ($env:OH_MY_CURSOR_SOURCE_BASE_URL) { $env:OH_MY_CURSOR_SOURCE_BASE_URL } else { "https://raw.githubusercontent.com/tmcfarlane/oh-my-cursor/main" }

function Log { param([string]$Message) Write-Host $Message }
function LogVerbose { param([string]$Message) if ($SCRIPT:VERBOSE) { Write-Host $Message -ForegroundColor DarkGray } }
function Get-ScriptDir {
  if ($PSScriptRoot) { return $PSScriptRoot }
  if ($MyInvocation.ScriptName) { return Split-Path -Parent $MyInvocation.ScriptName }
  return $null
}

function Show-Usage {
  @"

oh-my-cursor installer v$VERSION
$CURSOR_MODE_LABEL

Install Team Avatar agent configurations for Cursor.

USAGE
  .\install.ps1 [OPTIONS]
  powershell -ExecutionPolicy Bypass -File install.ps1 [OPTIONS]

OPTIONS
  --user          Install to user scope (`$env:USERPROFILE\.cursor\) [default]
  --project       Install to project scope (.\\.cursor\)
  --claude        Also install to .claude\agents\ for Claude Code compatibility
  --codex         Also install to .codex\agents\ for Codex compatibility
  --no-skills     Skip installing bundled agent skills
  -f, --force     Overwrite existing files
  -n, --dry-run   Show what would be done without making changes
  -v, --verbose   Enable verbose output
  --uninstall     Remove installed agent and rule files
  --disable       Disable orchestration (rename rule so Cursor stops applying it)
  --enable        Re-enable orchestration (rename rule back)
  -h, --help      Show this help message
  --version       Print version

EXAMPLES
  .\install.ps1
  .\install.ps1 --project
  .\install.ps1 -Force
  .\install.ps1 -DryRun
  .\install.ps1 --uninstall
  .\install.ps1 --disable
  .\install.ps1 --enable

"@
}

function Parse-Args {
  param([string[]]$Args)
  $i = 0
  while ($i -lt $Args.Count) {
    switch ($Args[$i]) {
      { $_ -in "-f", "--force" }    { $SCRIPT:FORCE = $true }
      { $_ -in "-n", "--dry-run" }  { $SCRIPT:DRY_RUN = $true }
      { $_ -in "-v", "--verbose" }  { $SCRIPT:VERBOSE = $true }
      "--user"     { $SCRIPT:SCOPE = "user" }
      "--project"  { $SCRIPT:SCOPE = "project" }
      "--claude"   { $SCRIPT:ALSO_CLAUDE = $true }
      "--codex"    { $SCRIPT:ALSO_CODEX = $true }
      "--with-skills" { $SCRIPT:WITH_SKILLS = $true }
      "--no-skills"   { $SCRIPT:WITH_SKILLS = $false }
      "--uninstall"   { $SCRIPT:UNINSTALL = $true }
      "--disable"    { $SCRIPT:DISABLE = $true }
      "--enable"     { $SCRIPT:ENABLE = $true }
      { $_ -in "-h", "--help" } {
        Show-Usage; exit 0
      }
      "--version" {
        Write-Host $VERSION; exit 0
      }
      default {
        Write-Host "Unknown option: $($Args[$i])" -ForegroundColor Red
        Show-Usage; exit 1
      }
    }
    $i++
  }
}

function Resolve-Dirs {
  if ($SCRIPT:SCOPE -eq "user") {
    $SCRIPT:CURSOR_DIR = Join-Path $env:USERPROFILE ".cursor"
  } else {
    $SCRIPT:CURSOR_DIR = Join-Path (Get-Location) ".cursor"
  }
  $SCRIPT:AGENTS_DIR   = Join-Path $SCRIPT:CURSOR_DIR "agents"
  $SCRIPT:RULES_DIR    = Join-Path $SCRIPT:CURSOR_DIR "rules"
  $SCRIPT:COMMANDS_DIR = Join-Path $SCRIPT:CURSOR_DIR "commands"
  $SCRIPT:HOOKS_DIR    = Join-Path $SCRIPT:CURSOR_DIR "hooks"
  $SCRIPT:SKILLS_DIR   = Join-Path $SCRIPT:CURSOR_DIR "skills"
}

function Copy-SourcesFromLocalRepo {
  param([string]$OutDir)
  $scriptDir = Get-ScriptDir
  if (-not $scriptDir) { return $false }
  $agentsPath = Join-Path $scriptDir "agents"
  $rulesPath  = Join-Path $scriptDir "rules"
  if (-not (Test-Path $agentsPath -PathType Container) -or -not (Test-Path $rulesPath -PathType Container)) {
    return $false
  }
  $null = New-Item -ItemType Directory -Path $OutDir -Force
  foreach ($f in $AGENT_FILES) {
    $src = Join-Path $agentsPath $f
    if (Test-Path $src) { Copy-Item -Path $src -Destination (Join-Path $OutDir $f) -Force }
  }
  foreach ($f in $PROTOCOL_FILES) {
    $destSub = Join-Path $OutDir (Split-Path $f -Parent)
    $null = New-Item -ItemType Directory -Path $destSub -Force
    $src = Join-Path $agentsPath $f
    if (Test-Path $src) { Copy-Item -Path $src -Destination (Join-Path $OutDir $f) -Force }
  }
  $ruleSrc = Join-Path $rulesPath $RULE_FILE
  if (Test-Path $ruleSrc) { Copy-Item -Path $ruleSrc -Destination (Join-Path $OutDir $RULE_FILE) -Force }
  $cmdDir = Join-Path $scriptDir "commands"
  if (Test-Path $cmdDir -PathType Container) {
    $cmdOut = Join-Path $OutDir "commands"
    $null = New-Item -ItemType Directory -Path $cmdOut -Force
    foreach ($f in $COMMAND_FILES) {
      $src = Join-Path $cmdDir $f
      if (Test-Path $src) { Copy-Item -Path $src -Destination (Join-Path $cmdOut $f) -Force }
    }
  }
  $hooksDir = Join-Path $scriptDir "hooks"
  if (Test-Path $hooksDir -PathType Container) {
    $hooksOut = Join-Path $OutDir "hooks"
    $null = New-Item -ItemType Directory -Path $hooksOut -Force
    foreach ($f in $HOOK_FILES) {
      $src = Join-Path $hooksDir $f
      if (Test-Path $src) { Copy-Item -Path $src -Destination (Join-Path $hooksOut $f) -Force }
    }
  }
  $skillsDir = Join-Path $scriptDir "skills"
  if (Test-Path $skillsDir -PathType Container) {
    $skillsOut = Join-Path $OutDir "skills"
    Copy-Item -Path $skillsDir -Destination $skillsOut -Recurse -Force
  }
  return $true
}

function Get-SourcesFromGitHub {
  param([string]$OutDir)
  $base = $SCRIPT:SOURCE_BASE_URL
  $null = New-Item -ItemType Directory -Path $OutDir -Force
  try {
    foreach ($f in $AGENT_FILES) {
      $url = "$base/agents/$f"
      $dest = Join-Path $OutDir $f
      Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $dest
    }
    foreach ($f in $PROTOCOL_FILES) {
      $destSub = Join-Path $OutDir (Split-Path $f -Parent)
      $null = New-Item -ItemType Directory -Path $destSub -Force
      $url = "$base/agents/$f"
      $dest = Join-Path $OutDir $f
      Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $dest
    }
    $url = "$base/rules/$RULE_FILE"
    Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile (Join-Path $OutDir $RULE_FILE)
    $cmdOut = Join-Path $OutDir "commands"
    $null = New-Item -ItemType Directory -Path $cmdOut -Force
    foreach ($f in $COMMAND_FILES) {
      $url = "$base/commands/$f"
      Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile (Join-Path $cmdOut $f)
    }
    $hooksOut = Join-Path $OutDir "hooks"
    $null = New-Item -ItemType Directory -Path $hooksOut -Force
    foreach ($f in $HOOK_FILES) {
      $url = "$base/hooks/$f"
      Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile (Join-Path $hooksOut $f)
    }
    $manifestUrl = "$base/skills/MANIFEST"
    $skillsOut = Join-Path $OutDir "skills"
    $null = New-Item -ItemType Directory -Path $skillsOut -Force
    try {
      $manifestPath = Join-Path $skillsOut "MANIFEST"
      Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing -OutFile $manifestPath
      $lines = Get-Content $manifestPath -ErrorAction SilentlyContinue
      foreach ($line in $lines) {
        $line = $line.Trim()
        if (-not $line) { continue }
        $dir = Split-Path $line -Parent
        if ($dir) { $null = New-Item -ItemType Directory -Path (Join-Path $skillsOut $dir) -Force }
        $url = "$base/skills/$line"
        Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile (Join-Path $skillsOut $line) -ErrorAction SilentlyContinue
      }
    } catch { LogVerbose "Could not fetch skills MANIFEST: $_" }
    return $true
  } catch {
    LogVerbose "Download failed: $_"
    return $false
  }
}

function Create-SourceFiles {
  $SCRIPT:WORK_DIR = Join-Path $env:TEMP "oh-my-cursor-$(Get-Random)"
  $null = New-Item -ItemType Directory -Path $SCRIPT:WORK_DIR -Force
  if (Copy-SourcesFromLocalRepo $SCRIPT:WORK_DIR) {
    LogVerbose "Using local repo sources"
    return
  }
  if (Get-SourcesFromGitHub $SCRIPT:WORK_DIR) {
    LogVerbose "Downloaded sources from $SCRIPT:SOURCE_BASE_URL"
    return
  }
  if (Test-Path $SCRIPT:WORK_DIR) { Remove-Item -Path $SCRIPT:WORK_DIR -Recurse -Force }
  Write-Host "Failed to acquire source files. Tried local repo and GitHub." -ForegroundColor Red
  Write-Host "Set `$env:OH_MY_CURSOR_SOURCE_BASE_URL for a custom base URL." -ForegroundColor DarkGray
  exit 1
}

function Install-FileSet {
  param(
    [string]$SrcDir,
    [string]$DestDir,
    [string]$Label,
    [string[]]$Files
  )
  if ($Files.Count -eq 0) { return 0 }
  if (-not $SCRIPT:DRY_RUN) { $null = New-Item -ItemType Directory -Path $DestDir -Force }
  Log "Installing $Label to $DestDir"
  Log ""
  $failed = 0
  foreach ($f in $Files) {
    $src = Join-Path $SrcDir $f
    $dest = Join-Path $DestDir $f
    if (-not (Test-Path $src -PathType Leaf)) {
      LogVerbose "  [skip] $f (source not found)"
      continue
    }
    $destSub = Split-Path $dest -Parent
    if (-not $SCRIPT:DRY_RUN -and $destSub) { $null = New-Item -ItemType Directory -Path $destSub -Force }
    if (-not (Test-Path $dest)) {
      if ($SCRIPT:DRY_RUN) { Log "  [new] $f" }
      else {
        try {
          Copy-Item -Path $src -Destination $dest -Force
          Log "  [installed] $f"
        } catch { Log "  [failed] $f"; $failed++ }
      }
    } else {
      $srcHash = (Get-FileHash -Path $src -Algorithm MD5).Hash
      $destHash = (Get-FileHash -Path $dest -Algorithm MD5).Hash
      if ($srcHash -eq $destHash) {
        Log "  [unchanged] $f"
      } elseif ($SCRIPT:FORCE) {
        if ($SCRIPT:DRY_RUN) { Log "  [update] $f" }
        else {
          try {
            Copy-Item -Path $src -Destination $dest -Force
            Log "  [updated] $f"
          } catch { Log "  [failed] $f"; $failed++ }
        }
      } else {
        Log "  [skipped] $f (use -Force to overwrite)"
      }
    }
  }
  Log ""
  return $failed
}

function Migrate-LegacyAgents {
  param([string]$AgentsDir)
  foreach ($f in $LEGACY_AGENT_FILES + $LEGACY_PROTOCOL_FILES) {
    $target = Join-Path $AgentsDir $f
    if (Test-Path $target -PathType Leaf) {
      if ($SCRIPT:DRY_RUN) { Log "  [migrate] removing legacy $f" }
      else {
        Remove-Item -Path $target -Force
        Log "  [migrated] removed legacy $f"
      }
    }
  }
}

function Install-ToDir {
  param([string]$CursorDir)
  $agentsDir   = Join-Path $CursorDir "agents"
  $rulesDir    = Join-Path $CursorDir "rules"
  $commandsDir = Join-Path $CursorDir "commands"
  $hooksDir    = Join-Path $CursorDir "hooks"
  Migrate-LegacyAgents $agentsDir
  $w = $SCRIPT:WORK_DIR
  $null = Install-FileSet $w $agentsDir "agents" $AGENT_FILES
  $null = Install-FileSet $w $agentsDir "protocols" $PROTOCOL_FILES
  $null = Install-FileSet (Join-Path $w "commands") $commandsDir "commands" $COMMAND_FILES
  $null = Install-FileSet (Join-Path $w "hooks") $hooksDir "hooks" $HOOK_FILES
  Log "Installing rules to $rulesDir"
  Log ""
  if (-not $SCRIPT:DRY_RUN) { $null = New-Item -ItemType Directory -Path $rulesDir -Force }
  $src = Join-Path $w $RULE_FILE
  $dest = Join-Path $rulesDir $RULE_FILE
  if (-not (Test-Path $dest)) {
    if ($SCRIPT:DRY_RUN) { Log "  [new] $RULE_FILE" }
    else {
      try {
        Copy-Item -Path $src -Destination $dest -Force
        Log "  [installed] $RULE_FILE"
      } catch { Log "  [failed] $RULE_FILE" }
    }
  } else {
    $srcHash = (Get-FileHash -Path $src -Algorithm MD5).Hash
    $destHash = (Get-FileHash -Path $dest -Algorithm MD5).Hash
    if ($srcHash -eq $destHash) { Log "  [unchanged] $RULE_FILE" }
    elseif ($SCRIPT:FORCE) {
      if ($SCRIPT:DRY_RUN) { Log "  [update] $RULE_FILE" }
      else {
        try {
          Copy-Item -Path $src -Destination $dest -Force
          Log "  [updated] $RULE_FILE"
        } catch { Log "  [failed] $RULE_FILE" }
      }
    } else { Log "  [skipped] $RULE_FILE (use -Force to overwrite)" }
  }
  Log ""
}

function Install-Agents {
  Log "Installing to $($SCRIPT:CURSOR_DIR)"
  Log ""
  Install-ToDir $SCRIPT:CURSOR_DIR
  if ($SCRIPT:ALSO_CLAUDE) {
    $claudeDir = if ($SCRIPT:SCOPE -eq "user") { Join-Path $env:USERPROFILE ".claude" } else { Join-Path (Get-Location) ".claude" }
    Log "Also installing to $claudeDir (Claude Code compatibility)"
    Log ""
    Install-ToDir $claudeDir
  }
  if ($SCRIPT:ALSO_CODEX) {
    $codexDir = if ($SCRIPT:SCOPE -eq "user") { Join-Path $env:USERPROFILE ".codex" } else { Join-Path (Get-Location) ".codex" }
    Log "Also installing to $codexDir (Codex compatibility)"
    Log ""
    Install-ToDir $codexDir
  }
  Log "Summary"
  $skillInfo = if ($SCRIPT:WITH_SKILLS) { " | Skills: $($SKILL_DIRS.Count)" } else { " | Skills: skipped" }
  Log "  Mode: $CURSOR_MODE_LABEL"
  Log "  Agents: $($AGENT_FILES.Count) | Commands: $($COMMAND_FILES.Count) | Hooks: $($HOOK_FILES.Count)$skillInfo"
  Log ""
}

function Install-Skills {
  $srcSkills = Join-Path $SCRIPT:WORK_DIR "skills"
  if (-not (Test-Path $srcSkills -PathType Container)) {
    Log "Warning: bundled skills not found. Skipping."
    Log ""
    return
  }
  Log "Installing skills to $($SCRIPT:SKILLS_DIR)"
  Log ""
  if (-not $SCRIPT:DRY_RUN) { $null = New-Item -ItemType Directory -Path $SCRIPT:SKILLS_DIR -Force }
  foreach ($skill in $SKILL_DIRS) {
    $skillSrc = Join-Path $srcSkills $skill
    $skillDest = Join-Path $SCRIPT:SKILLS_DIR $skill
    if (-not (Test-Path $skillSrc -PathType Container)) {
      LogVerbose "  [skip] $skill (source not found)"
      continue
    }
    if (-not (Test-Path $skillDest)) {
      if ($SCRIPT:DRY_RUN) { Log "  [new] $skill/" }
      else {
        Copy-Item -Path $skillSrc -Destination $skillDest -Recurse -Force
        Log "  [installed] $skill/"
      }
    } else {
      $same = $false
      try {
        $srcFiles = Get-ChildItem -Path $skillSrc -Recurse -File
        $destFiles = Get-ChildItem -Path $skillDest -Recurse -File
        if ($srcFiles.Count -eq $destFiles.Count) {
          $same = $true
          foreach ($s in $srcFiles) {
            $rel = $s.FullName.Substring($skillSrc.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
            $d = Join-Path $skillDest $rel
            if (-not (Test-Path $d -PathType Leaf) -or (Get-FileHash -Path $s.FullName -Algorithm MD5).Hash -ne (Get-FileHash -Path $d -Algorithm MD5).Hash) {
              $same = $false
              break
            }
          }
        }
      } catch { }
      if ($same) {
        Log "  [unchanged] $skill/"
      } elseif ($SCRIPT:FORCE) {
        if ($SCRIPT:DRY_RUN) { Log "  [update] $skill/" }
        else {
          Remove-Item -Path $skillDest -Recurse -Force
          Copy-Item -Path $skillSrc -Destination $skillDest -Recurse -Force
          Log "  [updated] $skill/"
        }
      } else {
        Log "  [skipped] $skill/ (use -Force to overwrite)"
      }
    }
  }
  Log ""
}

function Toggle-OrchestratorRule {
  $rulePath = Join-Path $SCRIPT:RULES_DIR $RULE_FILE
  $disabledPath = Join-Path $SCRIPT:RULES_DIR "$RULE_FILE.disabled"
  Log "oh-my-cursor v$VERSION"
  Log $CURSOR_MODE_LABEL
  Log ""
  if ($SCRIPT:DISABLE) {
    if (Test-Path $rulePath -PathType Leaf) {
      if ($SCRIPT:DRY_RUN) { Log "  [would disable] $RULE_FILE in $($SCRIPT:RULES_DIR)" }
      else {
        Move-Item -Path $rulePath -Destination $disabledPath -Force
        Log "  [disabled] $RULE_FILE — orchestration off."
      }
    } else {
      if (Test-Path $disabledPath) { Log "  Already disabled ($RULE_FILE.disabled present)" }
      else { Log "  No rule file found at $rulePath" }
    }
  } else {
    if (Test-Path $disabledPath -PathType Leaf) {
      if ($SCRIPT:DRY_RUN) { Log "  [would enable] $RULE_FILE in $($SCRIPT:RULES_DIR)" }
      else {
        Move-Item -Path $disabledPath -Destination $rulePath -Force
        Log "  [enabled] $RULE_FILE — Team Avatar orchestration on."
      }
    } else {
      if (Test-Path $rulePath) { Log "  Already enabled ($RULE_FILE present)" }
      else { Log "  No disabled rule found at $disabledPath" }
    }
  }
  Log ""
}

function Uninstall-Agents {
  Log "oh-my-cursor v$VERSION"
  Log $CURSOR_MODE_LABEL
  Log ""
  if ($SCRIPT:DRY_RUN) { Log "Dry run mode -- no changes will be made"; Log "" }
  $removed = 0
  $allAgents = $AGENT_FILES + $LEGACY_AGENT_FILES
  $allProtocols = $PROTOCOL_FILES + $LEGACY_PROTOCOL_FILES
  Log "Removing agents from $($SCRIPT:AGENTS_DIR)"
  Log ""
  foreach ($f in $allAgents) {
    $target = Join-Path $SCRIPT:AGENTS_DIR $f
    if (Test-Path $target -PathType Leaf) {
      if ($SCRIPT:DRY_RUN) { Log "  [remove] $f" } else { Remove-Item -Path $target -Force; Log "  [removed] $f" }
      $removed++
    }
  }
  foreach ($f in $allProtocols) {
    $target = Join-Path $SCRIPT:AGENTS_DIR $f
    if (Test-Path $target -PathType Leaf) {
      if ($SCRIPT:DRY_RUN) { Log "  [remove] $f" } else { Remove-Item -Path $target -Force; Log "  [removed] $f" }
      $removed++
    }
  }
  $protocolsDir = Join-Path $SCRIPT:AGENTS_DIR "protocols"
  if (Test-Path $protocolsDir -PathType Container) {
    try { Remove-Item -Path $protocolsDir -Force -ErrorAction SilentlyContinue } catch { }
  }
  Log ""
  Log "Removing commands from $($SCRIPT:COMMANDS_DIR)"
  Log ""
  foreach ($f in $COMMAND_FILES) {
    $target = Join-Path $SCRIPT:COMMANDS_DIR $f
    if (Test-Path $target -PathType Leaf) {
      if ($SCRIPT:DRY_RUN) { Log "  [remove] $f" } else { Remove-Item -Path $target -Force; Log "  [removed] $f" }
      $removed++
    }
  }
  Log ""
  Log "Removing hooks from $($SCRIPT:HOOKS_DIR)"
  Log ""
  foreach ($f in $HOOK_FILES) {
    $target = Join-Path $SCRIPT:HOOKS_DIR $f
    if (Test-Path $target -PathType Leaf) {
      if ($SCRIPT:DRY_RUN) { Log "  [remove] $f" } else { Remove-Item -Path $target -Force; Log "  [removed] $f" }
      $removed++
    }
  }
  Log ""
  Log "Removing rules from $($SCRIPT:RULES_DIR)"
  Log ""
  $rulePath = Join-Path $SCRIPT:RULES_DIR $RULE_FILE
  $disabledPath = Join-Path $SCRIPT:RULES_DIR "$RULE_FILE.disabled"
  foreach ($path in @($rulePath, $disabledPath)) {
    if (Test-Path $path -PathType Leaf) {
      if ($SCRIPT:DRY_RUN) { Log "  [remove] $(Split-Path $path -Leaf)" } else { Remove-Item -Path $path -Force; Log "  [removed] $(Split-Path $path -Leaf)" }
      $removed++
    }
  }
  Log ""
  Log "Removing skills from $($SCRIPT:SKILLS_DIR)"
  Log ""
  foreach ($skill in $SKILL_DIRS) {
    $skillDir = Join-Path $SCRIPT:SKILLS_DIR $skill
    if (Test-Path $skillDir -PathType Container) {
      if ($SCRIPT:DRY_RUN) { Log "  [remove] $skill/" } else { Remove-Item -Path $skillDir -Recurse -Force; Log "  [removed] $skill/" }
      $removed++
    }
  }
  Log ""
  Log "Summary"
  Log "  Mode: $CURSOR_MODE_LABEL"
  if ($removed -gt 0) { Log "  Removed: $removed" } else { Log "  Nothing to remove" }
}

function Main {
  # When piped via `irm ... | iex`, $args is empty. Check env var for arguments.
  $envArgs = if ($env:OH_MY_CURSOR_ARGS) {
    $env:OH_MY_CURSOR_ARGS -split '\s+' | Where-Object { $_ -ne '' }
  } else { @() }
  Parse-Args (@($args) + $envArgs)
  Resolve-Dirs
  if ($SCRIPT:DISABLE -and $SCRIPT:ENABLE) {
    Write-Host "Cannot use --disable and --enable together." -ForegroundColor Red
    exit 1
  }
  if ($SCRIPT:DISABLE -or $SCRIPT:ENABLE) {
    Toggle-OrchestratorRule
    return
  }
  if ($SCRIPT:UNINSTALL) {
    Uninstall-Agents
    return
  }
  Create-SourceFiles
  try {
    Log "oh-my-cursor v$VERSION"
    Log $CURSOR_MODE_LABEL
    Log ""
    if ($SCRIPT:DRY_RUN) { Log "Dry run mode -- no changes will be made"; Log "" }
    LogVerbose "Scope: $($SCRIPT:SCOPE)"
    LogVerbose "Target: $($SCRIPT:CURSOR_DIR)"
    LogVerbose "Force: $($SCRIPT:FORCE)"
    Install-Agents
    if ($SCRIPT:WITH_SKILLS) { Install-Skills }
  } finally {
    if ($SCRIPT:WORK_DIR -and (Test-Path $SCRIPT:WORK_DIR)) {
      Remove-Item -Path $SCRIPT:WORK_DIR -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

Main @args
