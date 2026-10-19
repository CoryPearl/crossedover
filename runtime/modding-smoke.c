/* Exercise Windows mod-file access and the shell folder route without Steam credentials. */
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
    static const char content[] = "crossedover mod file round trip\n";
    char result[sizeof(content)] = {0};
    DWORD written = 0, read = 0;
    HANDLE file;
    BOOL okay;
    CreateDirectoryW(L"C:\\crossedover", NULL);
    CreateDirectoryW(L"C:\\crossedover\\modding-smoke", NULL);
    file = CreateFileW(L"C:\\crossedover\\modding-smoke\\test-mod.txt", GENERIC_READ | GENERIC_WRITE,
                      FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE) return 1;
    okay = WriteFile(file, content, sizeof(content) - 1, &written, NULL);
    SetFilePointer(file, 0, NULL, FILE_BEGIN);
    okay = okay && ReadFile(file, result, sizeof(result) - 1, &read, NULL);
    CloseHandle(file);
    if (!okay || read != sizeof(content) - 1 || written != read || memcmp(content, result, read)) return 2;
    puts("{\"windowsFileRoundTrip\":true}");
    fflush(stdout);
    if (argc > 1 && !strcmp(argv[1], "--browse"))
    {
        SHELLEXECUTEINFOW launch = {0};
        launch.cbSize = sizeof(launch);
        launch.fMask = SEE_MASK_NOCLOSEPROCESS | SEE_MASK_FLAG_NO_UI;
        launch.lpVerb = L"open";
        launch.lpFile = L"C:\\crossedover\\modding-smoke";
        launch.nShow = SW_SHOWNORMAL;
        if (!ShellExecuteExW(&launch) || (UINT_PTR)launch.hInstApp <= 32) return 3;
        if (launch.hProcess) CloseHandle(launch.hProcess);
        puts("{\"shellFolderOpenAccepted\":true}");
        fflush(stdout);
    }
    {
        WNDCLASSW window_class = {0};
        HWND window;
        DWORD start;
        MSG message;
        window_class.lpfnWndProc = DefWindowProcW;
        window_class.hInstance = GetModuleHandleW(NULL);
        window_class.lpszClassName = L"CrossedoverModdingSmoke";
        RegisterClassW(&window_class);
        window = CreateWindowW(window_class.lpszClassName, L"Steam", WS_OVERLAPPEDWINDOW,
                               100, 100, 400, 160, NULL, NULL, window_class.hInstance, NULL);
        if (!window) return 4;
        ShowWindow(window, SW_SHOW);
        start = GetTickCount();
        while (GetTickCount() - start < 4000)
        {
            while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE))
            {
                TranslateMessage(&message);
                DispatchMessageW(&message);
            }
            Sleep(10);
        }
        DestroyWindow(window);
    }
    return 0;
}
