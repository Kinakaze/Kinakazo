param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
if (-not ('QQIsolation.OfflineRegistry' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
namespace QQIsolation {
    public static class OfflineRegistry {
        [DllImport("offreg.dll")] static extern uint ORCreateHive(out IntPtr hive);
        [DllImport("offreg.dll", CharSet=CharSet.Unicode)] static extern uint ORCreateKey(IntPtr key, string name, string keyClass, uint options, IntPtr security, out IntPtr result, out uint disposition);
        [DllImport("offreg.dll", CharSet=CharSet.Unicode)] static extern uint ORSetValue(IntPtr key, string name, uint type, byte[] value, uint length);
        [DllImport("offreg.dll", CharSet=CharSet.Unicode)] static extern uint ORSaveHive(IntPtr hive, string file, uint major, uint minor);
        [DllImport("offreg.dll")] static extern uint ORCloseHive(IntPtr hive);
        [DllImport("offreg.dll")] static extern uint ORCloseKey(IntPtr key);
        static void Check(uint result) { if (result != 0) throw new Win32Exception((int)result); }
        public static void Create(string file) {
            IntPtr hive;
            Check(ORCreateHive(out hive));
            try {
                IntPtr key = hive; uint disposition;
                string keyPath = @"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders";
                foreach (string part in keyPath.Split('\\')) {
                    IntPtr child;
                    Check(ORCreateKey(key, part, null, 0, IntPtr.Zero, out child, out disposition));
                    if (key != hive) ORCloseKey(key);
                    key = child;
                }
                try {
                    string[] names = {"Personal", "Desktop", "My Pictures", "My Music", "My Video", "{374DE290-123F-4565-9164-39C4925E467B}", "AppData", "Local AppData"};
                    string[] dirs = {"Documents", "Desktop", "Pictures", "Music", "Videos", "Downloads", @"AppData\Roaming", @"AppData\Local"};
                    for (int i=0; i<names.Length; i++) {
                        byte[] data = Encoding.Unicode.GetBytes(@"%QQ_ISOLATED_PROFILE%\" + dirs[i] + "\0");
                        Check(ORSetValue(key, names[i], 2, data, (uint)data.Length));
                    }
                } finally { ORCloseKey(key); }
                Check(ORSaveHive(hive, file, 6, 1));
            } finally { ORCloseHive(hive); }
        }
    }
}
'@
}
[QQIsolation.OfflineRegistry]::Create([IO.Path]::GetFullPath($OutputPath))
