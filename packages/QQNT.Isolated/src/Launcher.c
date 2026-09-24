#ifndef UNICODE
#define UNICODE
#endif
#define _UNICODE
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <appmodel.h>
#include <stdio.h>
#include <wchar.h>

static void logline(HANDLE log, const wchar_t *text) {
    char utf8[8192];
    int count = WideCharToMultiByte(CP_UTF8, 0, text, -1, utf8, sizeof(utf8), NULL, NULL);
    DWORD written;
    if (log != INVALID_HANDLE_VALUE && count > 0) {
        WriteFile(log, utf8, count - 1, &written, NULL);
        WriteFile(log, "\r\n", 2, &written, NULL);
        FlushFileBuffers(log);
    }
}

/* user.dat supplies the known-folder overlay; AppData keeps the OS COW mapping. */
static BOOL redirectProfile(const wchar_t *state, HANDLE log) {
    const wchar_t *suffixes[] = {L"Documents", L"Desktop", L"Pictures", L"Music", L"Videos", L"Downloads"};
    wchar_t profile[32768], path[32768];
    swprintf(profile, 32768, L"%ls\\Profile", state);
    if (!CreateDirectoryW(profile, NULL) && GetLastError() != ERROR_ALREADY_EXISTS) return FALSE;
    swprintf(path, 32768, L"%ls\\AppData", profile);
    if (!CreateDirectoryW(path, NULL) && GetLastError() != ERROR_ALREADY_EXISTS) return FALSE;
    const wchar_t *appdirs[] = {L"Roaming", L"Local", L"LocalLow"};
    for (int i = 0; i < 3; i++) {
        swprintf(path, 32768, L"%ls\\AppData\\%ls", profile, appdirs[i]);
        if (!CreateDirectoryW(path, NULL) && GetLastError() != ERROR_ALREADY_EXISTS) return FALSE;
    }
    wchar_t family[256];
    UINT32 familySize = 256;
    if (GetCurrentPackageFamilyName(&familySize, family) != ERROR_SUCCESS) return FALSE;
    swprintf(path, 32768, L"%ls\\AppData\\Local\\Packages\\%ls\\AC", profile, family);
    int directoryResult = SHCreateDirectoryExW(NULL, path, NULL);
    if (directoryResult != ERROR_SUCCESS && directoryResult != ERROR_ALREADY_EXISTS && directoryResult != ERROR_FILE_EXISTS) return FALSE;
    if (!SetEnvironmentVariableW(L"LOCALAPPDATA", path)) return FALSE;
    swprintf(path, 32768, L"%ls\\AppData\\Roaming", profile);
    if (!SetEnvironmentVariableW(L"APPDATA", path)) return FALSE;
    BOOL ok = TRUE;
    for (int i = 0; i < 6; ++i) {
        swprintf(path, 32768, L"%ls\\%ls", profile, suffixes[i]);
        if (!CreateDirectoryW(path, NULL) && GetLastError() != ERROR_ALREADY_EXISTS) ok = FALSE;
    }
    ok = SetEnvironmentVariableW(L"QQ_ISOLATED_PROFILE", profile) && ok;
    ok = SetEnvironmentVariableW(L"USERPROFILE", profile) && ok;
    wchar_t drive[3] = {profile[0], L':', 0};
    ok = SetEnvironmentVariableW(L"HOMEDRIVE", drive) && ok;
    ok = SetEnvironmentVariableW(L"HOMEPATH", profile + 2) && ok;
    swprintf(path, 32768, L"%ls\\Temp", profile);
    if (!CreateDirectoryW(path, NULL) && GetLastError() != ERROR_ALREADY_EXISTS) ok = FALSE;
    ok = SetEnvironmentVariableW(L"TEMP", path) && ok;
    ok = SetEnvironmentVariableW(L"TMP", path) && ok;
    logline(log, ok ? L"Profile redirected inside the package." : L"Profile redirection failed.");
    return ok;
}

/* Run the access probes inside the real AppSilo process, using only a caller-created canary. */
static int probe(const wchar_t *state, const wchar_t *path, DWORD hostPid) {
    DWORD readError = 0, writeError = 0, processError = 0;
    HANDLE file = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    if (file == INVALID_HANDLE_VALUE) readError = GetLastError(); else CloseHandle(file);
    file = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    if (file == INVALID_HANDLE_VALUE) writeError = GetLastError(); else CloseHandle(file);
    HANDLE process = OpenProcess(PROCESS_VM_READ | PROCESS_VM_WRITE, FALSE, hostPid);
    if (!process) processError = GetLastError(); else CloseHandle(process);
    wchar_t output[32768];
    swprintf(output, 32768, L"%ls\\isolation-probe.json", state);
    file = CreateFileW(output, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return 20;
    char json[1024];
    int count = snprintf(json, sizeof(json), "{\"appContainer\":true,\"processId\":%lu,\"hostReadError\":%lu,\"hostWriteError\":%lu,\"hostProcessError\":%lu}\n", GetCurrentProcessId(), readError, writeError, processError);
    DWORD written;
    BOOL saved = WriteFile(file, json, count, &written, NULL);
    CloseHandle(file);
    if (!saved || written != (DWORD)count) return 21;
    return readError == ERROR_ACCESS_DENIED && writeError == ERROR_ACCESS_DENIED && processError == ERROR_ACCESS_DENIED ? 0 : 22;
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR args, int show) {
    wchar_t root[32768], state[32768], logpath[32768], exe[32768], cmd[32768], message[1024];
    HANDLE token = NULL;
    DWORD size, container = 0;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return 10;
    BOOL inspected = GetTokenInformation(token, TokenIsAppContainer, &container, sizeof(container), &size);
    CloseHandle(token);
    if (!inspected || !container) {
        MessageBoxW(NULL, L"Please launch QQ through the installed isolated application.", L"QQ Isolated", MB_ICONERROR);
        return 11;
    }
    DWORD len = GetModuleFileNameW(NULL, root, 32768);
    if (!len || len >= 32768) return 12;
    wchar_t *slash = wcsrchr(root, L'\\');
    if (!slash) return 12;
    *slash = 0;
    DWORD envlen = GetEnvironmentVariableW(L"LOCALAPPDATA", state, 32768);
    if (!envlen || envlen > 30000) return 13;
    wcscat(state, L"\\QQIsolated");
    if (!CreateDirectoryW(state, NULL) && GetLastError() != ERROR_ALREADY_EXISTS) return 15;
    swprintf(logpath, 32768, L"%ls\\launcher.log", state);
    SECURITY_ATTRIBUTES security = {sizeof(security), NULL, TRUE};
    HANDLE log = CreateFileW(logpath, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, &security, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (log == INVALID_HANDLE_VALUE) return 16;
    swprintf(message, 1024, L"Launcher PID=%lu AppContainer=%lu", GetCurrentProcessId(), container);
    logline(log, message);
    logline(log, root);
    logline(log, state);
    int argc = 0;
    wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    BOOL pathProbe = argv && argc >= 2 && wcsncmp(argv[1], L"--paths", 7) == 0;
    if (argv && argc == 4 && wcscmp(argv[1], L"--probe-file") == 0) {
        int result = probe(state, argv[2], wcstoul(argv[3], NULL, 10));
        LocalFree(argv);
        CloseHandle(log);
        return result;
    }
    if (argv) LocalFree(argv);
    if (!redirectProfile(state, log)) { CloseHandle(log); return 17; }
    swprintf(exe, 32768, L"%ls\\%ls", root, pathProbe ? L"PathProbe.exe" : L"QQ.exe");
    swprintf(cmd, 32768, L"\"%ls\" --no-sandbox --enable-logging=stderr --user-data-dir=\"%ls\\Chromium\"", exe, state);
    STARTUPINFOW startup = {0};
    PROCESS_INFORMATION process = {0};
    startup.cb = sizeof(startup);
    if (log != INVALID_HANDLE_VALUE) {
        startup.dwFlags = STARTF_USESTDHANDLES;
        startup.hStdOutput = log;
        startup.hStdError = log;
        startup.hStdInput = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &security, OPEN_EXISTING, 0, NULL);
    }
    logline(log, cmd);
    BOOL ok = CreateProcessW(exe, cmd, NULL, NULL, log != INVALID_HANDLE_VALUE, pathProbe ? CREATE_NO_WINDOW : 0, NULL, root, &startup, &process);
    if (!ok) {
        swprintf(message, 1024, L"CreateProcess failed: %lu", GetLastError());
        logline(log, message);
        if (log != INVALID_HANDLE_VALUE) CloseHandle(log);
        return 14;
    }
    swprintf(message, 1024, L"QQ PID=%lu", process.dwProcessId);
    logline(log, message);
    CloseHandle(process.hThread);
    WaitForSingleObject(process.hProcess, INFINITE);
    DWORD result = 0;
    GetExitCodeProcess(process.hProcess, &result);
    swprintf(message, 1024, L"QQ exit=%lu (0x%08lX)", result, result);
    logline(log, message);
    CloseHandle(process.hProcess);
    if (startup.hStdInput && startup.hStdInput != INVALID_HANDLE_VALUE) CloseHandle(startup.hStdInput);
    if (log != INVALID_HANDLE_VALUE) CloseHandle(log);
    return (int)result;
}
