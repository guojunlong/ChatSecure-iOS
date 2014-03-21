//
//  OTRXMPPLoginViewController.m
//  Off the Record
//
//  Created by David on 10/2/12.
//  Copyright (c) 2012 Chris Ballinger. All rights reserved.
//
//  This file is part of ChatSecure.
//
//  ChatSecure is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  ChatSecure is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with ChatSecure.  If not, see <http://www.gnu.org/licenses/>.

#import "OTRXMPPLoginViewController.h"
#import "OTRConstants.h"
#import "OTRXMPPError.h"
#import "SIAlertView.h"
#import "HITorManager.h"
#import "OTRColors.h"
#import "OTRCertificatePinning.h"
#import "OTRManagedXMPPTorAccount.h"



@interface OTRXMPPLoginViewController ()

@property (nonatomic,strong) SIAlertView * certAlertView;

@end

@implementation OTRXMPPLoginViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.resourceTextField = [[UITextField alloc] init];
    self.resourceTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.resourceTextField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.resourceTextField.returnKeyType = UIReturnKeyDone;
    self.resourceTextField.textColor = self.textFieldTextColor;
    self.resourceTextField.text = self.account.resource;
    
    [self addCellinfoWithSection:1 row:0 labelText:@"Resource" cellType:kCellTypeTextField userInputView:self.resourceTextField];
    
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHideOrShow:) name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillHideOrShow:) name:UIKeyboardWillShowNotification object:nil];

}

-(void)keyboardWillHideOrShow:(NSNotification *)note
{
    NSDictionary *userInfo = note.userInfo;
    NSTimeInterval duration = [[userInfo objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = [[userInfo objectForKey:UIKeyboardAnimationCurveUserInfoKey] intValue];
    
    CGRect keyboardFrame = [[userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect keyboardFrameForTableView = [self.loginViewTableView.superview convertRect:keyboardFrame fromView:nil];
    
    CGRect newTableViewFrame = CGRectMake(0, 0, self.loginViewTableView.frame.size.width, keyboardFrameForTableView.origin.y);
    
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | curve animations:^{
        self.loginViewTableView.frame = newTableViewFrame;
    } completion:nil];
}

- (BOOL)isTorAccount{
    if ([self.account isKindOfClass:[OTRManagedXMPPTorAccount class]]) {
        return YES;
    }
    return NO;
}

- (void)readInFields
{
    [super readInFields];
    if (self.resourceTextField.text.length) {
        self.account.resource = self.resourceTextField.text;
    }
    else {
        self.account.resource = [OTRManagedXMPPAccount newResource];
    }
    
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHideOrShow:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHideOrShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    
    [self.usernameTextField resignFirstResponder];
    [self.passwordTextField resignFirstResponder];
    self.loginButtonPressed = NO;
    if (self.isTorAccount) {
        [[HITorManager defaultManager] addObserver:self forKeyPath:NSStringFromSelector(@selector(isRunning)) options:NSKeyValueObservingOptionNew context:NULL];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    if(self.isTorAccount)
    {
        [[HITorManager defaultManager] removeObserver:self forKeyPath:NSStringFromSelector(@selector(isRunning))];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                              name:UIKeyboardWillHideNotification
                                                  object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                              name:UIKeyboardWillShowNotification
                                                  object:nil];
    [super viewWillDisappear:animated];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:NSStringFromSelector(@selector(isRunning))] && [object isEqual:[HITorManager defaultManager]]) {
        BOOL isRunning = [[change objectForKey:NSKeyValueChangeNewKey] boolValue];
        if (isRunning && self.loginButtonPressed) {
            [self loginButtonPressed:nil];
        }
    }
}

- (void)protocolLoginFailed:(NSNotification *)notification {
    [self hideHUD];
    NSError * error = notification.userInfo[kOTRNotificationErrorKey];
    
    if (error.code == OTRXMPPSSLError) {
        NSData * certData = error.userInfo[OTRXMPPSSLCertificateDataKey];
        NSString * hostname = error.userInfo[OTRXMPPSSLHostnameKey];
        NSNumber * statusNumber = error.userInfo[OTRXMPPSSLStatusKey];
        
        if ([statusNumber longLongValue] == errSSLPeerAuthCompleted) {
            //The cert was manually evaluated but did not anything that is saved so we have to recheck system and get interal validation status
            id<OTRProtocol> protocol = [[OTRProtocolManager sharedInstance] protocolForAccount:self.account];
            ((OTRXMPPManager *)protocol).certificatePinningModule.doNotManuallyEvaluateOverride = YES;
            [self loginButtonPressed:nil];
        }
        else {
            [self showCertWarningForCertificateData:certData withHostname:hostname withStatus:[statusNumber longValue]];
        }
    }
    else if(!self.certAlertView.isVisible){
        [super protocolLoginFailed:notification];
    }
}

- (void)showCertWarningForCertificateData:(NSData *)certData withHostname:(NSString *)hostname withStatus:(OSStatus)status {
    
    SecCertificateRef certificate = [OTRCertificatePinning certForData:certData];
    NSString * fingerprint = [OTRCertificatePinning sha1FingerprintForCertificate:certificate];
    NSString * message = [NSString stringWithFormat:@"%@\nSHA1: %@",hostname,fingerprint];
    NSUInteger length = [message length];
    
    UIColor * sslMessageColor;
    NSMutableAttributedString * attributedString = nil;
    
    self.certAlertView = [[SIAlertView alloc] initWithTitle:NEW_CERTIFICATE_STRING andMessage:nil];
    
    self.certAlertView.buttonColor = [UIColor whiteColor];
    
    if (![OTRCertificatePinning publicKeyWithCertData:certData]) {
        //no public key not able to save because won't be able evaluate later
        
        self.certAlertView.messageAttributedString = nil;
        message = [message stringByAppendingString:[NSString stringWithFormat:@"\nX %@",PUBLIC_KEY_ERROR_STRING]];
        attributedString = [[NSMutableAttributedString alloc] initWithString:message];
        sslMessageColor = [OTRColors redErrorColor];
        
        [self.certAlertView addButtonWithTitle:OK_STRING type:SIAlertViewButtonTypeCancel handler:^(SIAlertView *alertView) {
            [alertView dismissAnimated:YES];
        }];
        
    }
    else {
        if (status == noErr) {
            //#52A352
            sslMessageColor = [OTRColors greenNoErrorColor];
            message = [message stringByAppendingString:[NSString stringWithFormat:@"\n✓ %@",VALID_CERTIFICATE_STRING]];
        }
        else {
            NSString * sslErrorMessage = [OTRXMPPError errorStringWithSSLStatus:status];
            sslMessageColor = [OTRColors redErrorColor];
            message = [message stringByAppendingString:[NSString stringWithFormat:@"\nX %@",sslErrorMessage]];
        }
        
        attributedString = [[NSMutableAttributedString alloc] initWithString:message];
        
        [self.certAlertView addButtonWithTitle:REJECT_STRING type:SIAlertViewButtonTypeDestructive handler:^(SIAlertView *alertView) {
            [alertView dismissAnimated:YES];
        }];
        __weak OTRXMPPLoginViewController * weakSelf = self;
        [self.certAlertView addButtonWithTitle:SAVE_STRING type:SIAlertViewButtonTypeDefault handler:^(SIAlertView *alertView) {
            id<OTRProtocol> protocol = [[OTRProtocolManager sharedInstance] protocolForAccount:weakSelf.account];
            if ([protocol isKindOfClass:[OTRXMPPManager class]]) {
                [OTRCertificatePinning addCertificate:[OTRCertificatePinning certForData:certData] withHostName:hostname];
                [weakSelf loginButtonPressed:alertView];
            }
        }];
    }
    
    NSRange errorMessageRange = NSMakeRange(length, message.length-length);
    [attributedString addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:16] range:NSMakeRange(0, message.length)];
    [attributedString addAttribute:NSForegroundColorAttributeName value:sslMessageColor range:errorMessageRange];
    
    self.certAlertView.messageAttributedString = attributedString;
    
    [self.certAlertView show];
    
    UIImage * normalImage = [UIImage imageNamed:@"button-green"];
    CGFloat hInset = floorf(normalImage.size.width / 2);
	CGFloat vInset = floorf(normalImage.size.height / 2);
	UIEdgeInsets insets = UIEdgeInsetsMake(vInset, hInset, vInset, hInset);
	UIImage * buttonImage = [normalImage resizableImageWithCapInsets:insets];
    
    [self.certAlertView setDefaultButtonImage:buttonImage forState:UIControlStateNormal];
    [self.certAlertView setDefaultButtonImage:buttonImage forState:UIControlStateHighlighted];
}

- (void)loginButtonPressed:(id)sender
{
    self.loginButtonPressed = YES;
    if( [self.account isKindOfClass:[OTRManagedXMPPTorAccount class]]){
        if(![HITorManager defaultManager].isRunning) {
            [self showHUDWithText:@"Connecting to Tor"];
            [[HITorManager defaultManager] start];
        }
        else{
            [super loginButtonPressed:sender];
        }
    }
    else {
        [super loginButtonPressed:sender];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


@end
