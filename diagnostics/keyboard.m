// Virtual ANSI key-name layout for GLFW. Real typed text still comes from UIKey.
// No system keyboard layout access, dead-key composition or event interception.
#import <Foundation/Foundation.h>
#import <stdint.h>
#import <string.h>
#define TCK_EXPORT __attribute__((visibility("default")))
static const unsigned char tcLayoutMarker[]={'T','C','A','N','S','I','0','1'};
TCK_EXPORT const CFStringRef kTISPropertyUnicodeKeyLayoutData=CFSTR("TISPropertyUnicodeKeyLayoutData");
TCK_EXPORT CFTypeRef TISCopyCurrentKeyboardLayoutInputSource(void){
    NSData *data=[NSData dataWithBytes:tcLayoutMarker length:sizeof(tcLayoutMarker)];
    return CFBridgingRetain(@{(__bridge NSString *)kTISPropertyUnicodeKeyLayoutData:data});
}
TCK_EXPORT const void *TISGetInputSourceProperty(CFTypeRef source,CFStringRef key){
    if(!source||!key||CFGetTypeID(source)!=CFDictionaryGetTypeID())return NULL;
    return CFDictionaryGetValue((CFDictionaryRef)source,key);
}
// Apple virtual key positions, explicitly ANSI US, not user's current layout.
static const char tcANSI[128]={
 [0]='a',[1]='s',[2]='d',[3]='f',[4]='h',[5]='g',[6]='z',[7]='x',[8]='c',[9]='v',
 [11]='b',[12]='q',[13]='w',[14]='e',[15]='r',[16]='y',[17]='t',[18]='1',[19]='2',
 [20]='3',[21]='4',[22]='6',[23]='5',[24]='=',[25]='9',[26]='7',[27]='-',[28]='8',
 [29]='0',[30]=']',[31]='o',[32]='u',[33]='[',[34]='i',[35]='p',[36]='\r',[37]='l',
 [38]='j',[39]='\'',[40]='k',[41]=';',[42]='\\',[43]=',',[44]='/',[45]='n',[46]='m',
 [47]='.',[48]='\t',[49]=' ',[50]='\x60',[51]='\b',[53]=27,[65]='.',[67]='*',
 [69]='+',[75]='/',[76]='\r',[78]='-',[81]='=',[82]='0',[83]='1',[84]='2',[85]='3',
 [86]='4',[87]='5',[88]='6',[89]='7',[91]='8',[92]='9'
};
TCK_EXPORT int32_t UCKeyTranslate(const void *layout,uint16_t key,uint16_t action,uint32_t modifiers,uint32_t keyboardType,uint32_t options,uint32_t *deadState,uint32_t maxLength,uint32_t *actualLength,uint16_t *chars){
    if(actualLength)*actualLength=0;
    if(!layout||memcmp(layout,tcLayoutMarker,sizeof(tcLayoutMarker))||!actualLength||!chars||key>=128||action>3||!maxLength)return -50;
    // Reject unsupported modifier/dead-key translation instead of fabricating text.
    if((deadState&&*deadState)||(modifiers&~6u))return -50;
    char c=tcANSI[key];if(!c)return 0;
    BOOL shift=(modifiers&2)!=0,caps=(modifiers&4)!=0;
    if(c>='a'&&c<='z'){if(shift!=caps)c-=32;}
    else if(shift){
        const char *plain="1234567890-=[]\\;',./\x60";
        const char *upper="!@#$%^&*()_+{}|:\"<>?~";
        const char *p=strchr(plain,c);if(p)c=upper[p-plain];
    }
    chars[0]=(uint16_t)(unsigned char)c;*actualLength=1;
    if(deadState)*deadState=0;return 0;
}
