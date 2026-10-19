/* Owned launcher stand-in: verifies Wine URI/child-process handoff, not Epic login. */
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
int main(int argc, char **argv) {
    const char *uri = NULL;
    char pending[8192] = {0};
    for (int i = 1; i < argc; ++i) if (!strcmp(argv[i], "-forwarduri")) {
        HKEY key; DWORD type = 0, bytes = sizeof(pending);
        if (RegOpenKeyExA(HKEY_CURRENT_USER, "Software\\Epic Games\\EpicGamesLauncher", 0, KEY_QUERY_VALUE | KEY_SET_VALUE, &key) != ERROR_SUCCESS) return 27;
        LONG result = RegQueryValueExA(key, "PendingUri", NULL, &type, (BYTE *)pending, &bytes);
        if (result != ERROR_SUCCESS || type != REG_SZ || !bytes || bytes >= sizeof(pending)) { RegCloseKey(key); return 28; }
        char *separator = strchr(pending, '|'), *end = NULL;
        if (!separator) { RegCloseKey(key); return 29; }
        strtoull(pending, &end, 10);
        if (end != separator) { RegCloseKey(key); return 30; }
        uri = separator + 1;
        RegDeleteValueA(key, "PendingUri"); RegCloseKey(key);
    }
    for (int i = 1; i < argc; ++i) if (!strncmp(argv[i], "com.epicgames.launcher://", strlen("com.epicgames.launcher://")) || !strncmp(argv[i], "uplay://", strlen("uplay://"))) uri = argv[i];
    if (!uri) uri = "com.epicgames.launcher://store/library";
    FILE *request = fopen("C:\\crossedover\\epic-handoff-request.txt", "wb");
    if (!request) return 21;
    fputs(uri, request); fclose(request);
    FILE *order = fopen("C:\\crossedover\\epic-handoff-order.txt", "ab");
    if (!order) return 26;
    fprintf(order, "%s\n", uri); fclose(order);
    if (!strcmp(uri, "com.epicgames.launcher://store/library")) return 0;
    if (strcmp(uri, "com.epicgames.launcher://apps/probe-ns%3Aprobe-item%3AOwnedProbe?action=launch&silent=false") &&
        strcmp(uri, "com.epicgames.launcher://apps/probe-ns%3Apartner-item%3AOwnedPartner?action=launch&silent=false") &&
        strcmp(uri, "uplay://launch/16382/0")) return 22;
    STARTUPINFOA si = {0}; PROCESS_INFORMATION pi = {0}; si.cb = sizeof(si);
    SECURITY_ATTRIBUTES sa = {sizeof(sa), NULL, TRUE};
    HANDLE output = CreateFileA("C:\\crossedover\\epic-readback.txt", GENERIC_WRITE, FILE_SHARE_READ, &sa, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (output == INVALID_HANDLE_VALUE) return 25;
    si.dwFlags = STARTF_USESTDHANDLES; si.hStdOutput = output; si.hStdError = output; si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    if (!CreateProcessA("C:\\Program Files\\Epic Games\\OwnedProbe\\Brawlhalla.exe", NULL, NULL, NULL, TRUE, 0, NULL,
        "C:\\Program Files\\Epic Games\\OwnedProbe", &si, &pi)) return 23;
    WaitForSingleObject(pi.hProcess, INFINITE);
    CloseHandle(output);
    DWORD code; GetExitCodeProcess(pi.hProcess, &code); CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
    FILE *result = fopen("C:\\crossedover\\epic-handoff-result.txt", "wb");
    if (!result) return 24;
    fprintf(result, "%lu", (unsigned long)code); fclose(result);
    return (int)code;
}
