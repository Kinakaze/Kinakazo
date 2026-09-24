#define UNICODE
#define _UNICODE
#include <windows.h>
#include <shlobj.h>
#include <stdio.h>

int main(void) {
    wchar_t path[32768];
    wchar_t profile[32768];
    if (!GetEnvironmentVariableW(L"QQ_ISOLATED_PROFILE",profile,32768)) return 1;
    int failures=0;
    const wchar_t *names[] = {L"USERPROFILE", L"APPDATA", L"LOCALAPPDATA", L"TEMP"};
    for (int i=0;i<4;i++) { GetEnvironmentVariableW(names[i],path,32768); wprintf(L"ENV %ls=%ls\n",names[i],path); }
    int folders[]={CSIDL_PERSONAL,CSIDL_APPDATA,CSIDL_LOCAL_APPDATA,CSIDL_PROFILE};
    for(int i=0;i<4;i++){
        path[0]=0;
        HRESULT hr=SHGetFolderPathW(NULL,folders[i],NULL,0,path);
        wprintf(L"FOLDER %d=%ls hr=%08lx\n",folders[i],path,hr);
        if(FAILED(hr) || _wcsnicmp(path,profile,wcslen(profile))!=0 || (path[wcslen(profile)]!=0 && path[wcslen(profile)]!=L'\\')) failures++;
    }
    HKEY key; LONG result=RegOpenKeyExW(HKEY_CURRENT_USER,L"Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders",0,KEY_QUERY_VALUE,&key);
    wprintf(L"REG open=%ld\n",result);
    if(result==0){ DWORD size=sizeof(path),type; result=RegQueryValueExW(key,L"Personal",0,&type,(BYTE*)path,&size); wprintf(L"REG Personal=%ls result=%ld\n",result==0?path:L"",result); RegCloseKey(key); }
    printf("PATH_VALIDATION_FAILURES=%d\n",failures);
    return failures ? 1 : 0;
}
