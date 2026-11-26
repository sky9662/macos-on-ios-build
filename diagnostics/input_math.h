#include <math.h>
static double tcClamp(double v,double lo,double hi){return fmin(hi,fmax(lo,v));}
static double tcPointerGain(double speed,double sensitivity,double acceleration){
    if(!isfinite(speed)||!isfinite(sensitivity)||!isfinite(acceleration))return 1;
    return tcClamp(sensitivity,0.25,3)*(1+tcClamp(acceleration,0,2)*tcClamp(speed/1000,0,1));
}
static double tcPointerAxis(double position,double delta,double gain,double extent){
    if(!isfinite(extent)||extent<=0)return 0;
    if(!isfinite(position))position=0;
    if(!isfinite(delta)||!isfinite(gain))return tcClamp(position,0,extent);
    return tcClamp(position+delta*gain,0,extent);
}

/* Three overlay key slots. One key-down per HID usage; release only after
 * the last slot holding that usage is released. Zero means no event. */
enum { TCKeySlotCount=3 };
typedef struct { int held[TCKeySlotCount]; } TCKeyState;
static int tcKeyAllowed(int hid){
    return (hid>=4&&hid<=39)||hid==40||hid==41||hid==42||hid==43||hid==44||(hid>=79&&hid<=82);
}
static int tcKeyDown(TCKeyState *state,int slot,int hid){
    if(slot<0||slot>=TCKeySlotCount||!tcKeyAllowed(hid)||state->held[slot])return 0;
    int duplicate=0;
    for(int i=0;i<TCKeySlotCount;i++)if(state->held[i]==hid)duplicate=1;
    state->held[slot]=hid;
    return duplicate?0:hid;
}
static int tcKeyUp(TCKeyState *state,int slot){
    if(slot<0||slot>=TCKeySlotCount)return 0;
    int hid=state->held[slot];state->held[slot]=0;
    if(!hid)return 0;
    for(int i=0;i<TCKeySlotCount;i++)if(state->held[i]==hid)return 0;
    return hid;
}

/* Normalize center within the usable travel span, not the entire screen. */
static double tcLayoutCenter(double normalized,double origin,double extent,double size){
    if(!isfinite(origin))origin=0;
    if(!isfinite(extent)||extent<=0)return origin;
    if(!isfinite(size)||size<0)size=0;
    size=fmin(size,extent);
    if(!isfinite(normalized))normalized=0.5;
    return origin+size/2+tcClamp(normalized,0,1)*(extent-size);
}
static double tcLayoutFraction(double center,double origin,double extent,double size){
    if(!isfinite(center)||!isfinite(origin)||!isfinite(extent)||!isfinite(size)||size<0||extent<=size)return 0.5;
    return tcClamp((center-origin-size/2)/(extent-size),0,1);
}
