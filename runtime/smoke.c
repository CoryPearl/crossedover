#include <windows.h>
#include <stdio.h>
int main(void) {
    char directory[MAX_PATH];
    if (!GetWindowsDirectoryA(directory, MAX_PATH)) return 1;
    printf("{\"windowsDirectoryPresent\":true,\"pointerBits\":%u,\"pid\":%lu}\n", (unsigned)(8 * sizeof(void *)), GetCurrentProcessId());
    return 0;
}
