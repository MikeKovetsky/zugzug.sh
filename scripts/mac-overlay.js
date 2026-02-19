#!/usr/bin/env osascript -l JavaScript
// mac-overlay.js — WC3-themed Cocoa overlay notification for macOS
// Usage: osascript -l JavaScript mac-overlay.js <message> <color> <icon_path> <slot> <dismiss_seconds> [category]
//
// JXA constraint: only one view per window may use layer.backgroundColor (CGColor).
// Additional colored elements use NSTextField with setDrawsBackground/setBackgroundColor.

ObjC.import('Cocoa');

function run(argv) {
  var message  = argv[0] || 'peon-ping';
  var color    = argv[1] || 'red';
  var iconPath = argv[2] || '';
  var slot     = parseInt(argv[3], 10) || 0;
  var dismiss  = parseFloat(argv[4]) || 4;
  var category = argv[5] || '';

  var acR = 180/255, acG = 30/255, acB = 30/255;
  switch (color) {
    case 'blue':   acR = 60/255;  acG = 130/255; acB = 220/255; break;
    case 'yellow': acR = 220/255; acG = 180/255; acB = 30/255;  break;
    case 'red':    acR = 180/255; acG = 30/255;  acB = 30/255;  break;
  }

  var isLoop = (category === 'resource.limit');
  var W = 520, H = 86;

  $.NSApplication.sharedApplication;
  $.NSApp.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  var screens = $.NSScreen.screens;
  var windows = [];

  for (var i = 0; i < screens.count; i++) {
    var vis = screens.objectAtIndex(i).visibleFrame;
    var yOff = 40 + slot * 96;
    var x = vis.origin.x + (vis.size.width - W) / 2;
    var y = vis.origin.y + vis.size.height - H - yOff;

    var win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
      $.NSMakeRect(x, y, W, H),
      $.NSWindowStyleMaskBorderless,
      $.NSBackingStoreBuffered,
      false
    );

    win.setBackgroundColor($.NSColor.clearColor);
    win.setOpaque(false);
    win.setAlphaValue(1.0);
    win.setLevel($.NSStatusWindowLevel);
    win.setIgnoresMouseEvents(true);
    win.setCollectionBehavior(
      $.NSWindowCollectionBehaviorCanJoinAllSpaces |
      $.NSWindowCollectionBehaviorStationary
    );

    var cv = win.contentView;
    cv.wantsLayer = true;

    // --- Dark WC3 panel (sole CGColor view) ---
    var panel = $.NSView.alloc.initWithFrame($.NSMakeRect(0, 0, W, H));
    panel.wantsLayer = true;
    panel.layer.backgroundColor =
      $.NSColor.colorWithSRGBRedGreenBlueAlpha(22/255, 18/255, 14/255, 0.96).CGColor;
    panel.layer.cornerRadius = 5;
    panel.layer.masksToBounds = true;
    cv.addSubview(panel);

    // Helper: colored bar via NSTextField (avoids CGColor crash)
    function addBar(fx, fy, fw, fh, nsColor) {
      var b = $.NSTextField.alloc.initWithFrame($.NSMakeRect(fx, fy, fw, fh));
      b.setBezeled(false);
      b.setEditable(false);
      b.setSelectable(false);
      b.setStringValue($(''));
      b.setDrawsBackground(true);
      b.setBackgroundColor(nsColor);
      panel.addSubview(b);
    }

    // Gold edge lines (top, bottom, right)
    var gold = $.NSColor.colorWithSRGBRedGreenBlueAlpha(180/255, 150/255, 45/255, 0.7);
    addBar(0, H - 2, W, 2, gold);
    addBar(0, 0, W, 2, gold);
    addBar(W - 2, 0, 2, H, gold);

    // Left accent bar (event color)
    var accent = $.NSColor.colorWithSRGBRedGreenBlueAlpha(acR, acG, acB, 1.0);
    addBar(0, 0, 5, H, accent);

    // --- Icon area ---
    var icoSz = 50, icoX = 16, icoY = (H - icoSz) / 2;
    var txtX = icoX;

    if (isLoop) {
      var emoji = $.NSTextField.alloc.initWithFrame(
        $.NSMakeRect(icoX + 2, icoY, icoSz, icoSz)
      );
      emoji.setStringValue($('\uD83D\uDCDC'));
      emoji.setBezeled(false);
      emoji.setDrawsBackground(true);
      emoji.setEditable(false);
      emoji.setSelectable(false);
      emoji.setBackgroundColor(
        $.NSColor.colorWithSRGBRedGreenBlueAlpha(28/255, 24/255, 18/255, 1.0)
      );
      emoji.setAlignment($.NSTextAlignmentCenter);
      emoji.setFont($.NSFont.systemFontOfSize(28));
      panel.addSubview(emoji);
      txtX = icoX + icoSz + 14;
    } else if (iconPath !== '' && $.NSFileManager.defaultManager.fileExistsAtPath(iconPath)) {
      var iconImage = $.NSImage.alloc.initWithContentsOfFile(iconPath);
      if (iconImage && !iconImage.isNil()) {
        var iv = $.NSImageView.alloc.initWithFrame(
          $.NSMakeRect(icoX, icoY, icoSz, icoSz)
        );
        iv.setImage(iconImage);
        iv.setImageScaling($.NSImageScaleProportionallyUpOrDown);
        panel.addSubview(iv);
        txtX = icoX + icoSz + 14;
      }
    }

    // --- Gold message text (Copperplate) ---
    var txtW = W - txtX - 16;
    var font = $.NSFont.fontWithNameSize($('Copperplate-Bold'), 15);
    if (!font || font.isNil()) font = $.NSFont.boldSystemFontOfSize(15);

    var th = font.ascender - font.descender + font.leading + 4;
    var ty = (H - th) / 2;
    var label = $.NSTextField.alloc.initWithFrame(
      $.NSMakeRect(txtX, ty, txtW, th)
    );
    label.setStringValue($(message));
    label.setBezeled(false);
    label.setDrawsBackground(false);
    label.setEditable(false);
    label.setSelectable(false);
    label.setTextColor(
      $.NSColor.colorWithSRGBRedGreenBlueAlpha(1, 215/255, 0, 1)
    );
    label.setAlignment($.NSTextAlignmentCenter);
    label.setFont(font);
    label.setLineBreakMode($.NSLineBreakByTruncatingTail);
    label.cell.setWraps(false);

    var shadow = $.NSShadow.alloc.init;
    shadow.setShadowOffset($.NSMakeSize(0, -1));
    shadow.setShadowBlurRadius(3);
    shadow.setShadowColor($.NSColor.blackColor);
    label.setShadow(shadow);

    panel.addSubview(label);

    win.orderFrontRegardless;
    windows.push(win);
  }

  $.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(
    dismiss, $.NSApp, 'terminate:', null, false
  );

  $.NSApp.run;
}
