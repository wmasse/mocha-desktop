// Prints "fullscreen" when the current space is a full-screen app, otherwise "desktop".
// Normal spaces always show the Dock's wallpaper window; full-screen spaces never do.
ObjC.import('CoreGraphics');
ObjC.import('Foundation');

var windows = ObjC.castRefToObject($.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, 0));
var desktop = false;
for (var i = 0; i < windows.count; i++) {
  var w = windows.objectAtIndex(i);
  if (ObjC.unwrap(w.objectForKey('kCGWindowOwnerName')) === 'Dock' &&
      ObjC.unwrap(w.objectForKey('kCGWindowLayer')) < -1000000000) {
    desktop = true;
    break;
  }
}
desktop ? 'desktop' : 'fullscreen';
