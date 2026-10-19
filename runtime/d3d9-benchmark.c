#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>
#include <stdlib.h>

/* A fixed, GPU-synchronized workload for comparing backends. These are not
 * TrackMania frame rates: the real game must be measured separately. */
#define CHECK(call) do { HRESULT hr = (call); if (FAILED(hr)) { fprintf(stderr, "%s: 0x%08lx\n", #call, (unsigned long)hr); return 1; } } while (0)
typedef struct { float x, y, z, rhw; DWORD color; } Vertex;
static int compare(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}
int main(void) {
    const unsigned count = 120, warmup = 10, tiles = 16;
    HWND window = CreateWindowA("STATIC", "CrossedOver D3D9 benchmark", WS_OVERLAPPEDWINDOW,
        0, 0, 1280, 720, NULL, NULL, GetModuleHandle(NULL), NULL);
    if (!window) return 1;
    IDirect3D9 *api = Direct3DCreate9(D3D_SDK_VERSION);
    if (!api) return 1;
    D3DADAPTER_IDENTIFIER9 adapter;
    CHECK(IDirect3D9_GetAdapterIdentifier(api, 0, 0, &adapter));
    D3DPRESENT_PARAMETERS p = {0};
    p.Windowed = TRUE; p.SwapEffect = D3DSWAPEFFECT_DISCARD;
    p.hDeviceWindow = window; p.BackBufferWidth = 1280; p.BackBufferHeight = 720;
    p.BackBufferFormat = D3DFMT_A8R8G8B8; p.PresentationInterval = D3DPRESENT_INTERVAL_IMMEDIATE;
    IDirect3DDevice9 *device = NULL;
    CHECK(IDirect3D9_CreateDevice(api, 0, D3DDEVTYPE_HAL, window,
        D3DCREATE_HARDWARE_VERTEXPROCESSING, &p, &device));
    CHECK(IDirect3DDevice9_SetFVF(device, D3DFVF_XYZRHW | D3DFVF_DIFFUSE));
    CHECK(IDirect3DDevice9_SetRenderState(device, D3DRS_LIGHTING, FALSE));
    CHECK(IDirect3DDevice9_SetRenderState(device, D3DRS_CULLMODE, D3DCULL_NONE));
    IDirect3DQuery9 *completion = NULL;
    CHECK(IDirect3DDevice9_CreateQuery(device, D3DQUERYTYPE_EVENT, &completion));
    LARGE_INTEGER frequency, start, end;
    QueryPerformanceFrequency(&frequency);
    double samples[120], total = 0;
    for (unsigned frame = 0; frame < count + warmup; ++frame) {
        QueryPerformanceCounter(&start);
        CHECK(IDirect3DDevice9_Clear(device, 0, NULL, D3DCLEAR_TARGET, 0xff102030, 1, 0));
        CHECK(IDirect3DDevice9_BeginScene(device));
        for (unsigned y = 0; y < tiles; ++y) for (unsigned x = 0; x < tiles; ++x) {
            float left = 2 + x * 80, top = 2 + y * 45;
            DWORD color = 0xff000000 | ((x * 15) << 16) | ((y * 15) << 8) | (frame & 255);
            Vertex v[] = {{left,top,0.5f,1,color},{left+75,top,0.5f,1,color},
                {left,top+40,0.5f,1,color},{left+75,top+40,0.5f,1,color}};
            CHECK(IDirect3DDevice9_DrawPrimitiveUP(device, D3DPT_TRIANGLESTRIP, 2, v, sizeof(Vertex)));
        }
        CHECK(IDirect3DDevice9_EndScene(device));
        CHECK(IDirect3DQuery9_Issue(completion, D3DISSUE_END));
        DWORD until = GetTickCount() + 10000;
        HRESULT status;
        while ((status = IDirect3DQuery9_GetData(completion, NULL, 0, D3DGETDATA_FLUSH)) == S_FALSE) {
            if ((LONG)(GetTickCount() - until) >= 0) { fprintf(stderr, "GPU completion timed out\n"); return 1; }
            SwitchToThread();
        }
        CHECK(status);
        CHECK(IDirect3DDevice9_Present(device, NULL, NULL, NULL, NULL));
        QueryPerformanceCounter(&end);
        if (frame >= warmup) {
            double ms = 1000.0 * (end.QuadPart - start.QuadPart) / frequency.QuadPart;
            samples[frame-warmup] = ms; total += ms;
        }
    }
    qsort(samples, count, sizeof(double), compare);
    printf("{\"kind\":\"synthetic-d3d9\",\"pointerBits\":%u,\"width\":1280,\"height\":720,"
        "\"drawCallsPerFrame\":256,\"samples\":120,\"meanMs\":%.3f,\"p95Ms\":%.3f,\"fps\":%.2f,"
        "\"vendorID\":%lu,\"deviceID\":%lu}\n", (unsigned)(8*sizeof(void*)), total/count,
        samples[113], 1000.0*count/total, (unsigned long)adapter.VendorId, (unsigned long)adapter.DeviceId);
    IDirect3DQuery9_Release(completion); IDirect3DDevice9_Release(device);
    IDirect3D9_Release(api); DestroyWindow(window);
    return 0;
}
