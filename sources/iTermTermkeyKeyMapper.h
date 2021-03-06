//
//  iTermTermkeyKeyMapper.h
//  iTerm2SharedARC
//
//  Created by George Nachman on 12/30/18.
//

#import <Cocoa/Cocoa.h>

#import "ITAddressBookMgr.h"
#import "iTermKeyMapper.h"
#import "VT100Terminal.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermTermkeyKeyMapper;

// Update iTermTermkeyKeyMapperConfigurationDictionary when modifying this.
typedef struct {
    NSStringEncoding encoding;
    iTermOptionKeyBehavior leftOptionKey;
    iTermOptionKeyBehavior rightOptionKey;
    BOOL applicationCursorMode;
    BOOL applicationKeypadMode;
} iTermTermkeyKeyMapperConfiguration;

NSDictionary *iTermTermkeyKeyMapperConfigurationDictionary(iTermTermkeyKeyMapperConfiguration *config);

@protocol iTermTermkeyKeyMapperDelegate<NSObject>
- (void)termkeyKeyMapperWillMapKey:(iTermTermkeyKeyMapper *)termkeyKeyMaper;
@end

@interface iTermTermkeyKeyMapper : NSObject<iTermKeyMapper>

@property (nonatomic, weak) id<iTermTermkeyKeyMapperDelegate> delegate;
@property (nonatomic) iTermTermkeyKeyMapperConfiguration configuration;
@property (nonatomic) VT100TerminalKeyReportingFlags flags;

@end

NS_ASSUME_NONNULL_END
