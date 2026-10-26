/* wine-crossover CI: create a D3D11 device, clear a render target on the GPU
 * and read the pixel back. Prints "d3d11-ok" plus the adapter on success. */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>

static int fail(const char *what, HRESULT hr)
{
    printf("d3d11-fail %s hr=0x%08lx\n", what, (unsigned long)hr);
    return 1;
}

int main(void)
{
    ID3D11Device *dev;
    ID3D11DeviceContext *ctx;
    D3D_FEATURE_LEVEL fl;
    IDXGIDevice *dxgi_dev;
    IDXGIAdapter *adapter;
    DXGI_ADAPTER_DESC desc;
    D3D11_TEXTURE2D_DESC td = {0};
    ID3D11Texture2D *rt, *staging;
    ID3D11RenderTargetView *rtv;
    D3D11_MAPPED_SUBRESOURCE map;
    static const float color[4] = {1.0f, 0.0f, 1.0f, 1.0f};
    DWORD pixel;
    HRESULT hr;

    hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                           D3D11_SDK_VERSION, &dev, &fl, &ctx);
    if (FAILED(hr)) return fail("D3D11CreateDevice", hr);

    hr = ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void **)&dxgi_dev);
    if (FAILED(hr)) return fail("IDXGIDevice", hr);
    IDXGIDevice_GetAdapter(dxgi_dev, &adapter);
    IDXGIAdapter_GetDesc(adapter, &desc);

    td.Width = td.Height = 4;
    td.MipLevels = td.ArraySize = 1;
    td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    td.SampleDesc.Count = 1;
    td.Usage = D3D11_USAGE_DEFAULT;
    td.BindFlags = D3D11_BIND_RENDER_TARGET;
    hr = ID3D11Device_CreateTexture2D(dev, &td, NULL, &rt);
    if (FAILED(hr)) return fail("CreateTexture2D", hr);
    hr = ID3D11Device_CreateRenderTargetView(dev, (ID3D11Resource *)rt, NULL, &rtv);
    if (FAILED(hr)) return fail("CreateRenderTargetView", hr);

    td.Usage = D3D11_USAGE_STAGING;
    td.BindFlags = 0;
    td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    hr = ID3D11Device_CreateTexture2D(dev, &td, NULL, &staging);
    if (FAILED(hr)) return fail("CreateTexture2D staging", hr);

    ID3D11DeviceContext_ClearRenderTargetView(ctx, rtv, color);
    ID3D11DeviceContext_CopyResource(ctx, (ID3D11Resource *)staging, (ID3D11Resource *)rt);
    hr = ID3D11DeviceContext_Map(ctx, (ID3D11Resource *)staging, 0, D3D11_MAP_READ, 0, &map);
    if (FAILED(hr)) return fail("Map", hr);
    pixel = *(DWORD *)map.pData;
    ID3D11DeviceContext_Unmap(ctx, (ID3D11Resource *)staging, 0);

    if (pixel != 0xffff00ff) {
        printf("d3d11-fail pixel=0x%08lx (want 0xffff00ff)\n", (unsigned long)pixel);
        return 1;
    }
    printf("d3d11-ok feature_level=0x%x adapter=%ls\n", (unsigned)fl, desc.Description);
    return 0;
}
