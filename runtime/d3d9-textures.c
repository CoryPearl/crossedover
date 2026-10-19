/* GPU readback for actual fixed-function draws, not just render-target clears.
 * Covers 2D and multiple volume slices in legacy color/luminance formats. */
#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#define CHECK(x) do {HRESULT h=(x);if(FAILED(h)){printf("FAIL %s %08lx\n",#x,(unsigned long)h);return 1;}}while(0)
static IDirect3DDevice9 *dev;
struct V {float x,y,z,rhw,u,v,w;};
static int render(IDirect3DBaseTexture9* tex,float z,DWORD expected,const char* name) {
 struct V q[]={{-.5,-.5,0,1,.5,.5,z},{15.5,-.5,0,1,.5,.5,z},{-.5,15.5,0,1,.5,.5,z},{15.5,15.5,0,1,.5,.5,z}};
 CHECK(IDirect3DDevice9_SetTexture(dev,0,tex));
 CHECK(IDirect3DDevice9_SetFVF(dev,D3DFVF_XYZRHW|D3DFVF_TEX1|D3DFVF_TEXCOORDSIZE3(0)));
 CHECK(IDirect3DDevice9_Clear(dev,0,NULL,D3DCLEAR_TARGET,0xff0000ff,1,0));
 CHECK(IDirect3DDevice9_BeginScene(dev));CHECK(IDirect3DDevice9_DrawPrimitiveUP(dev,D3DPT_TRIANGLESTRIP,2,q,sizeof(q[0])));CHECK(IDirect3DDevice9_EndScene(dev));
 IDirect3DSurface9 *rt=NULL,*cpu=NULL;D3DLOCKED_RECT r;
 CHECK(IDirect3DDevice9_GetRenderTarget(dev,0,&rt));
 CHECK(IDirect3DDevice9_CreateOffscreenPlainSurface(dev,16,16,D3DFMT_A8R8G8B8,D3DPOOL_SYSTEMMEM,&cpu,NULL));
 CHECK(IDirect3DDevice9_GetRenderTargetData(dev,rt,cpu));CHECK(IDirect3DSurface9_LockRect(cpu,&r,NULL,D3DLOCK_READONLY));
 DWORD actual=*(DWORD*)((char*)r.pBits+8*r.Pitch+8*4);int valid=(actual&0xffffff)==(expected&0xffffff);
 printf("%s expected=%08lx actual=%08lx valid=%d\n",name,(unsigned long)expected,(unsigned long)actual,valid);
 IDirect3DSurface9_UnlockRect(cpu);IDirect3DSurface9_Release(cpu);IDirect3DSurface9_Release(rt);
 return valid?0:1;
}
int main(void) {
 HWND win=CreateWindowA("STATIC","Texture diagnostic",WS_OVERLAPPEDWINDOW,0,0,64,64,NULL,NULL,GetModuleHandle(NULL),NULL);
 IDirect3D9* d=Direct3DCreate9(D3D_SDK_VERSION);if(!d)return 1;
 D3DPRESENT_PARAMETERS p={0};p.Windowed=TRUE;p.SwapEffect=D3DSWAPEFFECT_DISCARD;p.hDeviceWindow=win;p.BackBufferWidth=p.BackBufferHeight=16;p.BackBufferFormat=D3DFMT_A8R8G8B8;
 CHECK(IDirect3D9_CreateDevice(d,0,D3DDEVTYPE_HAL,win,D3DCREATE_HARDWARE_VERTEXPROCESSING,&p,&dev));
 IDirect3DDevice9_SetRenderState(dev,D3DRS_LIGHTING,FALSE);IDirect3DDevice9_SetRenderState(dev,D3DRS_ZENABLE,FALSE);IDirect3DDevice9_SetRenderState(dev,D3DRS_CULLMODE,D3DCULL_NONE);
 IDirect3DDevice9_SetTextureStageState(dev,0,D3DTSS_COLOROP,D3DTOP_SELECTARG1);IDirect3DDevice9_SetTextureStageState(dev,0,D3DTSS_COLORARG1,D3DTA_TEXTURE);
 IDirect3DDevice9_SetTextureStageState(dev,0,D3DTSS_ALPHAOP,D3DTOP_SELECTARG1);IDirect3DDevice9_SetTextureStageState(dev,0,D3DTSS_ALPHAARG1,D3DTA_TEXTURE);
 IDirect3DDevice9_SetSamplerState(dev,0,D3DSAMP_MINFILTER,D3DTEXF_POINT);IDirect3DDevice9_SetSamplerState(dev,0,D3DSAMP_MAGFILTER,D3DTEXF_POINT);
 int failures=0;
 D3DFORMAT formats[]={D3DFMT_A8R8G8B8,D3DFMT_X8R8G8B8,D3DFMT_R5G6B5,D3DFMT_L8,D3DFMT_A8L8,D3DFMT_A4R4G4B4};
 for(int f=0;f<6;f++) {
  int bpp=f<2?4:f==3?1:2;DWORD colors[]={0xffff0000,0xff00ff00};uint16_t packed[]={0xf800,0x07e0};uint16_t argb4444[]={0xff00,0xf0f0};uint16_t luminance[]={0xff00,0xffff};uint8_t gray[]={0,255};
  for(int volume=0;volume<2;volume++) {
   IDirect3DBaseTexture9* base=NULL;IDirect3DTexture9* tex=NULL;IDirect3DVolumeTexture9* vol=NULL;D3DLOCKED_RECT r;D3DLOCKED_BOX box;
   if(volume){CHECK(IDirect3DDevice9_CreateVolumeTexture(dev,2,2,2,1,0,formats[f],D3DPOOL_MANAGED,&vol,NULL));base=(IDirect3DBaseTexture9*)vol;CHECK(IDirect3DVolumeTexture9_LockBox(vol,0,&box,NULL,0));}
   else {CHECK(IDirect3DDevice9_CreateTexture(dev,2,2,1,0,formats[f],D3DPOOL_MANAGED,&tex,NULL));base=(IDirect3DBaseTexture9*)tex;CHECK(IDirect3DTexture9_LockRect(tex,0,&r,NULL,0));}
   for(int z=0;z<(volume?2:1);z++)for(int y=0;y<2;y++)for(int x=0;x<2;x++){
    void* ptr=volume?(char*)box.pBits+z*box.SlicePitch+y*box.RowPitch+x*bpp:(char*)r.pBits+y*r.Pitch+x*bpp;
    memcpy(ptr,f<2?(void*)&colors[z]:f==2?(void*)&packed[z]:f==3?(void*)&gray[z]:f==4?(void*)&luminance[z]:(void*)&argb4444[z],bpp);
   }
   if(volume)IDirect3DVolumeTexture9_UnlockBox(vol,0);else IDirect3DTexture9_UnlockRect(tex,0);
   for(int z=0;z<(volume?2:1);z++) {char name[80];snprintf(name,sizeof(name),"%s-format%d-slice%d",volume?"volume":"2D",(int)formats[f],z);failures+=render(base,z?.75:.25,(f<3||f==5)?colors[z]:z?0xffffffff:0xff000000,name);}
   IDirect3DDevice9_SetTexture(dev,0,NULL);IDirect3DBaseTexture9_Release(base);
  }
 }
 IDirect3DDevice9_Release(dev);IDirect3D9_Release(d);DestroyWindow(win);return failures?2:0;
}
