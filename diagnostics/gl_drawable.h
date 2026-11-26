#ifndef TC_GL_DRAWABLE_H
#define TC_GL_DRAWABLE_H
/* Only the emulated double-buffered default drawable needs remapping.
 * Values are shared by desktop OpenGL and GLES; no GL headers for unit tests. */
enum { TC_GL_NONE=0, TC_GL_BACK=0x0405, TC_GL_COLOR_ATTACHMENT0=0x8ce0 };
static inline unsigned tcGLBufferToNative(unsigned selection, int virtualDefault) {
    return virtualDefault && selection==TC_GL_BACK ? TC_GL_COLOR_ATTACHMENT0 : selection;
}
static inline unsigned tcGLBufferToDesktop(unsigned selection, int virtualDefault) {
    return virtualDefault && selection==TC_GL_COLOR_ATTACHMENT0 ? TC_GL_BACK : selection;
}
/* Desktop glMapBuffer access -> GLES glMapBufferRange flags. */
static inline unsigned tcGLMapAccess(unsigned mode) {
    switch(mode) {
        case 0x88b8: return 0x0001; /* GL_READ_ONLY */
        case 0x88b9: return 0x0002; /* GL_WRITE_ONLY */
        case 0x88ba: return 0x0003; /* GL_READ_WRITE */
        default: return 0;
    }
}
/* Desktop polygon fill is already the GLES triangle rasterization mode.
 * Non-fill modes need a different rasterizer; never report them as supported. */
static inline unsigned tcGLPolygonModeError(unsigned face, unsigned mode) {
    if(face!=0x0404 && face!=0x0405 && face!=0x0408)return 0x0500;
    if(mode==0x1b02)return 0;
    if(mode==0x1b00 || mode==0x1b01)return 0x0502;
    return 0x0500;
}
#endif
