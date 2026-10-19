#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>
#define CHECK(call) do { HRESULT hr_ = (call); if (FAILED(hr_)) { fprintf(stderr, "%s failed: 0x%08lx\n", #call, (unsigned long)hr_); return 1; } } while(0)
int main(void) {
    HWND window = CreateWindowA("STATIC", "CrossedOver rendering test", WS_OVERLAPPEDWINDOW, 0, 0, 64, 64, NULL, NULL, GetModuleHandle(NULL), NULL);
    if (!window) return 1;
    IDirect3D9 *d3d = Direct3DCreate9(D3D_SDK_VERSION); if (!d3d) return 1;
    D3DPRESENT_PARAMETERS parameters = {0};
    parameters.Windowed = TRUE; parameters.SwapEffect = D3DSWAPEFFECT_DISCARD;
    parameters.hDeviceWindow = window; parameters.BackBufferWidth = parameters.BackBufferHeight = 16;
    parameters.BackBufferFormat = D3DFMT_A8R8G8B8; parameters.PresentationInterval = D3DPRESENT_INTERVAL_IMMEDIATE;
    IDirect3DDevice9 *device = NULL;
    CHECK(IDirect3D9_CreateDevice(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, window, D3DCREATE_SOFTWARE_VERTEXPROCESSING, &parameters, &device));
    CHECK(IDirect3DDevice9_Clear(device, 0, NULL, D3DCLEAR_TARGET, 0xff4080bf, 1.0f, 0));
    IDirect3DSurface9 *target = NULL, *staging = NULL;
    CHECK(IDirect3DDevice9_GetRenderTarget(device, 0, &target));
    CHECK(IDirect3DDevice9_CreateOffscreenPlainSurface(device, 16, 16, D3DFMT_A8R8G8B8, D3DPOOL_SYSTEMMEM, &staging, NULL));
    CHECK(IDirect3DDevice9_GetRenderTargetData(device, target, staging));
    D3DLOCKED_RECT rectangle; CHECK(IDirect3DSurface9_LockRect(staging, &rectangle, NULL, D3DLOCK_READONLY));
    unsigned long pixel = *(unsigned long *)rectangle.pBits;
    int valid = pixel == 0xff4080bf;
    printf("{\"api\":\"d3d9\",\"pointerBits\":%u,\"pixel\":\"%08lx\",\"valid\":%s}\n", (unsigned)(8 * sizeof(void *)), pixel, valid ? "true" : "false");
    IDirect3DSurface9_UnlockRect(staging); IDirect3DSurface9_Release(staging); IDirect3DSurface9_Release(target);
    IDirect3DDevice9_Release(device); IDirect3D9_Release(d3d); DestroyWindow(window);
    return valid ? 0 : 2;
}
