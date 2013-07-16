/*
 Copyright 2009-2013 Urban Airship Inc. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 
 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.
 
 2. Redistributions in binaryform must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided withthe distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC ``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/* UAInboxOverlayController is based on MTPopupWindow
 * http://www.touch-code-magazine.com/showing-a-popup-window-in-ios-class-for-download/
 *
 * Copyright 2011 Marin Todorov. MIT license
 * http://www.opensource.org/licenses/mit-license.php
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of this software
 * and associated documentation files (the "Software"), to deal in the Software without restriction,
 * including without limitation the rights to use, copy, modify, merge, publish, distribute,
 * sublicense, and/or sell copies of the Software, and to permit persons to whom the Software
 * is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all copies or
 * substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
 * BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
 * DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#import "UAInboxOverlayController.h"
#import "UAInboxMessage.h"
#import "UAInboxMessageList.h"
#import "UAInbox.h"
#import "UAInboxUI.h"
#import "UAUtils.h"

#import <QuartzCore/QuartzCore.h>

#define kShadeViewTag 1000

static NSMutableSet *overlayControllers = nil;

@interface UAInboxOverlayController()

- (id)initWithParentViewController:(UIViewController *)parent andMessageID:(NSString*)messageID;
- (void)loadMessageAtIndex:(int)index;
- (void)loadMessageForID:(NSString *)mid;
- (void)displayWindow;
- (void)closePopupWindow;

@property(nonatomic, retain) UIViewController *parentViewController;
@property(nonatomic, retain) UIView *bgView;
@property(nonatomic, retain) UIView *bigPanelView;
@property(nonatomic, retain) UABeveledLoadingIndicator *loadingIndicator;
@end

@implementation UAInboxOverlayController

// Setup a container for the newly allocated controllers, will be released by OS. 
+ (void)initialize {
    if (self == [UAInboxOverlayController class]){
        overlayControllers = [[NSMutableSet alloc] initWithCapacity:1];
    }
}

// While this breaks from convention, it does not actually leak. Turning off analyzer warnings
+ (void)showWindowInsideViewController:(UIViewController *)viewController withMessageID:(NSString *)messageID {
    UAInboxOverlayController *overlayController = [[[UAInboxOverlayController alloc] initWithParentViewController:viewController andMessageID:messageID] autorelease];
    [overlayControllers addObject:overlayController];
}


- (id)initWithParentViewController:(UIViewController *)parent andMessageID:(NSString*)messageID {
    self = [super init];
    if (self) {
        // Initialization code here.
        
        self.parentViewController = parent;
        UIView *sview = parent.view;
        
        self.bgView = [[[UIView alloc] initWithFrame: sview.bounds] autorelease];
        self.bgView.autoresizesSubviews = YES;
        self.bgView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        [sview addSubview: self.bgView];
        
        //set the frame later
        self.webView = [[[UIWebView alloc] initWithFrame:CGRectZero] autorelease];
        self.webView.backgroundColor = [UIColor clearColor];
        self.webView.opaque = NO;
        self.webView.delegate = self;
        
        //hack to hide the ugly webview gradient
        for (UIView* subView in [self.webView subviews]) {
            if ([subView isKindOfClass:[UIScrollView class]]) {
                for (UIView* shadowView in [subView subviews]) {
                    if ([shadowView isKindOfClass:[UIImageView class]]) {
                        [shadowView setHidden:YES];
                    }
                }
            }
        }
        
        self.loadingIndicator = [UABeveledLoadingIndicator indicator];
                
        //required to receive orientation updates from NSNotificationCenter
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(orientationChanged:) 
                                                     name:UIDeviceOrientationDidChangeNotification object:nil];
        
        [self loadMessageForID:messageID];
        
    }
    
    return self;
}

- (void)dealloc {
    self.message = nil;
    self.webView = nil;
    self.parentViewController = nil;
    self.loadingIndicator = nil;
    self.bgView = nil;
    self.bigPanelView = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIDeviceOrientationDidChangeNotification
                                                  object:nil];
    [super dealloc];
}

- (void)loadMessageAtIndex:(int)index {
    self.message = [[UAInbox shared].messageList messageAtIndex:index];
    if (self.message == nil) {
        UALOG(@"Can not find message with index: %d", index);
        [self closePopupWindow];
        return;
    }
    
    NSMutableURLRequest *requestObj = [NSMutableURLRequest requestWithURL: self.message.messageBodyURL];
    NSString *auth = [UAUtils userAuthHeaderString];
    
    [requestObj setValue:auth forHTTPHeaderField:@"Authorization"];
    [requestObj setTimeoutInterval:5];
    
    [self.webView stopLoading];
    [self.webView loadRequest:requestObj];
    [self performSelector:@selector(displayWindow) withObject:nil afterDelay:0.1];
}

- (void)loadMessageForID:(NSString *)mid {
    UAInboxMessage *msg = [[UAInbox shared].messageList messageForID:mid];
    if (msg == nil) {
        UALOG(@"Can not find message with ID: %@", mid);
        [self closePopupWindow];
        return;
    }
    
    [self loadMessageAtIndex:[[UAInbox shared].messageList indexOfMessage:msg]];
}

- (BOOL)shouldTransition {
    return [UIView respondsToSelector:@selector(transitionFromView:toView:duration:options:completion:)];
}

- (void)constructWindow {
    
    //the new panel
    self.bigPanelView = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, self.bgView.frame.size.width, self.bgView.frame.size.height)]
                         autorelease];
    
    self.bigPanelView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.bigPanelView.autoresizesSubviews = YES;
    self.bigPanelView.center = CGPointMake( self.bgView.frame.size.width/2, self.bgView.frame.size.height/2);
    
    //add the window background
    UIView *background = [[[UIView alloc] initWithFrame:CGRectInset
                           (self.bigPanelView.frame, 15, 30)] autorelease];
    background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    background.backgroundColor = [UIColor whiteColor];
    background.layer.borderColor = [[UIColor blackColor] CGColor];
    background.layer.borderWidth = 2;
    background.center = CGPointMake(self.bigPanelView.frame.size.width/2, self.bigPanelView.frame.size.height/2);
    [self.bigPanelView addSubview: background];
    
    //add the web view
    int webOffset = 2;
    self.webView.frame = CGRectInset(background.frame, webOffset, webOffset);
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    [self.bigPanelView addSubview: self.webView];
    
    [self.webView addSubview:self.loadingIndicator];
    self.loadingIndicator.center = CGPointMake(self.webView.frame.size.width/2, self.webView.frame.size.height/2);
    [self.loadingIndicator show];
    
    //add the close button
    int closeBtnOffset = 10;
    UIImage* closeBtnImg = [UIImage imageNamed:@"overlayCloseBtn.png"];
    UIButton* closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [closeBtn setImage:closeBtnImg forState:UIControlStateNormal];
    [closeBtn setFrame:CGRectMake( background.frame.origin.x + background.frame.size.width - closeBtnImg.size.width - closeBtnOffset, 
                                  background.frame.origin.y ,
                                  closeBtnImg.size.width + closeBtnOffset, 
                                  closeBtnImg.size.height + closeBtnOffset)];
    [closeBtn addTarget:self action:@selector(closePopupWindow) forControlEvents:UIControlEventTouchUpInside];
    [self.bigPanelView addSubview: closeBtn];
    
}

-(void)displayWindow {
    
    if ([self shouldTransition]) {
        //faux view
        UIView* fauxView = [[[UIView alloc] initWithFrame: self.bgView.bounds] autorelease];
        fauxView.autoresizesSubviews = YES;
        fauxView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.bgView addSubview: fauxView];
        
        //animation options
        UIViewAnimationOptions options = UIViewAnimationOptionTransitionFlipFromRight |
        UIViewAnimationOptionAllowUserInteraction    |
        UIViewAnimationOptionBeginFromCurrentState;
        
        [self constructWindow];
        
        //run the animation
        [UIView transitionFromView:fauxView toView:self.bigPanelView duration:0.5 options:options completion: ^(BOOL finished) {
            
            //dim the contents behind the popup window
            UIView* shadeView = [[[UIView alloc] initWithFrame:self.bigPanelView.bounds] autorelease];
            shadeView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            shadeView.backgroundColor = [UIColor blackColor];
            shadeView.alpha = 0.3;
            shadeView.tag = kShadeViewTag;
            [self.bigPanelView addSubview: shadeView];
            [self.bigPanelView sendSubviewToBack: shadeView];
        }];
    }
    
    else {
        [self constructWindow];
        [self.bgView addSubview:self.bigPanelView];
    }
}

- (void)onRotationChange:(UIInterfaceOrientation)toInterfaceOrientation {
    
    if(![self.parentViewController shouldAutorotateToInterfaceOrientation:toInterfaceOrientation]) {
        return;
    }
    
    switch (toInterfaceOrientation) {
        case UIDeviceOrientationPortrait:
            [self.webView stringByEvaluatingJavaScriptFromString:@"window.__defineGetter__('orientation',function(){return 0;});window.onorientationchange();"];
            break;
        case UIDeviceOrientationLandscapeLeft:
            [self.webView stringByEvaluatingJavaScriptFromString:@"window.__defineGetter__('orientation',function(){return 90;});window.onorientationchange();"];
            break;
        case UIDeviceOrientationLandscapeRight:
            [self.webView stringByEvaluatingJavaScriptFromString:@"window.__defineGetter__('orientation',function(){return -90;});window.onorientationchange();"];
            break;
        case UIDeviceOrientationPortraitUpsideDown:
            [self.webView stringByEvaluatingJavaScriptFromString:@"window.__defineGetter__('orientation',function(){return 180;});window.onorientationchange();"];
            break;
        default:
            break;
    }
}

- (void)orientationChanged:(NSNotification *)notification {
    // Note that face up and face down orientations will be ignored as this
    // casts a device orientation to an interface orientation
    [self onRotationChange:(UIInterfaceOrientation)[UIDevice currentDevice].orientation];
}

- (void)populateJavascriptEnvironment {
    
    // This will inject the current device orientation
    // Note that face up and face down orientations will be ignored as this
    // casts a device orientation to an interface orientation
    [self onRotationChange:(UIInterfaceOrientation)[UIDevice currentDevice].orientation];
    
    /*
     * Define and initialize our one global
     */
    NSString *js = @"var UAirship = {};";
    
    /*
     * Set the device model.
     */
    NSString *model = [UIDevice currentDevice].model;
    js = [js stringByAppendingFormat:@"UAirship.devicemodel=\"%@\";", model];
    
    /*
     * Set the UA user ID.
     */
    NSString *userID = [UAUser defaultUser].username;
    js = [js stringByAppendingFormat:@"UAirship.userID=\"%@\";", userID];
    
    /*
     * Set the current message ID.
     */
    NSString *messageID = self.message.messageID;
    js = [js stringByAppendingFormat:@"UAirship.messageID=\"%@\";", messageID];

    /*
     * Set the current message's sent date (GMT).
     */
    NSDate *date = self.message.messageSent;
    NSDateFormatter* dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
    NSLocale *enUSPOSIXLocale = [[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease];
    [dateFormatter setLocale:enUSPOSIXLocale];
    [dateFormatter setTimeStyle:NSDateFormatterFullStyle];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    [dateFormatter setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];

    NSString *messageSentDate = [dateFormatter stringFromDate:date];
    js = [js stringByAppendingFormat:@"UAirship.messageSentDate=\"%@\";", messageSentDate];

    /*
     * Set the current message's sent date (unix epoch time in milliseconds).
     */
    NSString *messageSentDateMS = [NSString stringWithFormat:@"%.0f", [date timeIntervalSince1970] * 1000];
    js =[js stringByAppendingFormat:@"UAirship.messageSentDateMS=%@;", messageSentDateMS];

    /*
     * Set the current message's title.
     */
    NSString *messageTitle = self.message.title;
    js = [js stringByAppendingFormat:@"UAirship.messageTitle=\"%@\";", messageTitle];

    /*
     * Define UAirship.handleCustomURL.
     */
    js = [js stringByAppendingString:@"UAirship.invoke = function(url) { location = url; };"];
    
    /*
     * Execute the JS we just constructed.
     */
    [self.webView stringByEvaluatingJavaScriptFromString:js];
}

- (void)injectViewportFix {
    NSString *js = @"var metaTag = document.createElement('meta');"
    "metaTag.name = 'viewport';"
    "metaTag.content = 'width=device-width; initial-scale=1.0; maximum-scale=1.0;';"
    "document.getElementsByTagName('head')[0].appendChild(metaTag);";
    
    [self.webView stringByEvaluatingJavaScriptFromString:js];
}

/**
 * Removes the shade background and calls the finish selector
 */
- (void)closePopupWindow {
    //remove the shade
    [[self.bigPanelView viewWithTag: kShadeViewTag] removeFromSuperview];
    [self performSelector:@selector(finish) withObject:nil afterDelay:0.1];
    
}

/**
 * Removes child views from bigPanelView and bgView
 */
- (void)removeChildViews {
    for (UIView* child in self.bigPanelView.subviews) {
        [child removeFromSuperview];
    }
    for (UIView* child in self.bgView.subviews) {
        [child removeFromSuperview];
    }
}


/**
 * Removes all views from the hierarchy and releases self
 */
-(void)finish {
    
    if ([self shouldTransition]) {
        
        //faux view
        UIView* fauxView = [[[UIView alloc] initWithFrame: CGRectMake(10, 10, 200, 200)] autorelease];
        [self.bgView addSubview: fauxView];
        
        //run the animation
        UIViewAnimationOptions options = UIViewAnimationOptionTransitionFlipFromLeft |
        UIViewAnimationOptionAllowUserInteraction    |
        UIViewAnimationOptionBeginFromCurrentState;
                
        [UIView transitionFromView:self.bigPanelView toView:fauxView duration:0.5 options:options completion:^(BOOL finished) {
            
            [self removeChildViews];
            self.bigPanelView = nil;
            [self.bgView removeFromSuperview];
            [overlayControllers removeObject:self];
        }];
    }
    
    else {
        [self removeChildViews];
        [self.bgView removeFromSuperview];
        [overlayControllers removeObject:self];
    }
}


#pragma mark UIWebViewDelegate

- (BOOL)webView:(UIWebView *)wv shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    NSURL *url = [request URL];
    
    /*
     ua://callbackArguments:withOptions:/[<arguments>][?<dictionary>]
     */
    
    if ([[url scheme] isEqualToString:@"ua"]) {
        if ((navigationType == UIWebViewNavigationTypeLinkClicked) || (navigationType == UIWebViewNavigationTypeOther)) {
            [UAInboxMessage performJSDelegate:wv url:url];
            return NO;
        }
    }
    
    // send iTunes/Phobos urls to AppStore.app
    else if ((navigationType == UIWebViewNavigationTypeLinkClicked) &&
             (([[url host] isEqualToString:@"phobos.apple.com"]) ||
              ([[url host] isEqualToString:@"itunes.apple.com"]))) {
                 
                 // TODO: set the url scheme to http, as it could be itms which will cause the store to launch twice (undesireable)
                 
                 return ![[UIApplication sharedApplication] openURL:url];
             }
    
    // send maps.google.com url or maps: to GoogleMaps.app
    else if ((navigationType == UIWebViewNavigationTypeLinkClicked) &&
             (([[url host] isEqualToString:@"maps.google.com"]) ||
              ([[url scheme] isEqualToString:@"maps"]))) {
                 
                 /* Do any special formatting here, for example:
                  
                  NSString *title = @"title";
                  float latitude = 35.4634;
                  float longitude = 9.43425;
                  int zoom = 13;
                  NSString *stringURL = [NSString stringWithFormat:@"http://maps.google.com/maps?q=%@@%1.6f,%1.6f&z=%d", title, latitude, longitude, zoom];
                  
                  */
                 
                 return ![[UIApplication sharedApplication] openURL:url];
             }
    
    // send www.youtube.com url to YouTube.app
    else if ((navigationType == UIWebViewNavigationTypeLinkClicked) &&
             ([[url host] isEqualToString:@"www.youtube.com"])) {
        return ![[UIApplication sharedApplication] openURL:url];
    }
    
    // send mailto: to Mail.app
    else if ((navigationType == UIWebViewNavigationTypeLinkClicked) && ([[url scheme] isEqualToString:@"mailto"])) {
        
        /* Do any special formatting here if you like, for example:
         
         NSString *subject = @"Message subject";
         NSString *body = @"Message body";
         NSString *address = @"address@domain.com";
         NSString *cc = @"address@domain.com";
         NSString *path = [NSString stringWithFormat:@"mailto:%@?cc=%@&subject=%@&body=%@", address, cc, subject, body];
         NSURL *url = [NSURL URLWithString:[path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
         
         For complex body text you may want to use CFURLCreateStringByAddingPercentEscapes.
         
         */
        
        return ![[UIApplication sharedApplication] openURL:url];
    }
    
    // send tel: to Phone.app
    else if ((navigationType == UIWebViewNavigationTypeLinkClicked) && ([[url scheme] isEqualToString:@"tel"])) {
        
        // TODO: Phone number must not contain spaces or brackets. Spaces or plus signs OK. Can add come checks here.
        
        return ![[UIApplication sharedApplication] openURL:url];
    }
    
    // send sms: to Messages.app
    else if ((navigationType == UIWebViewNavigationTypeLinkClicked) && ([[url scheme] isEqualToString:@"sms"])) {
        return ![[UIApplication sharedApplication] openURL:url];
    }
    
    // load local file and http/https webpages in webview
    return YES;
}


- (void)webViewDidStartLoad:(UIWebView *)wv {
    [self populateJavascriptEnvironment];
}

- (void)webViewDidFinishLoad:(UIWebView *)wv {
    [self.loadingIndicator hide];
    
    // Mark message as read after it has finished loading
    if(self.message.unread) {
        [self.message markAsRead];
    }

    [self injectViewportFix];
}

- (void)webView:(UIWebView *)wv didFailLoadWithError:(NSError *)error {
    
    [self.loadingIndicator hide];
    
    if (error.code == NSURLErrorCancelled)
        return;
    UALOG(@"Failed to load message: %@", error);
    UIAlertView *someError = [[UIAlertView alloc] initWithTitle:UA_INBOX_TR(@"UA_Ooops")
                                                        message:UA_INBOX_TR(@"UA_Error_Fetching_Message")
                                                       delegate:self
                                              cancelButtonTitle:UA_INBOX_TR(@"UA_OK")
                                              otherButtonTitles:nil];
    [someError show];
    [someError release];
}


@end
