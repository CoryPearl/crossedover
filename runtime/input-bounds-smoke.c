/* Owned native move/resize fixture. No game windows or synthetic input. */
#include <windows.h>
#include <stdio.h>
#include <string.h>
static int armed;
static RECT replacement;
static void pump(DWORD duration) {
    DWORD until=GetTickCount()+duration; MSG msg;
    while ((LONG)(GetTickCount()-until)<0) {
        while (PeekMessageA(&msg,0,0,0,PM_REMOVE)) { TranslateMessage(&msg); DispatchMessageA(&msg); }
        Sleep(10);
    }
}
static LRESULT CALLBACK procedure(HWND window, UINT msg, WPARAM w, LPARAM l) {
    if (msg==WM_SIZE && armed) {
        int action=armed; armed=0;
        if (action==1) ClipCursor(NULL);
        else { GetClientRect(window,&replacement); MapWindowPoints(window,NULL,(POINT*)&replacement,2);
            replacement.right=replacement.left+70; replacement.bottom=replacement.top+50; ClipCursor(&replacement); }
    }
    return DefWindowProcA(window,msg,w,l);
}
static RECT client(HWND window) { RECT rect; GetClientRect(window,&rect); MapWindowPoints(window,NULL,(POINT*)&rect,2); return rect; }
int main(void) {
    SetProcessDPIAware();
    WNDCLASSA wc={0}; wc.lpfnWndProc=procedure;wc.hInstance=GetModuleHandleA(NULL);wc.lpszClassName="OwnedInputBounds";
    if (!RegisterClassA(&wc)) return 1;
    const char *names[]={"grow","move","shrink","subrect","point","released","release_during","replace_during"};
    for (int test=0;test<8;test++) {
        ClipCursor(NULL);
        HWND window=CreateWindowExA(0,wc.lpszClassName,"Owned input fixture",WS_OVERLAPPEDWINDOW,
            80,90,420,300,NULL,NULL,wc.hInstance,NULL);
        if (!window) return 2;
        ShowWindow(window,SW_SHOW);SetForegroundWindow(window);pump(250);
        RECT before=client(window), requested=before, old_clip, after;
        if (test==3) {requested.right=requested.left+80;requested.bottom=requested.top+60;}
        if (test==4) {requested.right=requested.left+1;requested.bottom=requested.top+1;}
        if (!ClipCursor(test==5 ? NULL : &requested)) return 3;
        pump(100);GetClipCursor(&old_clip);
        if (test==6) armed=1;
        if (test==7) armed=2;
        const char *action=(test==1 || test==4) ? "move" : test==2 ? "shrink" : "grow";
        char title[96];snprintf(title,sizeof(title),"Owned crossedover input:%s",action);
        SetWindowTextA(window,title);pump(600);
        RECT current=client(window);GetClipCursor(&after);
        printf("INPUT_BOUNDS case=%s geometry=%d follows=%d unchanged=%d replaced=%d released=%d\n",
            names[test],!EqualRect(&before,&current),EqualRect(&after,&current),EqualRect(&after,&old_clip),
            test==7 && EqualRect(&after,&replacement),test==6 && !EqualRect(&after,&current) && !EqualRect(&after,&old_clip));
        fflush(stdout);armed=0;ClipCursor(NULL);DestroyWindow(window);pump(70);
    }
    return 0;
}
