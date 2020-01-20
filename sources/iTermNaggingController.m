//
//  iTermNaggingController.m
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/11/19.
//

#import "iTermNaggingController.h"

#import "DebugLogging.h"
#import "iTermAdvancedSettingsModel.h"
#import "NSArray+iTerm.h"
#import "NSStringITerm.h"
#import "ProfileModel.h"

static NSString *const iTermNaggingControllerOrphanIdentifier = @"DidRestoreOrphan";
static NSString *const iTermNaggingControllerReopenSessionAfterBrokenPipeIdentifier = @"ReopenSessionAfterBrokenPipe";
static NSString *const iTermNaggingControllerAbortDownloadIdentifier = @"AbortDownloadOnKeyPressAnnouncement";
static NSString *const iTermNaggingControllerAbortUploadOnKeyPressAnnouncementIdentifier = @"AbortUploadOnKeyPressAnnouncement";
static NSString *const iTermNaggingControllerArrangementProfileMissingIdentifier = @"ThisProfileNoLongerExists";
static NSString *const iTermNaggingControllerTmuxSupplementaryPlaneErrorIdentifier = @"Tmux2.2SupplementaryPlaneAnnouncement";
static NSString *const iTermNaggingControllerAskAboutAlternateMouseScrollIdentifier = @"AskAboutAlternateMouseScroll";
static NSString *const iTermNaggingControllerAskAboutMouseReportingFrustrationIdentifier = @"AskAboutMouseReportingFrustration";

static NSString *const iTermNaggingControllerUserDefaultNeverAskAboutSettingAlternateMouseScroll = @"NoSyncNeverAskAboutSettingAlternateMouseScroll";
static NSString *const iTermNaggingControllerUserDefaultMouseReportingFrustrationDetectionDisabled = @"NoSyncNeverAskAboutMouseReportingFrustration";

static NSString *iTermNaggingControllerSetBackgroundImageFileIdentifier = @"SetBackgroundImageFile";
static NSString *iTermNaggingControllerUserDefaultAlwaysAllowBackgroundImage = @"AlwaysAllowBackgroundImage";
static NSString *iTermNaggingControllerUserDefaultAlwaysDenyBackgroundImage = @"AlwaysDenyBackgroundImage";

@implementation iTermNaggingController

- (BOOL)permissionToReportVariableNamed:(NSString *)name {
    static NSString *const allow = @"allow:";
    static NSString *const deny = @"deny:";

    NSNumber *originalValue = nil;
    {
        NSArray<NSString *> *parts = [self variablesToReportEntries];
        if ([parts containsObject:[allow stringByAppendingString:name]]) {
            originalValue = @YES;
        }
        if ([parts containsObject:[deny stringByAppendingString:name]]) {
            originalValue = @NO;
        }
    }

    return [self requestPermissionWithOriginalValue:originalValue
                                                key:[NSString stringWithFormat:@"ShouldReportVariable%@", name]
                                   prompt:[NSString stringWithFormat:@"A request to report variable “%@” was denied. Allow it in the future?", name]
                                   setter:^(BOOL shouldAllow) {
        NSArray<NSString *> *parts = [self variablesToReportEntries];
        NSString *prefix = shouldAllow ? allow : deny;
        NSString *newEntry = [prefix stringByAppendingString:name];
        parts = [parts arrayByAddingObject:newEntry];
        [iTermAdvancedSettingsModel setNoSyncVariablesToReport:[parts componentsJoinedByString:@","]];
    }];
}

- (void)arrangementWithName:(NSString *)savedArrangementName
        missingProfileNamed:(NSString *)missingProfileName
                       guid:(NSString *)guid {
    DLog(@"Can’t find profile %@ guid %@", missingProfileName, guid);
    if ([iTermAdvancedSettingsModel noSyncSuppressMissingProfileInArrangementWarning]) {
        return;
    }
    NSString *notice;
    NSArray<NSString *> *actions = @[ @"Don’t Warn Again" ];
    if ([[ProfileModel sharedInstance] bookmarkWithName:missingProfileName]) {
        notice = [NSString stringWithFormat:@"This session’s profile, “%@”, no longer exists. A profile with that name happens to exist.", missingProfileName];
        if (savedArrangementName) {
            actions = [actions arrayByAddingObject:@"Repair Saved Arrangement"];
        }
    } else {
        notice = [NSString stringWithFormat:@"This session’s profile, “%@”, no longer exists.", missingProfileName];
    }
    _missingSavedArrangementProfileGUID = [guid copy];
    [self.delegate naggingControllerShowMessage:notice
                                     isQuestion:NO
                                      important:NO
                                     identifier:iTermNaggingControllerArrangementProfileMissingIdentifier
                                        options:actions
                                     completion:^(int selection) {
        [self handleCompletionForMissingProfileInArrangementWithName:savedArrangementName
                                                 missingProfileNamed:missingProfileName
                                                                guid:guid
                                                           selection:selection];
    }];
}

- (void)didRestoreOrphan {
    [self.delegate naggingControllerShowMessage:@"This already-running session was restored but its contents were not saved."
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerOrphanIdentifier
                                        options:@[ @"Why?" ]
                                     completion:^(int selection) {
        if (selection == 0) {
            // Why?
            NSURL *whyUrl = [NSURL URLWithString:@"https://iterm2.com/why_no_content.html"];
            [[NSWorkspace sharedWorkspace] openURL:whyUrl];
        }
    }];
}

- (void)brokenPipe {
    [self.delegate naggingControllerShowMessage:@"Session ended (broken pipe). Restart it?"
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerReopenSessionAfterBrokenPipeIdentifier
                                        options:@[ @"_Restart", @"Don’t Ask Again" ]
                                     completion:^(int selection) {
        [self handleCompletionForBrokenPipe:selection];
    }];
}

- (void)askAboutAbortingDownload {
    [self.delegate naggingControllerShowMessage:@"A file is being downloaded. Abort the download?"
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerAbortDownloadIdentifier
                                        options:@[ @"OK", @"Cancel" ]
                                     completion:^(int selection) {
        if (selection == 0) {
            [self.delegate naggingControllerAbortDownload];
        }
    }];
}

- (void)askAboutAbortingUpload {
    [self.delegate naggingControllerShowMessage:@"A file is being uploaded. Abort the upload?"
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerAbortUploadOnKeyPressAnnouncementIdentifier
                                        options:@[ @"OK", @"Cancel" ]
                                     completion:^(int selection) {
        if (selection == 0) {
            [self.delegate naggingControllerAbortUpload];
        }
    }];
}

- (void)didFinishDownload {
    [self.delegate naggingControllerRemoveMessageWithIdentifier:iTermNaggingControllerAbortDownloadIdentifier];
}

- (void)didRepairSavedArrangement {
    [self.delegate naggingControllerRemoveMessageWithIdentifier:iTermNaggingControllerArrangementProfileMissingIdentifier];
}

- (void)willRecycleSession {
    NSArray<NSString *> *identifiers = @[
        iTermNaggingControllerOrphanIdentifier,
        iTermNaggingControllerReopenSessionAfterBrokenPipeIdentifier,
        iTermNaggingControllerAbortDownloadIdentifier,
        iTermNaggingControllerAbortUploadOnKeyPressAnnouncementIdentifier ];
    for (NSString *identifier in identifiers) {
        [self.delegate naggingControllerRemoveMessageWithIdentifier:identifier];
    }
}

- (void)tmuxSupplementaryPlaneErrorForCharacter:(NSString *)string {
    NSString *message = [NSString stringWithFormat:@"Because of a bug in tmux 2.2, the character “%@” cannot be sent.", string];
    [self.delegate naggingControllerShowMessage:message
                                     isQuestion:NO
                                      important:NO
                                     identifier:iTermNaggingControllerTmuxSupplementaryPlaneErrorIdentifier
                                        options:@[ @"Why?" ]
                                     completion:^(int selection) {
        if (selection == 0) {
            [self showTmuxSupplementaryPlaneBugHelpPage];
        }
    }];
}

- (void)showTmuxSupplementaryPlaneBugHelpPage {
    NSURL *whyUrl = [NSURL URLWithString:@"https://iterm2.com//tmux22bug.html"];
    [[NSWorkspace sharedWorkspace] openURL:whyUrl];
}

- (void)tryingToSendArrowKeysWithScrollWheel:(BOOL)isTrying {
    if (!isTrying) {
        [self.delegate naggingControllerRemoveMessageWithIdentifier:iTermNaggingControllerAskAboutAlternateMouseScrollIdentifier];
        return;
    }
    if ([[NSUserDefaults standardUserDefaults] boolForKey:iTermNaggingControllerUserDefaultNeverAskAboutSettingAlternateMouseScroll]) {
        return;
    }
    [self.delegate naggingControllerShowMessage:@"Do you want the scroll wheel to move the cursor in interactive programs like this?"
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerAskAboutAlternateMouseScrollIdentifier
                                        options:@[ @"Yes", @"Don‘t Ask Again" ]
                                     completion:^(int selection) {
        [self handleTryingToSendArrowKeysWithScrollWheel:selection];
    }];
}

- (void)handleTryingToSendArrowKeysWithScrollWheel:(int)selection {
    switch (selection) {
        case 0: // Yes
            [iTermAdvancedSettingsModel setAlternateMouseScroll:YES];
            break;

        case 1: { // Never
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:iTermNaggingControllerUserDefaultNeverAskAboutSettingAlternateMouseScroll];
            break;
        }
    }
}

- (void)setBackgroundImageToFileWithName:(NSString *)maybeFilename {
    NSString *filename = maybeFilename ?: @"";
    DLog(@"screenSetbackgroundImageFile:%@", filename);

    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSArray *allowedFiles = [userDefaults objectForKey:iTermNaggingControllerUserDefaultAlwaysAllowBackgroundImage];
    NSArray *deniedFiles = [userDefaults objectForKey:iTermNaggingControllerUserDefaultAlwaysDenyBackgroundImage];
    if ([deniedFiles containsObject:filename]) {
        return;
    }
    if ([allowedFiles containsObject:filename]) {
        [self.delegate naggingControllerSetBackgroundImageToFileWithName:filename];
        return;
    }

    NSString *title;
    if (filename.length) {
        title = [NSString stringWithFormat:@"Set background image to “%@”?", filename];
    } else {
        title = @"Remove background image?";
    }
    [self.delegate naggingControllerShowMessage:title
                                     isQuestion:YES
                                      important:NO
                                     identifier:iTermNaggingControllerSetBackgroundImageFileIdentifier
                                        options:@[ @"Yes", @"Always", @"Never" ]
                                     completion:^(int selection) {
        [self handleSetBackgroundImageToFileWithName:filename selection:selection];
    }];
}

- (void)handleSetBackgroundImageToFileWithName:(NSString *)filename selection:(int)selection {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    switch (selection) {
        case 0: // Yes
            if (!filename.length) {
                DLog(@"Filename is empty. Reset the background image.");
                [self.delegate naggingControllerSetBackgroundImageToFileWithName:nil];
                return;
            }
            [self.delegate naggingControllerSetBackgroundImageToFileWithName:filename];
            break;

        case 1: { // Always
            NSArray *allowed = [userDefaults objectForKey:iTermNaggingControllerUserDefaultAlwaysAllowBackgroundImage];
            if (!allowed) {
                allowed = @[];
            }
            allowed = [allowed arrayByAddingObject:filename];
            [userDefaults setObject:allowed forKey:iTermNaggingControllerUserDefaultAlwaysAllowBackgroundImage];
            if (!filename.length) {
                DLog(@"Filename is empty. Reset the background image.");
                [self.delegate naggingControllerSetBackgroundImageToFileWithName:nil];
                return;
            }
            [self.delegate naggingControllerSetBackgroundImageToFileWithName:filename];
            break;
        }
        case 2: {  // Never
            NSArray *denied = [userDefaults objectForKey:iTermNaggingControllerUserDefaultAlwaysDenyBackgroundImage];
            if (!denied) {
                denied = @[];
            }
            denied = [denied arrayByAddingObject:filename];
            [userDefaults setObject:denied forKey:iTermNaggingControllerUserDefaultAlwaysDenyBackgroundImage];
            break;
        }
    }
}

- (void)didDetectMouseReportingFrustration {
    if ([[NSUserDefaults standardUserDefaults] boolForKey:iTermNaggingControllerUserDefaultMouseReportingFrustrationDetectionDisabled]) {
        return;
    }
    [self.delegate naggingControllerShowMessage:@"Looks like you’re trying to copy to the pasteboard, but mouse reporting has prevented making a selection. Disable mouse reporting?"
                                     isQuestion:YES
                                      important:YES
                                     identifier:iTermNaggingControllerAskAboutMouseReportingFrustrationIdentifier
                                        options:@[ @"_Temporarily", @"Permanently" ]
                                     completion:^(int selection) {
        [self handleMouseReportingFrustration:selection];
    }];
}

- (void)handleMouseReportingFrustration:(int)selection {
    switch (selection) {
        case 0: // Temporarily
            [self.delegate naggingControllerDisableMouseReportingPermanently:NO];
            break;

        case 1: { // Never
            [self.delegate naggingControllerDisableMouseReportingPermanently:YES];
            break;
        }
    }
}


#pragma mark - Variable Reporting

- (NSArray<NSString *> *)variablesToReportEntries {
    return [[[iTermAdvancedSettingsModel noSyncVariablesToReport] componentsSeparatedByString:@","] filteredArrayUsingBlock:^BOOL(NSString *anObject) {
        return anObject.length > 0;
    }];
}

- (BOOL)requestPermissionWithOriginalValue:(NSNumber *)setting
                                       key:(NSString *)key
                                    prompt:(NSString *)prompt
                                    setter:(void (^)(BOOL))setter {
    if (setting) {
        return setting.boolValue;
    }
    if (![self.delegate naggingControllerCanShowMessageWithIdentifier:key]) {
        return NO;
    }
    [self.delegate naggingControllerShowMessage:prompt
                                     isQuestion:YES
                                      important:YES
                                     identifier:key
                                        options:@[ @"Always Allow", @"Always Deny" ]
                                     completion:^(int selection) {
        if (selection == 0) {
            setter(YES);
        } else if (selection == 1) {
            setter(NO);
        }
    }];
    return NO;
}

#pragma mark - Arrangement with missing profile

- (void)handleCompletionForMissingProfileInArrangementWithName:(NSString *)savedArrangementName
                                           missingProfileNamed:(NSString *)missingProfileName
                                                          guid:(NSString *)guid
                                                     selection:(int)selection {
    if (selection == 0) {
        [iTermAdvancedSettingsModel setNoSyncSuppressMissingProfileInArrangementWarning:YES];
        return;
    }
    if (selection == 1) {
        [self.delegate naggingControllerRepairSavedArrangement:savedArrangementName
                                           missingProfileNamed:missingProfileName
                                                          guid:guid];
        return;
    }
}

- (void)handleCompletionForBrokenPipe:(int)selection {
    switch (selection) {
        case 0: // Yes
            [self.delegate naggingControllerRestart];
            break;

        case 1: // Don't ask again
            [iTermAdvancedSettingsModel setSuppressRestartAnnouncement:YES];
            break;
    }
}

@end