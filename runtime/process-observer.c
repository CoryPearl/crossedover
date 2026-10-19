#define UNICODE
#define _UNICODE
#include <windows.h>
#include <tlhelp32.h>
#include <stdio.h>

static void json_string(const wchar_t *value) {
    char utf8[4096];
    if (!WideCharToMultiByte(CP_UTF8, 0, value, -1, utf8, sizeof utf8, NULL, NULL)) utf8[0] = 0;
    putchar('"');
    for (const unsigned char *p = (const unsigned char *)utf8; *p; p++) {
        if (*p == '"' || *p == '\\') { putchar('\\'); putchar(*p); }
        else if (*p < 32) printf("\\u%04x", *p);
        else putchar(*p);
    }
    putchar('"');
}
int main(void) {
    HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE) return 1;
    PROCESSENTRY32W entry; entry.dwSize = sizeof entry;
    int first = 1; putchar('[');
    if (Process32FirstW(snapshot, &entry)) do {
        if (entry.th32ProcessID == GetCurrentProcessId()) continue;
        if (!first) putchar(','); first = 0;
        printf("{\"pid\":%lu,\"executable\":", entry.th32ProcessID); json_string(entry.szExeFile); putchar('}');
    } while (Process32NextW(snapshot, &entry));
    puts("]"); CloseHandle(snapshot); return 0;
}
