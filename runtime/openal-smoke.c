/* Silent 32-source playback and spatial-update regression probe; ten-second deadline. */
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <math.h>
typedef void* DEV;typedef void* CTX;
static DWORD WINAPI deadline(void *p){Sleep(10000);ExitProcess(124);return 0;}
#define FN(ret,name,args) ret (__cdecl *name)args = (void*)GetProcAddress(dll,#name); if(!name){printf("missing=%s\n",#name);return 3;}
int main(int argc,char **argv){const char *library=argc==2?argv[1]:"C:\\crossedover\\openal-soft.dll";CreateThread(NULL,0,deadline,NULL,0,NULL);HMODULE dll=LoadLibraryA(library);if(!dll){printf("load-error=%lu\n",GetLastError());return 3;}
FN(DEV,alcOpenDevice,(const char*));FN(int,alcCloseDevice,(DEV));FN(CTX,alcCreateContext,(DEV,const int*));FN(void,alcDestroyContext,(CTX));FN(int,alcMakeContextCurrent,(CTX));FN(const char*,alGetString,(int));FN(int,alGetError,(void));FN(void,alGenBuffers,(int,unsigned*));FN(void,alDeleteBuffers,(int,const unsigned*));FN(void,alBufferData,(unsigned,int,const void*,int,int));FN(void,alGenSources,(int,unsigned*));FN(void,alDeleteSources,(int,const unsigned*));FN(void,alSourcei,(unsigned,int,int));FN(void,alSource3f,(unsigned,int,float,float,float));FN(void,alSourcePlay,(unsigned));FN(void,alGetSourcef,(unsigned,int,float*));
DEV dev=alcOpenDevice(NULL);if(!dev){puts("device-open-failed");return 4;}CTX ctx=alcCreateContext(dev,NULL);if(!ctx||!alcMakeContextCurrent(ctx)){puts("context-failed");return 5;}
printf("vendor=%s renderer=%s version=%s\n",alGetString(0xb001),alGetString(0xb003),alGetString(0xb002));
short pcm[44100]={0};unsigned buf=0,sources[32]={0};alGenBuffers(1,&buf);alBufferData(buf,0x1101,pcm,sizeof(pcm),44100);alGenSources(32,sources);for(int i=0;i<32;i++){alSourcei(sources[i],0x1009,buf);alSourcei(sources[i],0x1007,1);alSource3f(sources[i],0x1004,i%8,0,-2);alSourcePlay(sources[i]);}
LARGE_INTEGER a,b,f;QueryPerformanceFrequency(&f);QueryPerformanceCounter(&a);for(int i=0;i<32000;i++)alSource3f(sources[i%32],0x1004,(float)(i%8),0,-2);QueryPerformanceCounter(&b);int err=alGetError();Sleep(250);float offset=0;alGetSourcef(sources[0],0x1024,&offset);printf("position-updates=32000 ms=%.3f error=%x playback-offset=%.4f valid=%d\n",(b.QuadPart-a.QuadPart)*1000.0/f.QuadPart,err,offset,!err&&offset>0);
alDeleteSources(32,sources);alDeleteBuffers(1,&buf);alcMakeContextCurrent(NULL);alcDestroyContext(ctx);alcCloseDevice(dev);return err||offset<=0?6:0;}
