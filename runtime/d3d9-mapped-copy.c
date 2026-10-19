/* Regression for a non-NX 32-bit image writing imported graphics memory.
 * Allocates one small buffer; submits no draws or presentation work. */
#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>
#include <string.h>
#define CHECK(x) do { HRESULT hr=(x); if(FAILED(hr)){fprintf(stderr,"FAIL %s %08lx\n",#x,(unsigned long)hr);return 1;} } while(0)
static HANDLE done;
static DWORD WINAPI watchdog(void *unused) {
    (void)unused;
    if (WaitForSingleObject(done, 10000) != WAIT_OBJECT_0) {
        fputs("FAIL mapped-copy deadline\n", stderr); fflush(stderr);
        TerminateProcess(GetCurrentProcess(), 7);
    }
    return 0;
}
typedef void *(__cdecl *Copy)(void *,const void *,size_t);
int main(void) {
    DWORD before=0, after=0; BOOL permanent=FALSE;
    if(!GetProcessDEPPolicy(GetCurrentProcess(), &before, &permanent) || (before & PROCESS_DEP_ENABLE)) {
        fputs("FAIL probe must start without DEP\n",stderr); return 2;
    }
    done=CreateEventA(NULL,TRUE,FALSE,NULL);
    HANDLE guard=CreateThread(NULL,0,watchdog,NULL,0,NULL);
    if(!done || !guard)return 3;
    IDirect3D9 *api=Direct3DCreate9(D3D_SDK_VERSION);
    if(!api)return 4;
    if(!GetProcessDEPPolicy(GetCurrentProcess(),&after,&permanent) || !(after&PROCESS_DEP_ENABLE) || !permanent) {
        fputs("FAIL runtime did not preserve non-executable data\n",stderr);return 5;
    }
    HWND window=CreateWindowA("STATIC","CrossedOver mapped-buffer check",WS_OVERLAPPEDWINDOW,
        0,0,64,64,NULL,NULL,GetModuleHandle(NULL),NULL);
    D3DPRESENT_PARAMETERS p={0};p.Windowed=TRUE;p.SwapEffect=D3DSWAPEFFECT_DISCARD;
    p.hDeviceWindow=window;p.BackBufferWidth=p.BackBufferHeight=16;p.BackBufferFormat=D3DFMT_A8R8G8B8;
    IDirect3DDevice9 *device=NULL;
    CHECK(IDirect3D9_CreateDevice(api,0,D3DDEVTYPE_HAL,window,D3DCREATE_HARDWARE_VERTEXPROCESSING,&p,&device));
    IDirect3DVertexBuffer9 *buffer=NULL;unsigned char *mapped=NULL;
    CHECK(IDirect3DDevice9_CreateVertexBuffer(device,16384,D3DUSAGE_DYNAMIC|D3DUSAGE_WRITEONLY,0,D3DPOOL_DEFAULT,&buffer,NULL));
    CHECK(IDirect3DVertexBuffer9_Lock(buffer,0,0,(void**)&mapped,D3DLOCK_DISCARD));
    HMODULE crt=LoadLibraryA("ucrtbase.dll");Copy copy=crt?(Copy)GetProcAddress(crt,"memcpy"):NULL;
    if(!copy)return 6;
    unsigned char source[96];for(unsigned i=0;i<sizeof(source);i++)source[i]=(unsigned char)(i*13+7);
    LARGE_INTEGER start,end,freq;QueryPerformanceFrequency(&freq);QueryPerformanceCounter(&start);
    for(unsigned offset=0;offset<16;offset++)for(unsigned i=0;i<128;i++) {
        copy(mapped+offset,source+offset,64);
        if(memcmp(mapped+offset,source+offset,64)){fputs("FAIL mapped copy contents\n",stderr);return 6;}
    }
    QueryPerformanceCounter(&end);
    CHECK(IDirect3DVertexBuffer9_Unlock(buffer));
    IDirect3DVertexBuffer9_Release(buffer);IDirect3DDevice9_Release(device);IDirect3D9_Release(api);DestroyWindow(window);
    SetEvent(done);WaitForSingleObject(guard,1000);CloseHandle(guard);CloseHandle(done);
    printf("mapped-buffer copies=2048 alignments=16 DEP=enabled/permanent valid=1 ms=%.3f\n",
        1000.0*(end.QuadPart-start.QuadPart)/freq.QuadPart);
    return 0;
}
