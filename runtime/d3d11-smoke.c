#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>

#define CHECK(call) do { HRESULT hr_ = (call); if (FAILED(hr_)) { fprintf(stderr, "%s failed: 0x%08lx\n", #call, (unsigned long)hr_); return 1; } } while(0)
int main(void) {
    ID3D11Device *device = NULL; ID3D11DeviceContext *context = NULL;
    D3D_FEATURE_LEVEL level, requested[] = {D3D_FEATURE_LEVEL_11_0};
    CHECK(D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, requested, 1, D3D11_SDK_VERSION, &device, &level, &context));
    D3D11_TEXTURE2D_DESC description = {0};
    description.Width = description.Height = 16; description.MipLevels = description.ArraySize = 1;
    description.Format = DXGI_FORMAT_R8G8B8A8_UNORM; description.SampleDesc.Count = 1;
    description.Usage = D3D11_USAGE_DEFAULT; description.BindFlags = D3D11_BIND_RENDER_TARGET;
    ID3D11Texture2D *target = NULL, *staging = NULL; ID3D11RenderTargetView *view = NULL;
    CHECK(ID3D11Device_CreateTexture2D(device, &description, NULL, &target));
    CHECK(ID3D11Device_CreateRenderTargetView(device, (ID3D11Resource *)target, NULL, &view));
    const FLOAT color[] = {0.25f, 0.5f, 0.75f, 1.0f};
    ID3D11DeviceContext_ClearRenderTargetView(context, view, color);
    description.Usage = D3D11_USAGE_STAGING; description.BindFlags = 0; description.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    CHECK(ID3D11Device_CreateTexture2D(device, &description, NULL, &staging));
    ID3D11DeviceContext_CopyResource(context, (ID3D11Resource *)staging, (ID3D11Resource *)target);
    D3D11_MAPPED_SUBRESOURCE mapped;
    CHECK(ID3D11DeviceContext_Map(context, (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &mapped));
    unsigned char *pixel = mapped.pData;
    int valid = pixel[0] >= 62 && pixel[0] <= 65 && pixel[1] >= 126 && pixel[1] <= 129 && pixel[2] >= 189 && pixel[2] <= 193 && pixel[3] == 255;
    printf("{\"api\":\"d3d11\",\"pointerBits\":%u,\"readback\":[%u,%u,%u,%u],\"valid\":%s}\n", (unsigned)(8 * sizeof(void *)), pixel[0], pixel[1], pixel[2], pixel[3], valid ? "true" : "false");
    ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)staging, 0);
    ID3D11RenderTargetView_Release(view); ID3D11Texture2D_Release(staging); ID3D11Texture2D_Release(target);
    ID3D11DeviceContext_Release(context); ID3D11Device_Release(device);
    return valid ? 0 : 2;
}
