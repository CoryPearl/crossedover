/* Owned windows only. No game binaries, window enumeration, or account access. */
#include <windows.h>
#include <stdio.h>

static void pump(DWORD milliseconds)
{
    DWORD until = GetTickCount() + milliseconds;
    MSG message;
    while ((LONG)(GetTickCount() - until) < 0)
    {
        while (PeekMessageA(&message, NULL, 0, 0, PM_REMOVE))
        {
            TranslateMessage(&message);
            DispatchMessageA(&message);
        }
        Sleep(10);
    }
}

int main(void)
{
    HINSTANCE instance = GetModuleHandleA(NULL);
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = instance;
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = "OwnedCrossedOverControls";
    if (!RegisterClassA(&wc)) return 1;
    const char *names[] = {"plain", "layered", "shaped", "desktop", "tool", "inactive", "small", "disabled"};
    for (int test = 0; test < 8; test++)
    {
        DWORD ex = test == 1 ? WS_EX_LAYERED : test == 4 ? WS_EX_TOOLWINDOW : test == 5 ? WS_EX_NOACTIVATE : 0;
        int width = test == 3 ? GetSystemMetrics(SM_CXSCREEN) : test == 6 ? 120 : 640;
        int height = test == 3 ? GetSystemMetrics(SM_CYSCREEN) : test == 6 ? 80 : 480;
        HWND window = CreateWindowExA(ex, wc.lpszClassName, "Owned fixture", WS_POPUP | (test == 7 ? WS_DISABLED : 0),
                                     test == 3 ? 0 : 60, test == 3 ? 0 : 90,
                                     width, height, NULL, NULL, instance, NULL);
        if (!window) return 2;
        if (test == 1 && !SetLayeredWindowAttributes(window, 0, 255, LWA_ALPHA)) return 3;
        if (test == 2)
        {
            HRGN region = CreateRectRgn(0, 0, width, height);
            if (!region || !SetWindowRgn(window, region, TRUE)) return 4;
        }
        ShowWindow(window, test == 5 ? SW_SHOWNOACTIVATE : SW_SHOW);
        UpdateWindow(window);
        pump(300);
        char title[128];
        snprintf(title, sizeof(title), "Owned crossedover controls:%s", names[test]);
        SetWindowTextA(window, title);
        pump(400);
        DestroyWindow(window);
        pump(100);
    }
    return 0;
}
