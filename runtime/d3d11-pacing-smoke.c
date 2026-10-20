/* Owned fixture only: bounded clear/present loop, no game or account access. */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

#define CHECK(x) do { HRESULT result = (x); if (FAILED(result)) { fprintf(stderr, "HRESULT %08lx at %d\n", (unsigned long)result, __LINE__); return 1; } } while (0)
static int compare(const void *a, const void *b) { double x=*(const double *)a, y=*(const double *)b; return (x>y)-(x<y); }
int main(void) {
    WNDCLASSA wc={0}; wc.lpfnWndProc=DefWindowProcA; wc.hInstance=GetModuleHandleA(NULL); wc.lpszClassName="CrossedOverOwnedPacing";
    if (!RegisterClassA(&wc)) return 1;
    HWND window=CreateWindowA(wc.lpszClassName,"crossedover owned presentation test",WS_OVERLAPPEDWINDOW,80,100,640,360,NULL,NULL,wc.hInstance,NULL);
    if (!window) return 1;
    ShowWindow(window, SW_SHOWNOACTIVATE);
    DXGI_SWAP_CHAIN_DESC desc={0}; desc.BufferDesc.Width=640; desc.BufferDesc.Height=360;
    desc.BufferDesc.Format=DXGI_FORMAT_R8G8B8A8_UNORM; desc.SampleDesc.Count=1;
    desc.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT; desc.BufferCount=2; desc.OutputWindow=window;
    desc.Windowed=TRUE; desc.SwapEffect=DXGI_SWAP_EFFECT_DISCARD;
    ID3D11Device *device=NULL; ID3D11DeviceContext *context=NULL; IDXGISwapChain *swap=NULL; D3D_FEATURE_LEVEL feature;
    CHECK(D3D11CreateDeviceAndSwapChain(NULL,D3D_DRIVER_TYPE_HARDWARE,NULL,0,NULL,0,D3D11_SDK_VERSION,&desc,&swap,&device,&feature,&context));
    IDXGIDevice *dxgi=NULL; IDXGIAdapter *adapter=NULL; DXGI_ADAPTER_DESC adapter_desc;
    CHECK(ID3D11Device_QueryInterface(device,&IID_IDXGIDevice,(void **)&dxgi));
    CHECK(IDXGIDevice_GetAdapter(dxgi,&adapter)); CHECK(IDXGIAdapter_GetDesc(adapter,&adapter_desc));
    int config_matched = wcsstr(adapter_desc.Description,L"crossedover pacing fixture") != NULL;
    IDXGIAdapter_Release(adapter); IDXGIDevice_Release(dxgi);
    ID3D11Texture2D *buffer=NULL; ID3D11RenderTargetView *view=NULL;
    CHECK(IDXGISwapChain_GetBuffer(swap,0,&IID_ID3D11Texture2D,(void **)&buffer));
    CHECK(ID3D11Device_CreateRenderTargetView(device,(ID3D11Resource *)buffer,NULL,&view));
    LARGE_INTEGER frequency,start,now,previous; QueryPerformanceFrequency(&frequency); QueryPerformanceCounter(&previous);
    double samples[120], total=0; int count=0;
    for (int i=0;i<140;i++) {
        MSG message; while(PeekMessageA(&message,NULL,0,0,PM_REMOVE)) { TranslateMessage(&message); DispatchMessageA(&message); }
        QueryPerformanceCounter(&start);
        const FLOAT color[]={0.12f,0.12f,0.12f,1.0f}; ID3D11DeviceContext_ClearRenderTargetView(context,view,color);
        CHECK(IDXGISwapChain_Present(swap,0,0));
        /* A bounded 60 FPS CPU loop; presentation completes asynchronously. */
        do { QueryPerformanceCounter(&now); if ((double)(now.QuadPart-start.QuadPart)/frequency.QuadPart<1.0/60.0) Sleep(1); else break; } while (1);
        QueryPerformanceCounter(&now);
        if (i>=20) { double elapsed=1000.0*(now.QuadPart-previous.QuadPart)/frequency.QuadPart; samples[count++]=elapsed; total+=elapsed; }
        previous=now;
    }
    qsort(samples,count,sizeof(double),compare);
    printf("{\"samples\":%d,\"configMatched\":%s,\"presentLoopFPS\":%.2f,\"medianMs\":%.3f,\"p95Ms\":%.3f,\"p99Ms\":%.3f}\n",count,config_matched ? "true" : "false",1000.0*count/total,samples[count/2],samples[(count*95)/100],samples[(count*99)/100]);
    ID3D11RenderTargetView_Release(view); ID3D11Texture2D_Release(buffer); IDXGISwapChain_Release(swap);
    ID3D11DeviceContext_Release(context); ID3D11Device_Release(device); DestroyWindow(window); return 0;
}
