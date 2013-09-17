//
//  bellPlayer.m
//  bell
//
//  Created by AnakinGWY on 9/9/13.
//  Copyright (c) 2013 xiuxiude. All rights reserved.
//

#import "bellPlayer.h"

const NSTimeInterval timerInterval=0.1;
static BellPlayer *sharedPlayer;

enum BellFadingState {
  BellNoFadingState = 0,
  BellNewPlayItemFadingOutState = 1,
  BellPauseFadingOutState = 2,
  BellResumeFadingInState = 3,
  };

@interface BellPlayer()
{
  NSTimer *timer;
  AVPlayerItem *waitingItem;
  float volume;
  int fadeState;
}

@end

@implementation BellPlayer

@synthesize fadingTimeDuration = fadingTimeDuration;

+ (instancetype)sharedPlayer
{
  if (sharedPlayer == nil) {
    sharedPlayer = [[BellPlayer alloc] init];
  }
  return sharedPlayer;
}

- (id)init
{
  self = [super init];
  if (self) {
    fadeState = BellNoFadingState;
    fadingTimeDuration = 1.0;
    volume = 1;
  }
  return self;
}

- (void)pause
{
  if (self.rate == 0.0) return;
  if (OSAtomicCompareAndSwapInt(BellNoFadingState,
                                 BellPauseFadingOutState,
                                 &fadeState)) {
    [self triggerFading];
  }
}

- (void)play
{
  if (self.rate > 0.1) return;
  if (OSAtomicCompareAndSwapInt(BellNoFadingState,
                                BellResumeFadingInState,
                                &fadeState)) {
    [super play];
    [self triggerFading];
  }
}

- (void)playURL:(NSURL *)url
{
  waitingItem = [AVPlayerItem playerItemWithURL:url];
  if (self.rate > 0.0) {
    fadeState = BellNewPlayItemFadingOutState;
    [self triggerFading];
  }
  else {
    [super replaceCurrentItemWithPlayerItem: waitingItem];
    [super setVolume:volume];
    [super play];
  }
}

- (void)invalidateTimer
{
  if (timer) {
    CFRunLoopRemoveTimer(CFRunLoopGetMain(),
                         (__bridge CFRunLoopTimerRef)timer,
                         kCFRunLoopCommonModes);
    [timer invalidate];
    timer = nil;
  }
}

- (void)triggerFading
{
  [self invalidateTimer];
  
  if (fadingTimeDuration >= 0.1) {
    NSDictionary *info = @{@"state": @(fadeState)};
    timer = [NSTimer timerWithTimeInterval:timerInterval
                                    target:self
                                  selector:@selector(timerPulse:)
                                  userInfo:info
                                   repeats:YES];
    CFRunLoopAddTimer(CFRunLoopGetMain(),
                      (__bridge CFRunLoopTimerRef)timer,
                      kCFRunLoopCommonModes);
    [timer fire];
  }
  else {
    if (fadeState != BellResumeFadingInState)
      super.volume = 0.0;
    else
      super.volume = volume;
    [self fadingFinishedWithState:fadeState];
  }
}

- (float)volume
{
  return volume;
}

- (void)setVolume:(float)v
{
  volume = v;
  if (timer == nil) [super setVolume:v];
}

- (void)timerPulse:(NSTimer *)sender
{
  NSDictionary *info = sender.userInfo;
  int state = [[info objectForKey:@"state"] intValue];
  float step = volume * timerInterval / fadingTimeDuration;
  if (state != BellResumeFadingInState) {
    if (super.volume < step) {
      super.volume = 0.0;
      [self fadingFinishedWithState:state];
    }
    else {
      super.volume -= step;
    }
  }
  else {
    if (fabsf(super.volume - volume) <= step) {
      
      super.volume = volume;
      [self fadingFinishedWithState:state];
    }
    else {
      super.volume += step;
    }
  }
}

- (void)fadingFinishedWithState:(int) state
{
  [self invalidateTimer];
  switch (state) {
    case BellPauseFadingOutState:
      [super pause];
      break;
    case BellNewPlayItemFadingOutState:
      [super pause];
      [super replaceCurrentItemWithPlayerItem:waitingItem];
      [super setVolume:volume];
      [super play];
      break;
  }
  OSAtomicCompareAndSwapInt(state, BellNoFadingState, &fadeState);
}

@end