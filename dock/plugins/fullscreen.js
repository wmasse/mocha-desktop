// Prints "fullscreen" when the current space is a full-screen app, otherwise "desktop".
// Normal spaces always show a wallpaper window; full-screen spaces never do. Which
// process draws it depends on the macOS version: the Dock did up to macOS 26, and
// WindowManager does from macOS 27, next to Finder's desktop-icons window.
ObjC.import('CoreGraphics');
ObjC.import('Foundation');

var windows = ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, 0));
var desktop = false;
for (var i = 0; i < windows.count; i++) {
  var w = windows.objectAtIndex(i);
  var owner = ObjC.unwrap(w.objectForKey('kCGWindowOwnerName'));
  var name = ObjC.unwrap(w.objectForKey('kCGWindowName')) || '';
  if (ObjC.unwrap(w.objectForKey('kCGWindowLayer')) >= -1000000000) continue;
  if (owner === 'Dock' ||
      (owner === 'WindowManager' && name === 'Wallpaper') ||
      owner === 'Finder') {
    desktop = true;
    break;
  }
}
desktop ? 'desktop' : 'fullscreen';
