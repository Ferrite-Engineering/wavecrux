// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

#import "WCXFoldPlugin.h"

#import <UIKit/UIKit.h>

// The hinge and reserved-region APIs arrived in the iOS 27.1 SDK. Building
// with an older Xcode (a CI runner that has not caught up) compiles the
// fallback below, which reports "no hinge", instead of failing the build.
#if __has_include(<UIKit/UIHingeInteraction.h>) && \
    __has_include(<UIKit/UIViewReservedRegion.h>)
#define WCX_HAS_HINGE_SDK 1
#else
#define WCX_HAS_HINGE_SDK 0
#endif

/// A transparent, non-interactive view stretched over the Flutter view. It
/// hosts the hinge interaction and, because UIKit has no change notification
/// for reserved regions, its layout pass is the cue to read the crease again.
@interface WCXFoldProbeView : UIView
@property(nonatomic, copy, nullable) void (^onLayout)(void);
@end

@implementation WCXFoldProbeView
- (void)layoutSubviews {
  [super layoutSubviews];
  if (self.onLayout) self.onLayout();
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
  return nil;
}
@end

@interface WCXFoldPlugin () <FlutterStreamHandler>
@property(nonatomic, copy, nullable) FlutterEventSink sink;
@property(nonatomic, strong, nullable) WCXFoldProbeView *probe;
@property(nonatomic, strong, nullable) id<UIInteraction> interaction;
@property(nonatomic, copy, nullable) NSDictionary *lastSent;
@property(nonatomic, copy) NSString *status;
@property(nonatomic, strong, nullable) NSNumber *angleDegrees;
@property(nonatomic) NSInteger attachAttempts;
@end

@implementation WCXFoldPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterEventChannel *channel =
      [FlutterEventChannel eventChannelWithName:@"com.wavecrux/fold"
                                binaryMessenger:[registrar messenger]];
  WCXFoldPlugin *instance = [[WCXFoldPlugin alloc] init];
  instance.status = @"none";
  [channel setStreamHandler:instance];
}

#pragma mark - FlutterStreamHandler

- (FlutterError *)onListenWithArguments:(id)arguments
                              eventSink:(FlutterEventSink)events {
  self.sink = events;
  self.lastSent = nil;
  self.attachAttempts = 0;
  [self attach];
  return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
  [self detach];
  self.sink = nil;
  return nil;
}

#pragma mark - Attaching

/// The Flutter view of the foreground scene's key window.
- (UIView *)hostView {
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:[UIWindowScene class]]) continue;
    if (scene.activationState == UISceneActivationStateUnattached) continue;
    UIWindowScene *windowScene = (UIWindowScene *)scene;
    UIWindow *window = windowScene.keyWindow ?: windowScene.windows.firstObject;
    UIViewController *root = window.rootViewController;
    if ([root isKindOfClass:[FlutterViewController class]]) return root.view;
    if (root.view != nil) return root.view;
  }
  return nil;
}

- (void)attach {
#if WCX_HAS_HINGE_SDK
  if (@available(iOS 27.1, *)) {
    UIView *host = [self hostView];
    if (host == nil) {
      // Dart can subscribe before the window is key; try again shortly.
      if (self.attachAttempts++ < 40 && self.sink != nil) {
        __weak WCXFoldPlugin *weakSelf = self;
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{
              [weakSelf attach];
            });
      } else {
        [self sendNoHinge];
      }
      return;
    }
    WCXFoldProbeView *probe = [[WCXFoldProbeView alloc] initWithFrame:host.bounds];
    probe.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    probe.userInteractionEnabled = NO;
    probe.backgroundColor = UIColor.clearColor;
    probe.isAccessibilityElement = NO;
    probe.accessibilityElementsHidden = YES;
    [host addSubview:probe];
    self.probe = probe;

    __weak WCXFoldPlugin *weakSelf = self;
    probe.onLayout = ^{
      [weakSelf emit];
    };
    UIHingeInteraction *hinge = [[UIHingeInteraction alloc]
        initWithUpdateHandler:^(UIHingeInteraction *interaction,
                                UIHingeInteractionUpdate *update) {
          WCXFoldPlugin *strongSelf = weakSelf;
          if (strongSelf == nil) return;
          [strongSelf applyHinge:update.hinge];
        }];
    [probe addInteraction:hinge];
    self.interaction = hinge;
    [self emit];
    return;
  }
#endif
  [self sendNoHinge];
}

- (void)detach {
  if (self.interaction != nil && self.probe != nil) {
    [self.probe removeInteraction:self.interaction];
  }
  self.probe.onLayout = nil;
  [self.probe removeFromSuperview];
  self.probe = nil;
  self.interaction = nil;
}

#pragma mark - State

#if WCX_HAS_HINGE_SDK
- (void)applyHinge:(UIHinge *)hinge API_AVAILABLE(ios(27.1)) {
  if (hinge == nil) {
    self.status = @"none";
    self.angleDegrees = nil;
  } else {
    switch (hinge.status) {
      case UIHingeStatusClosed:
        self.status = @"closed";
        break;
      case UIHingeStatusPartiallyOpen:
        self.status = @"partiallyOpen";
        break;
      case UIHingeStatusFullyOpen:
        self.status = @"fullyOpen";
        break;
      default:
        self.status = @"none";
        break;
    }
    // UIKit reports radians; Dart works in degrees, 0 shut to 180 flat.
    self.angleDegrees = @(hinge.angle * 180.0 / M_PI);
  }
  [self emit];
  // Reserved regions trail the hinge by a few frames; read them again once
  // they have settled so the crease is not missed (or kept) for a whole
  // posture.
  __weak WCXFoldPlugin *weakSelf = self;
  for (NSNumber *delay in @[ @0.12, @0.35 ]) {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW,
                      (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
          [weakSelf emit];
        });
  }
}
#endif

- (NSArray<NSNumber *> *)currentCrease {
#if WCX_HAS_HINGE_SDK
  if (@available(iOS 27.1, *)) {
    if (self.probe == nil) return nil;
    NSArray<UIViewReservedRegion *> *regions = [self.probe
        reservedRegionsOfKind:[UIViewReservedRegionKind divisionRegionKind]];
    for (UIViewReservedRegion *region in regions) {
      if (!region.isActive) continue;
      CGRect f = region.frame;
      if (f.size.width <= 0 || f.size.height <= 0) continue;
      return @[ @(f.origin.x), @(f.origin.y), @(f.size.width), @(f.size.height) ];
    }
  }
#endif
  return nil;
}

- (void)emit {
  if (self.sink == nil) return;
  NSMutableDictionary *event = [NSMutableDictionary dictionary];
  event[@"status"] = self.status ?: @"none";
  if (self.angleDegrees != nil) event[@"angle"] = self.angleDegrees;
  NSArray<NSNumber *> *crease = [self currentCrease];
  if (crease != nil) event[@"crease"] = crease;
  if ([event isEqualToDictionary:self.lastSent ?: @{}]) return;
  self.lastSent = event;
  self.sink(event);
}

- (void)sendNoHinge {
  if (self.sink == nil) return;
  self.lastSent = @{@"status" : @"none"};
  self.sink(self.lastSent);
}

@end
