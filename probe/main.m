#import <UIKit/UIKit.h>
#import <GLKit/GLKit.h>
#import <OpenGLES/ES3/gl.h>
static GLuint shader(GLenum type, const char *source) {
    GLuint s=glCreateShader(type); glShaderSource(s,1,&source,NULL); glCompileShader(s);
    GLint ok=0; glGetShaderiv(s,GL_COMPILE_STATUS,&ok);
    if(!ok){char log[1024]={0};glGetShaderInfoLog(s,sizeof(log),NULL,log);NSLog(@"PROBE shader error: %s",log);glDeleteShader(s);return 0;}
    return s;
}
@interface ProbeController : GLKViewController
@end
@implementation ProbeController {
    GLuint program, vao, vbo;
}
- (void)loadView {
    EAGLContext *ctx=[[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if(!ctx){self.view=[[UIView alloc] init]; self.view.backgroundColor=UIColor.redColor; NSLog(@"PROBE no ES3 context");return;}
    GLKView *v=[[GLKView alloc] initWithFrame:CGRectZero context:ctx]; v.delegate=self; self.view=v;
    [EAGLContext setCurrentContext:ctx];
    NSLog(@"PROBE GL_VERSION=%s GLSL=%s",glGetString(GL_VERSION),glGetString(GL_SHADING_LANGUAGE_VERSION));
    GLuint vs=shader(GL_VERTEX_SHADER,"#version 300 es\nlayout(location=0) in vec2 pos; void main(){gl_Position=vec4(pos,0,1);}");
    GLuint fs=shader(GL_FRAGMENT_SHADER,"#version 300 es\nprecision highp float; out vec4 color; void main(){color=vec4(0.2,0.9,0.5,1);}");
    if(!vs||!fs)return;
    program=glCreateProgram();glAttachShader(program,vs);glAttachShader(program,fs);glLinkProgram(program);
    GLint ok=0;glGetProgramiv(program,GL_LINK_STATUS,&ok);
    if(!ok){char log[1024]={0};glGetProgramInfoLog(program,sizeof(log),NULL,log);NSLog(@"PROBE link error: %s",log);glDeleteProgram(program);program=0;return;}
    glDeleteShader(vs);glDeleteShader(fs);
    const GLfloat vertices[]={0.0f,0.65f,-0.65f,-0.65f,0.65f,-0.65f};
    glGenVertexArrays(1,&vao);glBindVertexArray(vao);glGenBuffers(1,&vbo);glBindBuffer(GL_ARRAY_BUFFER,vbo);
    glBufferData(GL_ARRAY_BUFFER,sizeof(vertices),vertices,GL_STATIC_DRAW);glVertexAttribPointer(0,2,GL_FLOAT,GL_FALSE,0,NULL);glEnableVertexAttribArray(0);
}
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    glViewport(0,0,(GLsizei)view.drawableWidth,(GLsizei)view.drawableHeight);
    glClearColor(program?0.06f:0.65f,0.08f,0.15f,1);glClear(GL_COLOR_BUFFER_BIT);
    if(program){glUseProgram(program);glBindVertexArray(vao);glDrawArrays(GL_TRIANGLES,0,3);}
    static BOOL first=YES;if(first){NSLog(@"PROBE first frame program=%u GL error=0x%x",program,glGetError());first=NO;}
}
@end
@interface ProbeScene : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation ProbeScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if(![scene isKindOfClass:UIWindowScene.class])return;
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];self.window.rootViewController=[[ProbeController alloc] init];[self.window makeKeyAndVisible];
}
@end
@interface ProbeApp : UIResponder <UIApplicationDelegate>
@end
@implementation ProbeApp
@end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(ProbeApp.class));}}
