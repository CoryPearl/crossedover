/* Owned x86/x64 probe for local .exe imports. No external software or accounts. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

static LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
    return DefWindowProcA(window, message, wparam, lparam);
}
int main(void) {
    char asset[64] = {0};
    FILE *input = fopen("assets/required.txt", "rb");
    if (!input) return 10;
    fread(asset, 1, sizeof(asset)-1, input); fclose(input);
    if (strcmp(asset, "crossedover sidecar\n")) return 11;
    HKEY key;
    if (RegCreateKeyExA(HKEY_CURRENT_USER, "Software\\CrossedoverExeProbe", 0, NULL, 0, KEY_WRITE, NULL, &key, NULL)) return 12;
    const char value[] = "round trip";
    LONG written = RegSetValueExA(key, "Result", 0, REG_SZ, (const BYTE *)value, sizeof(value));
    RegCloseKey(key);
    if (written) return 13;
    WNDCLASSA wc = {0}; wc.lpfnWndProc = window_proc; wc.hInstance = GetModuleHandleA(NULL); wc.lpszClassName = "CrossedoverOwnedProbe";
    if (!RegisterClassA(&wc)) return 14;
    HWND window = CreateWindowA(wc.lpszClassName, "Owned crossedover import probe", WS_OVERLAPPEDWINDOW, 0, 0, 320, 180, NULL, NULL, wc.hInstance, NULL);
    if (!window) return 15;
    SendMessageA(window, WM_NULL, 0, 0); DestroyWindow(window);
    FILE *output = fopen("probe-result.txt", "wb");
    if (!output) return 16;
    fprintf(output, "{\"bits\":%u,\"sidecarRead\":true,\"registryWrite\":true,\"windowCreated\":true}\n", (unsigned)(sizeof(void*)*8));
    fclose(output);
    Sleep(2500); /* The harness checks the persisted running state before exit. */
    return 0;
}
