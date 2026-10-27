# Windows Port Doctor

Read-only diagnostics for a local Windows port. Collect TCP/UDP endpoints, process ownership, Windows excluded and dynamic port ranges, and visible WSL/Docker context in one text or JSON report.

Use it when an application cannot open a port and checking listening processes alone does not explain why. The report records observations and collection gaps; it cannot prove that a port is **FREE** or that your application can bind it.

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

## Arguments and exit codes

| Argument | Accepted values | Default |
| --- | --- | --- |
| `-Port` | One integer, `1` through `65535` | Required |
| `-Protocol` | `Both`, `TCP`, `UDP` | `Both` |
| `-AddressFamily` | `Both`, `IPv4`, `IPv6` | `Both` |
| `-Format` | `Text`, `Json` | `Text` |

Reports go to standard output. JSON output contains the report, with diagnostics kept separate. Missing or invalid arguments produce a usage error without an interactive prompt.

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
