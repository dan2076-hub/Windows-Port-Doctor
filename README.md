# Windows Port Doctor — Diagnose Port Conflicts and Excluded Port Ranges

Troubleshoot Windows port binding failures with a read-only PowerShell CLI. Inspect TCP/UDP endpoints, owning processes, excluded port ranges, and dynamic port ranges in one report. Export text, JSON, or Markdown for troubleshooting, support tickets, and automation.

Use it when a local development server reports **address already in use**, **EADDRINUSE**, or **WinError 10013**, or when checking listening processes alone does not explain a bind failure. Visible WSL/Docker process and service context is included without starting either system.

- **One diagnostic report:** endpoint states, process ownership and parent chain, and Windows port ranges.
- **Read-only operation:** no port killing, registry changes, firewall changes, or automatic elevation.
- **Local and scriptable:** no external runtime modules or network service required; JSON for scripts and AI agents.
- **Explicit uncertainty:** incomplete collection is identified. The tool does not test binding, guarantee that a port is free, or automatically fix the error.

[Quick start](#quick-start) · [Common port errors](#troubleshoot-windows-port-binding-errors) · [Example report](#example-diagnostic-report) · [FAQ](#frequently-asked-questions) · [AI agents and automation](#for-ai-agents-and-automation)

## Quick start

Download and extract this repository, or clone it:

```powershell
git clone https://github.com/dan2076-hub/Windows-Port-Doctor.git
cd Windows-Port-Doctor
```

Run from the repository directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\port-doctor.ps1 -Port 8888
```

`-ExecutionPolicy Bypass` applies to that PowerShell process. It does not change the machine or user execution policy. An organization policy can still prevent execution. No installer, external modules, or Pester download is required; the tool uses Windows NetTCPIP, CIM, .NET, and `netsh.exe`.

Filter to IPv4 TCP or save JSON:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\port-doctor.ps1 -Port 8888 -Protocol TCP -AddressFamily IPv4
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\port-doctor.ps1 -Port 8888 -Format Json > report.json
```

Review a saved report before sharing it. [Synthetic text](examples/report.txt) and [synthetic JSON](examples/report.json) examples illustrate the output without publishing a live machine report.

## Troubleshoot Windows port binding errors

These are symptoms to investigate, not errors the tool claims to repair automatically. Replace the example port with the port from your application's error message.

| Symptom or question | What to inspect in the report |
| --- | --- |
| `EADDRINUSE`, `address already in use`, or Windows socket error `10048` (`WSAEADDRINUSE`) | TCP/UDP endpoints, address family, bind address, state, and owning process. A process listening on another address is not automatically a conflict. |
| `WinError 10013` / `WSAEACCES`: socket access forbidden by access permissions | Matching excluded port ranges and collection gaps, alongside the application's address and socket options. This error has multiple possible causes; an exclusion is not a diagnosis by itself. |
| Port cannot be opened, but no listening process is visible | Excluded ranges, non-listening TCP states, IPv4/IPv6 differences, and unavailable evidence. No listener does not prove a port is available. |
| A local server or Docker port mapping cannot bind a Windows host port | Windows host endpoints and ranges, plus visible WSL/Docker context. The tool does not inspect container namespaces or diagnose a Linux guest from inside Windows. |

For example, investigate a local web server on port 3000:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\port-doctor.ps1 -Port 3000 -Protocol TCP -Explain
```

The [Microsoft Winsock error reference](https://learn.microsoft.com/en-us/windows/win32/winsock/windows-sockets-error-codes-2) explains errors 10013 and 10048. Use the application's exact error together with the observations in the report.

## Example diagnostic report

Excerpt from the included [synthetic text report](examples/report.txt), not a scan of a real machine:

```text
Windows Port Doctor 0.1.0
Port: 8888 | Protocol: Both | Address family: Both
Collection: complete | Data: synthetic

[TCP_LISTENER] TCP Listen observed on 127.0.0.1:8888 (PID 100).
[EXCLUDED_RANGE] Port appears in an excluded IPv4 TCP range 8800-8899. Ownership and bind availability are not established.

Processes (observed snapshot):
  TCP IPv4 127.0.0.1 Listen: python.exe (100) <- launcher.exe (200)
```

This example shows two separate findings: a TCP listener owned by a process, and a matching excluded range. It does not establish who created the exclusion or whether another application can bind. `Collection: complete` describes evidence collection, not port availability.

## Arguments and exit codes

| Argument | Accepted values | Default |
| --- | --- | --- |
| `-Port` | One integer, `1` through `65535` | Required |
| `-Protocol` | `Both`, `TCP`, `UDP` | `Both` |
| `-AddressFamily` | `Both`, `IPv4`, `IPv6` | `Both` |
| `-Format` | `Text`, `Json`, `Markdown` | `Text` |
| `-Explain` | Add detailed guidance and Microsoft references | Off |

Reports go to standard output. JSON output contains the report, with diagnostics kept separate. Missing or invalid arguments produce a usage error without an interactive prompt.

Use `-Explain` to add an interpretation and next steps for each finding, without additional collection or privileges:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\port-doctor.ps1 -Port 8888 -Explain
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\port-doctor.ps1 -Port 8888 -Format Json -Explain
```

JSON gains an optional `explanations` array only when this switch is used. Guidance is static, runs locally, and links to official Microsoft documentation; it does not guess the owner of an exclusion or apply fixes.

Generate a support-issue report with tables and optional explanations:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\port-doctor.ps1 -Port 8888 -Format Markdown -Explain > report.md
```

[Synthetic Markdown example](examples/report.md). Table cells escape Markdown separators, inline markup, HTML tags, and line breaks. Output contains the same normalized observations and collection gaps as JSON; it does not include raw command output. Review the result before attaching it to an issue.

| Exit code | Meaning |
| --- | --- |
| `0` | All requested collection completed, including when endpoints or exclusions were found. This does not mean the port is available. |
| `1` | Collection was partial or failed; inspect source status and findings. |
| `2` | The script detected an argument validation error. |

PowerShell parsing or parameter binding failures can have the shell's own nonzero exit code.

## Reading a report

- TCP endpoints retain their state. `Listen` is a listener; `Established`, `Bound`, and `TimeWait` are separate observations. UDP endpoints are reported separately.
- IPv4 and IPv6, and loopback, wildcard, and interface addresses, remain distinct. Binding depends on the address, protocol, socket options, permissions, and the application.
- A visible excluded range containing the port is a finding. An administered marker does not identify who created the exclusion.
- Dynamic range membership describes Windows client port allocation. It is not a bind prohibition or proof of the application's failure. `MaxUserPort`, when readable, is additional registry context; the active dynamic range comes from `netsh`.
- Process names, PIDs, and a bounded parent chain help identify ownership. Exited processes, unavailable fields, and possible PID reuse can leave ancestry unknown.
- WSL/Docker process and service observations provide context. Their presence does not prove they created an exclusion or caused a bind failure.
- Missing access, unavailable commands, and unrecognized source output produce explicit collection gaps. A snapshot can become stale immediately after collection.

An empty endpoint list is an observation at collection time. Even a complete report cannot guarantee a later bind will succeed. Check the application's exact bind address and socket error alongside the report.

## Frequently asked questions

### Which process is using a port on Windows?

Run `port-doctor.ps1 -Port 3000 -Protocol TCP` from the repository directory. Inspect the endpoint address, TCP state, process name, PID, and available parent chain. Use `-Protocol UDP` for UDP. The tool reports observed ownership; it does not stop the process.

### Why can I not bind a port when nothing is listening?

A listener search is only part of the evidence. Check excluded port ranges, other TCP states, the exact IPv4/IPv6 address, and missing permissions or unavailable sources. Socket options and application behavior also matter. Windows Port Doctor gathers context without claiming a single cause from an empty listener list.

### How do I check Windows excluded port ranges?

Run `port-doctor.ps1 -Port 8888 -Explain` and inspect the port-range section. The tool checks whether the requested port belongs to visible exclusions for the selected protocol and address family. For direct inspection, Windows also provides `netsh interface ipv4 show excludedportrange protocol=tcp`. An administered exclusion marker does not identify its owner.

### How is this different from netstat or Get-NetTCPConnection?

Those tools remain useful for endpoint inspection. Windows Port Doctor combines endpoint evidence with UDP, process ancestry, excluded and dynamic ranges, collection status, and shareable reports. It is not a packet capture tool, remote port scanner, firewall auditor, or replacement for an actual bind test.

### Does it fix Docker or WSL port conflicts?

It helps investigate the Windows host side. It reports visible Docker/WSL process and service context, but their presence does not prove that they caused a reservation or conflict. It neither starts nor stops them, and does not modify port mappings, firewall rules, or network settings.

### Does it need administrator rights or change Windows settings?

It does not automatically request administrator rights or change system settings. Some observations may be unavailable under your current permissions; those gaps are reported explicitly. Read the [behavior and privacy notes](#behavior-and-report-privacy) before sharing a report.

## For AI agents and automation

Use this CLI when an assistant or script needs structured evidence about a **local Windows port**. Run it on the Windows host being investigated, from a reviewed checkout, with an explicit port number. It is a PowerShell CLI, not an MCP server or a hosted API.

```powershell
$json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\port-doctor.ps1 -Port 8888 -Format Json
$diagnosticExitCode = $LASTEXITCODE
if ($diagnosticExitCode -notin 0, 1) {
    throw "Port Doctor did not produce a usable diagnostic run (exit $diagnosticExitCode)."
}
$report = ($json -join [Environment]::NewLine) | ConvertFrom-Json
if ($report.schema_version -ne 1) {
    throw 'Unsupported report schema.'
}
$report.completeness
$report.findings | Select-Object code, severity, message
$report.sources | Select-Object id, status, error_code
```

Important fields in [the complete synthetic JSON example](examples/report.json):

| Field | How to use it |
| --- | --- |
| `schema_version` | Check the schema version before relying on field structure. |
| `request` | Match the port, protocol, and address family to the user's problem. |
| `generated_at_utc` | Treat observations as a point-in-time snapshot. |
| `data_kind` | Distinguish synthetic examples from collected reports. |
| `completeness` and `sources` | Identify collection gaps before drawing conclusions. |
| `findings` | Inspect finding codes, severities, and descriptions; do not infer bind availability from an empty array. |
| `explanations` | Optional static guidance included with `-Explain`; it is not model-generated analysis. |

Exit `0` means collection completed, **not that the port is free**. Exit `1` requires inspection of partial or failed collection; preserve that uncertainty in the answer. Exit `2` means a script-detected argument error; shell failures can use other codes. Do not treat an error as an empty successful scan, or turn diagnostic output into an automatic instruction to kill a process or delete a port exclusion.

The tool itself makes no model calls and uploads no report. If an agent sends its output to a cloud model, that is a separate data transfer controlled by the agent. Review the report before sharing it.

## Behavior and report privacy

The diagnostic CLI does not bind sockets, stop applications or services, change the registry, firewall, or port ranges, or start WSL/Docker. An unresponsive read-only `netsh` query launched by the tool is cancelled after ten seconds. It does not automatically request administrator rights. Access restrictions appear in the report.

Process command lines and environment variables are not collected. Default output omits full paths, user names, and host names. Loopback and wildcard IP addresses remain visible; other addresses use consistent labels within the report. Process names and PIDs remain visible for diagnosis. These field restrictions are not a guarantee that every possible sensitive detail has been removed. Review reports before posting them publicly.

## Compatibility and tests

Targets: Windows 10 and Windows 11, with Windows PowerShell 5.1 or PowerShell 7 on Windows. The local validation platform is Windows 10 with Windows PowerShell 5.1. Local Windows 11 and PowerShell 7 testing is not claimed.

The included GitHub Actions workflow runs the test harness with both `powershell` and `pwsh` on `windows-latest`. A configured workflow is not evidence of a successful run; check the repository's Actions results. Windows Server runners do not establish Windows 11 compatibility.

Run deterministic tests without external test modules:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Opt into integration checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1 -Live
```

Only the live test harness opens its own temporary loopback TCP/UDP sockets, which it closes in `finally`. The diagnostic CLI reads endpoint state. Existing applications and system settings are left untouched. Localized parser fixtures are test data, not proof that every Windows language has been tested.

## Microsoft references

- [Get-NetTCPConnection](https://learn.microsoft.com/en-us/powershell/module/nettcpip/get-nettcpconnection) and [Get-NetUDPEndpoint](https://learn.microsoft.com/en-us/powershell/module/nettcpip/get-netudpendpoint)
- [netsh interface commands](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/netsh-interface)
- [Troubleshoot TCP/IP port exhaustion](https://learn.microsoft.com/en-us/troubleshoot/windows-client/networking/tcp-ip-port-exhaustion-troubleshooting)
- [Win32_Process](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-process)
- [SO_REUSEADDR and SO_EXCLUSIVEADDRUSE](https://learn.microsoft.com/en-us/windows/win32/winsock/using-so-reuseaddr-and-so-exclusiveaddruse) and [Windows Sockets error codes](https://learn.microsoft.com/en-us/windows/win32/winsock/windows-sockets-error-codes-2)
- [PowerShell execution policies](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies)

## License

[MIT](LICENSE). Copyright (c) 2026 dan2076-hub.
