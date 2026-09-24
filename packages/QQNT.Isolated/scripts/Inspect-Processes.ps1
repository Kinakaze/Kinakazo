param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
if (-not ('QQIsolation.ProcessToken' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
namespace QQIsolation {
    public class TokenResult {
        public int ProcessId;
        public bool IsAppContainer;
        public string AppContainerSid;
        public string IntegritySid;
        public string PackageFullName;
    }
    public static class ProcessToken {
        [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError=true)] static extern bool GetTokenInformation(IntPtr token, int type, IntPtr info, int length, out int returned);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern int GetPackageFullName(IntPtr process, ref uint length, StringBuilder name);
        static IntPtr Info(IntPtr token, int type) {
            int length;
            GetTokenInformation(token, type, IntPtr.Zero, 0, out length);
            if (length == 0) throw new Win32Exception(Marshal.GetLastWin32Error());
            IntPtr data = Marshal.AllocHGlobal(length);
            if (!GetTokenInformation(token, type, data, length, out length)) {
                int error = Marshal.GetLastWin32Error();
                Marshal.FreeHGlobal(data);
                throw new Win32Exception(error);
            }
            return data;
        }
        public static TokenResult Read(int pid) {
            IntPtr process = OpenProcess(0x1000, false, pid);
            if (process == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            IntPtr token = IntPtr.Zero;
            try {
                if (!OpenProcessToken(process, 8, out token)) throw new Win32Exception(Marshal.GetLastWin32Error());
                var result = new TokenResult { ProcessId = pid };
                IntPtr data = Info(token, 29);
                try { result.IsAppContainer = Marshal.ReadInt32(data) != 0; } finally { Marshal.FreeHGlobal(data); }
                data = Info(token, 25);
                try { result.IntegritySid = new SecurityIdentifier(Marshal.ReadIntPtr(data)).Value; } finally { Marshal.FreeHGlobal(data); }
                if (result.IsAppContainer) {
                    data = Info(token, 31);
                    try { result.AppContainerSid = new SecurityIdentifier(Marshal.ReadIntPtr(data)).Value; } finally { Marshal.FreeHGlobal(data); }
                }
                uint count = 0;
                if (GetPackageFullName(process, ref count, null) == 122) {
                    var name = new StringBuilder((int)count);
                    if (GetPackageFullName(process, ref count, name) == 0) result.PackageFullName = name.ToString();
                }
                return result;
            } finally {
                if (token != IntPtr.Zero) CloseHandle(token);
                CloseHandle(process);
            }
        }
    }
}
'@
}
$package = Get-AppxPackage -Name QQNT.Isolated
if (-not $package) { throw 'QQNT.Isolated is not installed.' }
$processes = @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($package.InstallLocation + '\', [StringComparison]::OrdinalIgnoreCase) })
if ($processes.Count -eq 0) { throw 'No isolated application process is running.' }
$results = @($processes | ForEach-Object {
    $result = [QQIsolation.ProcessToken]::Read($_.ProcessId)
    $process = Get-Process -Id $_.ProcessId
    [pscustomobject]@{
        ProcessId = $_.ProcessId
        ParentProcessId = $_.ParentProcessId
        Name = $_.Name
        IsAppContainer = $result.IsAppContainer
        AppContainerSid = $result.AppContainerSid
        IntegritySid = $result.IntegritySid
        PackageFullName = $result.PackageFullName
        WindowTitle = $process.MainWindowTitle
        WindowHandle = $process.MainWindowHandle.ToInt64()
        Responding = $process.Responding
        CommandLine = $_.CommandLine
    }
})
if ($OutputPath) { $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $OutputPath -Encoding UTF8 }
$results
if (@($results | Where-Object { -not $_.IsAppContainer -or $_.IntegritySid -ne 'S-1-16-4096' -or $_.PackageFullName -ne $package.PackageFullName }).Count) {
    throw 'Process isolation validation failed.'
}
