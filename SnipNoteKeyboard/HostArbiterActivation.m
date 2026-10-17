// Enables UIKit's private keyboard arbiter so the keyboard can learn which app it types into
// (see HostAppResolver.swift). Personal build only: private API, never for the App Store.
//
// Adapted from Dictus, DictusKeyboard/HostArbiterActivation.m.
// Copyright (c) 2026 PIVI Solutions. MIT License. https://github.com/getdictus/dictus-ios
//
// It must run at load time: UIKit decides early whether the arbiter client exists, and
// enabling it from viewWillAppear stopped working in Dictus's device tests. It runs before
// everything else in the extension, so every step is nil-checked and it does no logging.

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

__attribute__((constructor))
static void SnipNoteEnableKeyboardArbiter(void) {
    Class cls = NSClassFromString(@"_UIKeyboardArbiterClient");
    if (cls == Nil) {
        return;
    }
    // +enabled is a class method, so its implementation lives on the metaclass.
    Method method = class_getClassMethod(cls, NSSelectorFromString(@"enabled"));
    if (method == NULL) {
        return;
    }
    method_setImplementation(method, imp_implementationWithBlock(^BOOL(id _self) {
        return YES;
    }));
}
