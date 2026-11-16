# Reads a PreToolUse payload on stdin. Exit 2 with a reason on stderr blocks the write and
# hands the reason to Claude; exit 0 lets it through. Any internal failure exits 0 — a broken
# guard must never stop someone working.

$ErrorActionPreference = 'Stop'
try {
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $tool = $payload.tool_input
    if (-not $tool) { exit 0 }
    $file = [string]$tool.file_path
    if (-not ($file -match '\.al$')) { exit 0 }

    $texts = New-Object System.Collections.Generic.List[string]
    foreach ($p in 'content', 'new_string') {
        if ($tool.PSObject.Properties.Name -contains $p -and $tool.$p) { $texts.Add([string]$tool.$p) }
    }
    if ($tool.PSObject.Properties.Name -contains 'edits') {
        foreach ($e in @($tool.edits)) { if ($e.new_string) { $texts.Add([string]$e.new_string) } }
    }
    if ($texts.Count -eq 0) { exit 0 }

    Import-Module (Join-Path $PSScriptRoot 'AlrigSecurity.psm1') -Force
    $root = '.'
    if ($payload.PSObject.Properties.Name -contains 'cwd' -and $payload.cwd) { $root = [string]$payload.cwd }
    $allow = Get-AlrigUrlAllowlist (Get-AlrigProfile $root)

    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($t in $texts) {
        foreach ($s in (Find-AlrigSecrets $t)) {
            $hits.Add(("  line {0} of the new text: {1} ({2})" -f $s.Line, $s.Rule, $s.Redacted))
        }
        foreach ($u in (Find-AlrigUrls $t $allow)) {
            $hits.Add(("  line {0} of the new text: hardcoded endpoint, host '{1}' is not in the allowlist" -f $u.Line, $u.Host))
        }
    }
    if ($hits.Count -eq 0) { exit 0 }

    $head = @("alrig write guard: blocked a write to $([IO.Path]::GetFileName($file)).")
    $head += @($hits | Select-Object -First 10)
    $msg = $head + @(
        '',
        'Credentials never go in AL source. Read them at run time from IsolatedStorage (SetEncrypted,',
        'keyed by a Guid field on a setup table) or the app key vault, hold them in SecretText, and mark',
        'procedures that still handle them as Text with [NonDebuggable].',
        'Endpoints belong in a setup table the customer can change. If this host is genuinely fixed,',
        'add it to security.urlAllowlist in .claude/alrig.json (ask the user first), or end the line',
        'with // alrig:allow-url <reason>. A test fixture that needs a fake key may use',
        '// alrig:allow-secret <reason>; the release check lists every suppression.'
    )
    $msg = $msg -join [Environment]::NewLine
    [Console]::Error.WriteLine($msg)
    exit 2
}
catch {
    exit 0
}
