#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <shlobj.h>
#include <appmodel.h>
#include <stdio.h>
#include <stdlib.h>
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

/* Keep the logical AppData path: legacy mkdir implementations inspect every
   ancestor, but AppContainer cannot query the physical Packages\<PFN> root.
   Windows redirects writes here to this package's LocalCache\Local via COW. */
static BOOL getStatePaths(wchar_t *state, wchar_t *legacy) {
    wchar_t local[32768], family[256], suffix[512];
    DWORD length = GetEnvironmentVariableW(L"LOCALAPPDATA", local, 32768);
    UINT32 familySize = 256;
    if (!length || length >= 30000 || GetCurrentPackageFamilyName(&familySize, family) != ERROR_SUCCESS) return FALSE;
    swprintf(legacy, 32768, L"%ls\\QQIsolated", local);
    swprintf(suffix, 512, L"\\Packages\\%ls\\AC", family);
    size_t suffixLength = wcslen(suffix);
    /* Fail closed if the OS no longer supplies the expected AppContainer path. */
    if (length <= suffixLength || _wcsicmp(local + length - suffixLength, suffix)) return FALSE;
    local[length - suffixLength] = 0;
    swprintf(state, 32768, L"%ls\\QQIsolated", local);
    return TRUE;
}

static wchar_t *childPath(const wchar_t *parent, const wchar_t *name) {
    size_t count = wcslen(parent) + wcslen(name) + 2;
    if (count > 32768) { SetLastError(ERROR_FILENAME_EXCED_RANGE); return NULL; }
    wchar_t *path = malloc(count * sizeof(wchar_t));
    if (!path) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return NULL; }
    swprintf(path, count, L"%ls\\%ls", parent, name);
    return path;
}

/* Migrate only this package's previous private data; never follow user links.
   Keep the source intact so an interrupted copy can be retried before launch. */
static BOOL copyPrivateState(const wchar_t *source, const wchar_t *target) {
    wchar_t *pattern = childPath(source, L"*");
    WIN32_FIND_DATAW entry;
    if (!pattern) return FALSE;
    HANDLE search = FindFirstFileW(pattern, &entry);
    DWORD error = GetLastError();
    free(pattern);
    if (search == INVALID_HANDLE_VALUE) { SetLastError(error); return error == ERROR_FILE_NOT_FOUND; }
    error = ERROR_SUCCESS;
    do {
        if (!wcscmp(entry.cFileName, L".") || !wcscmp(entry.cFileName, L"..")) continue;
        if (entry.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) { error = ERROR_REPARSE_TAG_INVALID; break; }
        wchar_t *from = childPath(source, entry.cFileName);
        wchar_t *to = from ? childPath(target, entry.cFileName) : NULL;
        if (!from || !to) error = GetLastError();
        else {
            DWORD targetAttributes = GetFileAttributesW(to);
            if (targetAttributes != INVALID_FILE_ATTRIBUTES && (targetAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) error = ERROR_REPARSE_TAG_INVALID;
            else if (entry.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
                if (!CreateDirectoryW(to, NULL) && GetLastError() != ERROR_ALREADY_EXISTS) error = GetLastError();
                else if (!copyPrivateState(from, to)) error = GetLastError();
            } else if (!CopyFileW(from, to, FALSE)) error = GetLastError();
        }
        free(from);
        free(to);
        if (error) break;
    } while (FindNextFileW(search, &entry));
    if (!error && GetLastError() != ERROR_NO_MORE_FILES) error = GetLastError();
    FindClose(search);
    SetLastError(error);
    return error == ERROR_SUCCESS;
}

static BOOL prepareState(const wchar_t *state, const wchar_t *legacy) {
    wchar_t pending[32768];
    swprintf(pending, 32768, L"%ls.migration-pending", state);
    DWORD marker = GetFileAttributesW(pending);
    if (marker == INVALID_FILE_ATTRIBUTES && GetLastError() != ERROR_FILE_NOT_FOUND && GetLastError() != ERROR_PATH_NOT_FOUND) return FALSE;
    if (marker != INVALID_FILE_ATTRIBUTES && (marker & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))) { SetLastError(ERROR_INVALID_DATA); return FALSE; }
    DWORD attributes = GetFileAttributesW(state);
    if (attributes != INVALID_FILE_ATTRIBUTES) {
        if (!(attributes & FILE_ATTRIBUTE_DIRECTORY) || (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) { SetLastError(ERROR_DIRECTORY); return FALSE; }
        if (marker == INVALID_FILE_ATTRIBUTES) return TRUE;
    } else if (GetLastError() != ERROR_FILE_NOT_FOUND && GetLastError() != ERROR_PATH_NOT_FOUND) return FALSE;
    attributes = GetFileAttributesW(legacy);
    if (attributes == INVALID_FILE_ATTRIBUTES) {
        if (marker != INVALID_FILE_ATTRIBUTES) return FALSE;
        if (GetLastError() != ERROR_FILE_NOT_FOUND && GetLastError() != ERROR_PATH_NOT_FOUND) return FALSE;
        return CreateDirectoryW(state, NULL);
    }
    if (!(attributes & FILE_ATTRIBUTE_DIRECTORY) || (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) { SetLastError(ERROR_DIRECTORY); return FALSE; }
    /* AppSilo COW does not support renaming a directory at the AppData root.
       A marker also prevents partially migrated data from being used by QQ. */
    HANDLE migration = CreateFileW(pending, GENERIC_WRITE, 0, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (migration == INVALID_HANDLE_VALUE) return FALSE;
    BOOL ok = CreateDirectoryW(state, NULL) || GetLastError() == ERROR_ALREADY_EXISTS;
    if (ok) ok = copyPrivateState(legacy, state);
    DWORD error = GetLastError();
    CloseHandle(migration);
    if (!ok) { SetLastError(error); return FALSE; }
    return DeleteFileW(pending);
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
    /* QQ checks this directory before its own first-run initialization. */
    swprintf(path, 32768, L"%ls\\Documents\\Tencent Files", profile);
    directoryResult = SHCreateDirectoryExW(NULL, path, NULL);
    if (directoryResult != ERROR_SUCCESS && directoryResult != ERROR_ALREADY_EXISTS && directoryResult != ERROR_FILE_EXISTS) ok = FALSE;
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

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR args, int show) {
    wchar_t root[32768], state[32768], legacy[32768], logpath[32768], exe[32768], cmd[32768], message[1024];
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
    if (!getStatePaths(state, legacy)) return 13;
    if (!prepareState(state, legacy)) {
        swprintf(message, 1024, L"无法准备隔离数据目录（错误 %lu）。原有数据已保留。", GetLastError());
        MessageBoxW(NULL, message, L"QQNT.Isolated", MB_ICONERROR);
        return 15;
    }
    swprintf(logpath, 32768, L"%ls\\launcher.log", state);
    SECURITY_ATTRIBUTES security = {sizeof(security), NULL, TRUE};
    HANDLE log = CreateFileW(logpath, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, &security, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (log == INVALID_HANDLE_VALUE) return 16;
    swprintf(message, 1024, L"Launcher PID=%lu AppContainer=%lu", GetCurrentProcessId(), container);
    logline(log, message);
    logline(log, root);
    logline(log, state);
    if (!redirectProfile(state, log)) { CloseHandle(log); return 17; }
    swprintf(exe, 32768, L"%ls\\QQ.exe", root);
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
    BOOL ok = CreateProcessW(exe, cmd, NULL, NULL, log != INVALID_HANDLE_VALUE, 0, NULL, root, &startup, &process);
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
