<#
.SYNOPSIS
  Executes the plugin's PowerShell scripts and the write-guard hook against known inputs and
  asserts on the results. Run: pwsh -File tests/scripts.test.ps1  (or powershell.exe -File).

.DESCRIPTION
  lint.mjs checks that the scripts exist; this checks that they work. Every case here is one
  that was once wrong. Runs on Windows PowerShell 5.1 and PowerShell 7, on any OS, and writes
  only under a temporary directory it deletes afterwards.

  Secret-shaped values are assembled at run time, so this file does not itself trip a secret
  scanner pointed at this repository.

  Exit 0 when every assertion holds, 1 otherwise.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$repo = Split-Path -Parent $PSScriptRoot
$plugin = Join-Path $repo 'plugins/alrig'
$scripts = Join-Path $plugin 'scripts'
$psExe = (Get-Process -Id $PID).Path
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('alrig-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null

$script:failed = 0
$script:passed = 0
function Assert([string]$Name, [bool]$Condition, [string]$Detail = '') {
    if ($Condition) { $script:passed++; Write-Host "  ok    $Name" }
    else { $script:failed++; Write-Host "  FAIL  $Name  $Detail" -ForegroundColor Red }
}
function Section([string]$Name) { Write-Host ''; Write-Host "== $Name" }

# Runs a native command without Windows PowerShell turning its stderr into an exception.
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = & $Exe @Arguments 2>$null; return [pscustomobject]@{ Code = $LASTEXITCODE; Out = (@($out) -join "`n") } }
    finally { $ErrorActionPreference = $prev }
}
function Invoke-Script([string]$Name, [string[]]$Arguments) {
    return Invoke-Native $psExe (@('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $scripts $Name)) + $Arguments)
}

# Values that look like credentials, built so that no literal one sits in this file.
$k20 = 'Zr2LmP0v' + 'X7nB4kW9' + 'tYq1'
$k32 = '3f9a2c7e' + '1b5d4a8f' + '9c0e2b6d' + '7a1f3c5e'

try {
    Import-Module (Join-Path $scripts 'AlrigSecurity.psm1') -Force
    # The module returns each result list as one object (return ,$array); hand it back as the
    # array itself, so .Count is the number of findings and not 1.
    function Get-Secrets([string]$Text) { $r = Find-AlrigSecrets $Text; if ($null -eq $r) { $r = @() }; return , @($r) }
    function Get-Urls([string]$Text, [string[]]$Allow) { $r = Find-AlrigUrls $Text $Allow; if ($null -eq $r) { $r = @() }; return , @($r) }

    # ------------------------------------------------------------------ secrets
    Section 'Find-AlrigSecrets: credentials are found'
    $positive = [ordered]@{
        'secret-named assignment'      = "ApiKey := '$k20';"
        'bare Token assignment'        = "Token := '$k20';"
        'locked label'                 = "ApiKeyLbl: Label '$k20', Locked = true;"
        'header literal'               = "Headers.Add('x-api-key', '$k32');"
        'subscription-key header'      = "H.Add('Ocp-Apim-Subscription-Key', '$k32');"
        'IsolatedStorage.Set literal'  = "IsolatedStorage.Set('ApiKey', '$k20', DataScope::Module);"
        'bearer literal'               = "Headers.Add('Authorization', 'Bearer $k20');"
        'connection string password'   = "Conn := 'Server=db;User Id=app;Password=$k20;';"
        'credentials in a URL'         = "Url := 'https://svc:$k20@api.example.com/v1';"
    }
    foreach ($name in $positive.Keys) {
        $hits = (Get-Secrets $positive[$name])
        Assert $name ($hits.Count -gt 0) "no finding for: $($positive[$name])"
        foreach ($h in $hits) {
            $red = [string]$h.Redacted
            Assert "$name - redacted" (-not ($red.Contains($k20.Substring(0, 8)) -or $red.Contains($k32.Substring(0, 8)))) $red
        }
    }

    Section 'Find-AlrigSecrets: ordinary AL is left alone'
    $negative = [ordered]@{
        'password comparison'          = 'if Password = ConfirmPassword then'
        'pwd comparison'               = 'if Pwd = OtherPwd then'
        'GUID-valued key label'        = "EncryptionKeyLbl: Label '7f3c2a1e-9b4d-4c6a-8e2f-1a2b3c4d5e6f', Locked = true;"
        'storage key name label'       = "IsolatedStorageKeyTok: Label 'MyAppApiKeyStorageV2', Locked = true;"
        'StrSubstNo pattern'           = "PasswordFormat := '%1/%2/%3';"
        'caption label with Comment'   = "PasswordLbl: Label 'Enter the password for %1', Comment = '%1 = user name';"
        'token endpoint label'         = "TokenUrlTok: Label 'https://login.example.com/oauth2/token', Locked = true;"
        'secret name label'            = "SecretNameTok: Label 'MyVaultSecret2024ab', Locked = true;"
        'suppressed line'              = "ApiKey := '$k20'; // alrig:allow-secret test fixture"
    }
    foreach ($name in $negative.Keys) {
        $hits = (Get-Secrets $negative[$name])
        Assert $name ($hits.Count -eq 0) ("unexpected: " + (($hits | ForEach-Object { $_.Rule }) -join ', '))
    }

    Section 'Protect-AlrigSecret never shows a short value'
    foreach ($v in 'abcd', 'abcdefgh', 'abcdefghijkl') {
        $r = Protect-AlrigSecret $v
        Assert "length $($v.Length)" (-not $r.Contains($v.Substring(0, 2))) $r
    }

    # ------------------------------------------------------------------ URLs
    Section 'Find-AlrigUrls'
    $allow = Get-AlrigUrlAllowlist $null
    $urlCases = [ordered]@{
        'plain endpoint'               = @("Url := 'https://evil.example/x';", 1)
        'uppercase scheme and port'    = @("Url := 'HTTPS://EVIL.EXAMPLE:8443/x';", 1)
        'IP address'                   = @("Url := 'http://10.0.0.5/x';", 1)
        'userinfo cannot borrow host'  = @("Url := 'https://learn.microsoft.com@evil.example/c';", 1)
        'after /* inside a string'     = @("Route := '/api/*';`nUrl := 'https://evil.example/x';", 1)
        'after /* inside // comment'   = @("// matches /api/* routes`nUrl := 'https://evil.example/x';", 1)
        'platform help link'           = @("Url := 'https://learn.microsoft.com/x';", 0)
        'XML namespace'                = @("Ns := 'http://schemas.xmlsoap.org/soap/envelope/';", 0)
        'link in a comment'            = @("// see https://evil.example/doc", 0)
        'block comment'                = @("/* start`nUrl := 'https://evil.example/x';`n*/", 0)
        'suppressed line'              = @("Url := 'https://evil.example/x'; // alrig:allow-url fixed vendor", 0)
    }
    foreach ($name in $urlCases.Keys) {
        $n = (Get-Urls $urlCases[$name][0] $allow).Count
        Assert $name ($n -eq $urlCases[$name][1]) "found $n, expected $($urlCases[$name][1])"
    }
    $userinfo = (Get-Urls "Url := 'https://$k20@api.example.com/v1';" $allow)
    Assert 'userinfo is never reported as the host' (@($userinfo | Where-Object { ([string]$_.Host).Contains($k20) }).Count -eq 0)
    Assert 'allowlisted subdomain passes' ((Get-Urls "U := 'https://api.vendor.example/x';" @('vendor.example')).Count -eq 0)

    # ------------------------------------------------------------------ JSONC
    Section 'Read-AlrigJsonc'
    $s1 = Join-Path $tmp 's1.json'
    [IO.File]::WriteAllText($s1, '{"files.exclude": {"**/*.app": true}, "al.codeAnalyzers": ["${CodeCop}"], "search.exclude": {"**/node_modules": true}}')
    Assert 'globs containing /* survive' ((@((Read-AlrigJsonc $s1).'al.codeAnalyzers') -join ',') -eq '${CodeCop}')
    $s2 = Join-Path $tmp 's2.json'
    [IO.File]::WriteAllText($s2, "{`n  `"al.ruleSetPath`": `"x.ruleset.json`", // trailing comment`n  `"url`": `"https://example.com/a`",`n}")
    $j = Read-AlrigJsonc $s2
    Assert 'trailing // comment and comma' ($j.'al.ruleSetPath' -eq 'x.ruleset.json')
    Assert '// inside a string is kept' ($j.url -eq 'https://example.com/a')

    # ------------------------------------------------------------------ hook
    Section 'write guard hook (sh -> PowerShell)'
    $sh = $null
    $cmd = Get-Command sh -ErrorAction SilentlyContinue
    if ($cmd) { $sh = $cmd.Source }
    foreach ($c in 'C:\Program Files\Git\usr\bin\sh.exe', 'C:\Program Files\Git\bin\sh.exe') {
        if (-not $sh -and (Test-Path -LiteralPath $c)) { $sh = $c }
    }
    if (-not $sh) {
        Assert 'sh is available to run the hook' $false 'no sh found - the hook could not be tested'
    } else {
        $env:CLAUDE_PLUGIN_ROOT = $plugin
        $guard = (Join-Path $scripts 'al-write-guard.sh') -replace '\\', '/'
        function Invoke-Guard($payload) {
            $in = Join-Path $tmp 'payload.json'
            $err = Join-Path $tmp 'stderr.txt'
            [IO.File]::WriteAllText($in, ($payload | ConvertTo-Json -Depth 5 -Compress))
            $r = Invoke-Native $sh @('-c', 'sh "$1" < "$2" 2> "$3"', 'guard', $guard, ($in -replace '\\', '/'), ($err -replace '\\', '/'))
            $e = ''; if (Test-Path -LiteralPath $err) { $e = [IO.File]::ReadAllText($err) }
            return [pscustomobject]@{ Code = $r.Code; Err = $e }
        }
        $secretLine = "ApiKey := '$k20';"
        $hookCases = @(
            @('Write .al with a secret blocks',      2, @{ tool_name = 'Write'; tool_input = @{ file_path = 'C:\r\src\a.al'; content = $secretLine } }),
            @('Write .AL blocks',                    2, @{ tool_name = 'Write'; tool_input = @{ file_path = '/r/src/a.AL'; content = $secretLine } }),
            @('Write .aL blocks',                    2, @{ tool_name = 'Write'; tool_input = @{ file_path = '/r/src/a.aL'; content = $secretLine } }),
            @('Edit .al blocks',                     2, @{ tool_name = 'Edit'; tool_input = @{ file_path = '/r/a.al'; old_string = 'x'; new_string = $secretLine } }),
            @('MultiEdit .al blocks',                2, @{ tool_name = 'MultiEdit'; tool_input = @{ file_path = '/r/a.al'; edits = @(@{ old_string = 'x'; new_string = $secretLine }) } }),
            @('endpoint outside allowlist blocks',   2, @{ tool_name = 'Write'; tool_input = @{ file_path = '/r/a.al'; content = "Url := 'https://evil.example/x';" } }),
            @('clean .al passes',                    0, @{ tool_name = 'Write'; tool_input = @{ file_path = '/r/a.al'; content = 'x := 1;' } }),
            @('ordinary comparison passes',          0, @{ tool_name = 'Write'; tool_input = @{ file_path = '/r/a.al'; content = 'if Password = ConfirmPassword then' } }),
            @('secret in a non-AL file passes',      0, @{ tool_name = 'Write'; tool_input = @{ file_path = '/r/a.md'; content = $secretLine } }),
            @('.alpackages path passes',             0, @{ tool_name = 'Write'; tool_input = @{ file_path = '/r/.alpackages/x.json'; content = $secretLine } })
        )
        foreach ($c in $hookCases) {
            $r = Invoke-Guard $c[2]
            Assert $c[0] ($r.Code -eq $c[1]) "exit $($r.Code), expected $($c[1])"
            if ($c[1] -eq 2) { Assert "$($c[0]) - reason never shows the value" (-not $r.Err.Contains($k20.Substring(0, 8))) }
        }
        $bad = Join-Path $tmp 'garbage.json'
        [IO.File]::WriteAllText($bad, 'not json but mentions a.al"')
        $r = Invoke-Native $sh @('-c', 'sh "$1" < "$2"', 'guard', $guard, ($bad -replace '\\', '/'))
        Assert 'malformed payload fails open' ($r.Code -eq 0) "exit $($r.Code)"
    }

    # ------------------------------------------------------------------ ruleset
    Section 'Test-AlRuleset.ps1'
    $rs = Join-Path $tmp 'rs'
    New-Item -ItemType Directory -Path (Join-Path $rs 'src') | Out-Null
    $files = @{
        'base.ruleset.json'    = '{ "name": "base", "rules": [ { "id": "AA0001", "action": "Error" }, { "id": "AA0005", "action": "Warning" } ] }'
        'a.ruleset.json'       = '{ "name": "a", "includedRuleSets": [ { "action": "Default", "path": "./base.ruleset.json" } ], "rules": [] }'
        'b.ruleset.json'       = '{ "name": "b", "includedRuleSets": [ { "action": "Default", "path": "./base.ruleset.json" } ], "rules": [] }'
        'diamond.ruleset.json' = '{ "name": "d", "includedRuleSets": [ { "action": "Default", "path": "./a.ruleset.json" }, { "action": "Default", "path": "./b.ruleset.json" } ], "rules": [] }'
        'lower.ruleset.json'   = '{ "name": "l", "includedRuleSets": [ { "action": "Default", "path": "./base.ruleset.json" } ], "rules": [ { "id": "aa0001", "action": "Info" } ] }'
        'missing.ruleset.json' = '{ "name": "m", "includedRuleSets": [ { "action": "Default", "path": "./nope.ruleset.json" } ], "rules": [] }'
    }
    foreach ($f in $files.Keys) { [IO.File]::WriteAllText((Join-Path $rs $f), $files[$f]) }
    function Get-Ruleset([string[]]$a) { (Invoke-Script 'Test-AlRuleset.ps1' $a).Out | ConvertFrom-Json }

    $r = Get-Ruleset @('-RuleSet', (Join-Path $rs 'diamond.ruleset.json'), '-Baseline', (Join-Path $rs 'base.ruleset.json'))
    Assert 'diamond include is not a cycle' (-not $r.blocking) (($r.findings | ForEach-Object { $_.kind }) -join ', ')
    $r = Get-Ruleset @('-RuleSet', (Join-Path $rs 'lower.ruleset.json'), '-Baseline', (Join-Path $rs 'base.ruleset.json'))
    Assert 'a lowered rule blocks, whatever its case' ($r.blocking -and @($r.weakened).Count -eq 1)
    $r = Get-Ruleset @('-RuleSet', (Join-Path $rs 'a.ruleset.json'), '-Baseline', (Join-Path $rs 'lower.ruleset.json'))
    Assert 'a baseline that is not included blocks' (@($r.findings | Where-Object { $_.kind -eq 'baseline-not-included' }).Count -eq 1)
    $r = Get-Ruleset @('-RuleSet', (Join-Path $rs 'missing.ruleset.json'))
    Assert 'an unresolved include blocks' (@($r.findings | Where-Object { $_.kind -eq 'include-unresolved' -and $_.blocking }).Count -eq 1)

    [IO.File]::WriteAllText((Join-Path $rs 'src/x.al'), "codeunit 50100 X`n{`n#pragma warning disable /* all of them */`n    #pragma warning disable AA0001, AA0002 // legacy`n#pragma warning disable AA0005`n}`n")
    $r = Get-Ruleset @('-RuleSet', (Join-Path $rs 'a.ruleset.json'), '-Root', $rs)
    Assert 'every pragma is listed' (@($r.pragmas).Count -eq 3) "listed $(@($r.pragmas).Count)"
    Assert 'blanket pragma with a block comment blocks' (@($r.findings | Where-Object { $_.kind -eq 'blanket-pragma' -and $_.blocking }).Count -eq 1)
    Assert 'pragma with a reason is not flagged' (@($r.findings | Where-Object { $_.kind -eq 'pragma-without-reason' }).Count -eq 1)

    # ------------------------------------------------------------------ fixture repository
    $fx = Join-Path $tmp 'fx'
    Copy-Item -Recurse -LiteralPath (Join-Path $repo 'tests/fixtures/multi-app-product') -Destination $fx
    $sec = @(
        'codeunit 50299 "FFS Sec"', '{', '    var', '        FixtureKey: Text;', '',
        '    [NonDebuggable]', '    // Reads the stored key', '    procedure SetApiKey(ApiKey: Text)', '    begin',
        "        FixtureKey := 'sk_live_$k20'; // alrig:allow-secret test fixture only",
        "        IsolatedStorage.Set('ApiKey', '$k20', DataScope::Module);", '    end;', '}',
        'codeunit 50100 "FFS Outside"', '{', '}'
    ) -join "`r`n"
    [IO.File]::WriteAllText((Join-Path $fx 'app/src/Sec.Codeunit.al'), $sec)
    $gitAvailable = [bool](Get-Command git -ErrorAction SilentlyContinue)
    if ($gitAvailable) {
        foreach ($g in @(@('init', '-q'), @('add', '-A'), @('-c', 'user.email=t@example.com', '-c', 'user.name=t', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'base'))) {
            Invoke-Native 'git' (@('-C', $fx) + $g) | Out-Null
        }
    }

    Section 'Invoke-ReleaseCheck.ps1'
    $raw = (Invoke-Script 'Invoke-ReleaseCheck.ps1' @('-AppPath', (Join-Path $fx 'app'))).Out
    $rc = $null; try { $rc = $raw | ConvertFrom-Json } catch { }
    Assert 'prints one JSON object' ($null -ne $rc) $raw.Substring(0, [Math]::Min(200, $raw.Length))
    Assert 'output never contains a secret value' (-not $raw.Contains($k20.Substring(0, 8)))
    if ($rc) {
        Assert 'object outside the range is found' (@($rc.sections.idRanges.details.outside | Where-Object { $_.id -eq 50100 }).Count -eq 1)
        Assert 'comment after [NonDebuggable] does not hide it' (@($rc.sections.secrets.details.procedureWithoutNonDebuggable).Count -eq 0)
        Assert 'suppression is listed' (@($rc.sections.secrets.details.suppressions).Count -ge 1)
        Assert 'IsolatedStorage.Set literal is a GAP' ($rc.sections.secrets.status -eq 'GAP')
    }

    Section 'Invoke-SecretScan.ps1'
    $res = Invoke-Script 'Invoke-SecretScan.ps1' @('-Root', $fx, '-ReportDir', (Join-Path $tmp 'no-such-dir'))
    Assert 'a missing report directory is refused' ($res.Code -ne 0)
    Assert 'refusing it creates nothing' (-not (Test-Path -LiteralPath (Join-Path $tmp 'no-such-dir')))
    $reports = Join-Path $tmp 'reports'
    New-Item -ItemType Directory -Path $reports | Out-Null
    $res = Invoke-Script 'Invoke-SecretScan.ps1' @('-Root', $fx, '-ReportDir', $reports)
    $ss = $null; try { $ss = $res.Out | ConvertFrom-Json } catch { }
    Assert 'prints one JSON object' ($null -ne $ss) $res.Out.Substring(0, [Math]::Min(200, $res.Out.Length))
    Assert 'output never contains a secret value' (-not $res.Out.Contains($k20.Substring(0, 8)))
    if ($ss) {
        Write-Host "        engine: $($ss.engine) $($ss.engineVersion), mode: $($ss.mode)"
        if (Get-Command gitleaks -ErrorAction SilentlyContinue) {
            # The CI leg that installs gitleaks exists to exercise the shipped TOML; a silent
            # fallback to the built-in engine would make that leg prove nothing.
            Assert 'gitleaks is the engine when it is installed' ($ss.engine -eq 'gitleaks') $ss.engine
            Assert 'gitleaks scans the working tree too' ([string]$ss.mode -like '*working-tree*') $ss.mode
        }
        Assert 'the planted IsolatedStorage literal is found' (@($ss.findings | Where-Object { $_.file -like '*Sec.Codeunit.al' }).Count -ge 1)
        $report = @(Get-ChildItem -LiteralPath $reports -Filter 'secret-scan-*.md')
        Assert 'one dated report is written' ($report.Count -eq 1)
        if ($report.Count) { Assert 'report never contains a secret value' (-not ([IO.File]::ReadAllText($report[0].FullName)).Contains($k20.Substring(0, 8))) }
    }
    if ($gitAvailable) {
        $st = (Invoke-Native 'git' @('-C', $fx, 'status', '--porcelain')).Out
        Assert 'scans wrote nothing into the repository' ([string]::IsNullOrWhiteSpace($st)) $st
    }

    Section 'Invoke-AlScan.ps1'
    $res = Invoke-Script 'Invoke-AlScan.ps1' @('-AppPath', (Join-Path $fx 'app'), '-AlcPath', (Join-Path $tmp 'no-alc.exe'))
    $as = $null; try { $as = $res.Out | ConvertFrom-Json } catch { }
    Assert 'no compiler is UNVERIFIED, not clean' ($as -and $as.status -eq 'UNVERIFIED') $res.Out
}
catch {
    $script:failed++
    Write-Host "  FAIL  unexpected error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
}
finally {
    Remove-Module AlrigSecurity -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("scripts: {0} passed, {1} failed ({2} {3})" -f $script:passed, $script:failed, $PSVersionTable.PSEdition, $PSVersionTable.PSVersion)
if ($script:failed) { exit 1 }
exit 0
