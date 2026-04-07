#import "BigYTMiniPlayer.h"

%group BigYTMiniPlayer // https://github.com/Galactic-Dev/BigYTMiniPlayer
%hook YTWatchMiniBarView
- (void)setWatchMiniPlayerLayout:(int)arg1 {
    %orig(1);
}
- (int)watchMiniPlayerLayout {
    return 1;
}
- (void)layoutSubviews {
    %orig;
    self.frame = CGRectMake(([UIScreen mainScreen].bounds.size.width - self.frame.size.width), self.frame.origin.y, self.frame.size.width, self.frame.size.height);
}
%end

%hook YTMainAppVideoPlayerOverlayView
- (BOOL)isUserInteractionEnabled {
    UIViewController *vc = [self _viewControllerForAncestor];
    while (vc) {
        if ([vc isKindOfClass:%c(YTWatchMiniBarViewController)]) {
            return [(YTWatchMiniBarViewController *)vc isActivated] ? NO : %orig;
        }
        vc = vc.parentViewController;
    }
    return %orig;
}
%end
%end

%ctor {
    if (IS_ENABLED(kBigYTMiniPlayer) && (UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPad)) {
        %init(BigYTMiniPlayer);
    }
}
