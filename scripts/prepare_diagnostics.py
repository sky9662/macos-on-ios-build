#!/usr/bin/env python3
"""Patch a disposable pinned upstream checkout for a separate diagnostic build."""
from pathlib import Path
import sys
root=Path(sys.argv[1]).resolve()
src=Path(__file__).resolve().parent.parent / "diagnostics"
def replace_once(path, old, new):
    text=path.read_text()
    if text.count(old)!=1:
        raise SystemExit(f"Unexpected upstream anchor in {path}: {old}")
    path.write_text(text.replace(old,new,1))
build=root/"probe/build.sh"
replace_once(build,"-framework QuartzCore macapp/main.m","-framework QuartzCore -framework OpenGL macapp/main.m macapp/tc_diagnostics.m")
replace_once(build,"-framework GameController ../shim/overrides/AppKit.m","-framework GameController -framework OpenGLES -framework UniformTypeIdentifiers ../shim/overrides/AppKit.m")
main=root/"probe/macapp/main.m"
replace_once(main,"@interface ProbeView : NSView","extern void TCMacDiagnostics(NSView *view);\n@interface ProbeView : NSView")
replace_once(main,'NSLog(@"PROBE mouseDown at %.0f,%.0f hue %.2f", p.x, p.y, _hue);','NSLog(@"PROBE mouseDown at %.0f,%.0f hue %.2f", p.x, p.y, _hue);\n    static BOOL tested=NO; if(!tested){tested=YES;TCMacDiagnostics(self);}')
(root/"probe/macapp/tc_diagnostics.m").write_text((src/"mac.m").read_text())
appkit=root/"shim/overrides/AppKit.m"
# Replace upstream's empty tracking area storage with actual storage methods.
replace_once(appkit, "- (void)addTrackingArea:(id)area {}", "- (void)addTrackingArea:(id)area { [self performSelector:@selector(tcAddTrackingArea:) withObject:area]; }")
replace_once(appkit, "- (void)removeTrackingArea:(id)area {}", "- (void)removeTrackingArea:(id)area { [self performSelector:@selector(tcRemoveTrackingArea:) withObject:area]; }")
replace_once(appkit, "- (NSArray *)trackingAreas { return @[]; }", "- (NSArray *)trackingAreas { return [self performSelector:@selector(tcTrackingAreas)]; }")
# Refresh the virtual cursor on the existing touch/hover event path.
replace_once(appkit, "static CGPoint gMouse;", "static CGPoint gMouse;\nstatic void tcCursorUpdate(void);")
replace_once(appkit, "gMouse = e.locationInWindow;", "gMouse = e.locationInWindow;\n    tcCursorUpdate();")
replace_once(appkit, "static void ShimDispatch(NSEvent *e);", "static void ShimDispatch(NSEvent *e);\nstatic void tcInstallControls(void);")
replace_once(appkit, "static CGPoint gMouse;", "static CGPoint gMouse;\nstatic NSUInteger tcControlPressedButtons(void);")
replace_once(appkit, "+ (NSUInteger)pressedMouseButtons { return 0; }", "+ (NSUInteger)pressedMouseButtons { return tcControlPressedButtons(); }")
replace_once(appkit, "    [gRootVC.view addSubview:v];", "    [gRootVC.view addSubview:v];\n    tcInstallControls();")
replace_once(appkit, "SHIM_FORWARD(rightMouseDown:) SHIM_FORWARD(rightMouseUp:)", "SHIM_FORWARD(rightMouseDown:) SHIM_FORWARD(rightMouseUp:) SHIM_FORWARD(rightMouseDragged:)")
replace_once(appkit, "case NSEventTypeLeftMouseDown: sel = @selector(mouseDown:); break;", "case NSEventTypeLeftMouseDown: sel = @selector(mouseDown:); break;\n        case 3: sel = @selector(rightMouseDown:); break;\n        case 4: sel = @selector(rightMouseUp:); break;\n        case 7: sel = @selector(rightMouseDragged:); break;")
appkit.write_text(appkit.read_text()+"\n"+(src/"appkit.m").read_text()+"\n"+(src/"display.m").read_text()+"\n"+(src/"ui_compat.m").read_text()+"\n"+(src/"cursor.m").read_text()+"\n"+(src/"panels.m").read_text()+"\n"+(src/"keyboard.m").read_text()+"\n"+(src/"events.m").read_text()+"\n"+(src/"input_math.h").read_text()+"\n"+(src/"controls.m").read_text())
