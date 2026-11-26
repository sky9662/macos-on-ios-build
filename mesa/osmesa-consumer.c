/* Independent compile-only consumer of the public OSMesa API.
 * Caller must supply a valid RGBA pixel buffer and dimensions.
 * The CI builds and links this object; it never executes it. */
#include <stddef.h>
#include <stdint.h>
typedef void *OSMesaContext;
typedef void (*OSMesaProc)(void);
extern OSMesaContext OSMesaCreateContextAttribs(const int *, OSMesaContext);
extern unsigned char OSMesaMakeCurrent(OSMesaContext, void *, unsigned, int, int);
extern OSMesaProc OSMesaGetProcAddress(const char *);
extern void OSMesaDestroyContext(OSMesaContext);
extern OSMesaContext OSMesaGetCurrentContext(void);
enum { TC_RGBA=0x1908,TC_UNSIGNED_BYTE=0x1401,TC_FORMAT=0x22,
       TC_PROFILE=0x33,TC_CORE=0x34,TC_MAJOR=0x36,TC_MINOR=0x37 };
int TCDesktopGLConsumer(void *pixels,size_t capacity,int width,int height) {
    if(!pixels||width<=0||height<=0||
       (size_t)width>SIZE_MAX/4/(size_t)height||
       capacity<(size_t)width*(size_t)height*4)return 0;
    const int attrs[]={TC_FORMAT,TC_RGBA,TC_PROFILE,TC_CORE,TC_MAJOR,3,TC_MINOR,3,0};
    OSMesaContext ctx=OSMesaCreateContextAttribs(attrs,NULL);
    if(!ctx)return 0;
    int ok=OSMesaMakeCurrent(ctx,pixels,TC_UNSIGNED_BYTE,width,height)&&OSMesaGetCurrentContext()==ctx;
    if(ok)ok=OSMesaGetProcAddress("glGetString")!=NULL &&
             OSMesaGetProcAddress("glTexBuffer")!=NULL &&
             OSMesaGetProcAddress("glDrawElementsBaseVertex")!=NULL &&
             OSMesaGetProcAddress("glPolygonMode")!=NULL;
    OSMesaMakeCurrent(NULL,NULL,0,0,0);
    OSMesaDestroyContext(ctx);
    return ok;
}
