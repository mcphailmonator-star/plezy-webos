// Copyright (c) 2026 LG Electronics, Inc. All rights reserved.
// Copyright 2021 Sony Corporation. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include <flutter_window.h>

#include "flutter/generated_plugin_registrant.h"

class App : public FlutterWindow {
 public:
  bool OnCreate() override {
    if (!FlutterWindow::OnCreate()) return false;
    RegisterPlugins(GetRegistrar());
    return true;
  }

 protected:
  void OnBuildViewProperties(
      flutter::FlutterViewController::ViewProperties& vp) override {
    // ELinuxWindowWayland::GetPhysicalWindowBounds multiplies 1920x1080 by
    // scale_factor; 1.0 gives a native 1920x1080 EGL surface (2.25x fewer
    // pixels than 2880x1620) while PlezyWebosFlutterBinding preserves 1280x720
    // logical sizing via effectiveDpr = physWidth / 1280.0.
    vp.force_scale_factor = true;
    vp.scale_factor = 1.0;
  }
};

int main(int argc, char** argv) {
  App app;
  return app.Run(argc, argv);
}
