#import "MVDirectChatConnection.h"
#import "MVDirectChatConnectionPrivate.h"

#import "InterThreadMessaging.h"
#import "MVDirectClientConnection.h"
#import "MVIRCChatConnection.h"
#import "MVFileTransfer.h"
#import "MVChatUser.h"
#import "MVUtilities.h"
#import "NSNotificationAdditions.h"
#import "NSStringAdditions.h"
#import "NSAttributedStringAdditions.h"

NSString *MVDirectChatConnectionOfferNotification = @"MVDirectChatConnectionOfferNotification";

NSString *MVDirectChatConnectionDidConnectNotification = @"MVDirectChatConnectionDidConnectNotification";
NSString *MVDirectChatConnectionDidNotConnectNotification = @"MVDirectChatConnectionDidNotConnectNotification";
NSString *MVDirectChatConnectionDidDisconnectNotification = @"MVDirectChatConnectionDidDisconnectNotification";
NSString *MVDirectChatConnectionErrorOccurredNotification = @"MVDirectChatConnectionErrorOccurredNotification";

NSString *MVDirectChatConnectionGotMessageNotification = @"";

NSString *MVDirectChatConnectionErrorDomain = @"MVDirectChatConnectionErrorDomain";

@implementation MVDirectChatConnection
+ (id) directChatConnectionWithUser:(MVChatUser *) user passively:(BOOL) passive {
	static unsigned passiveId = 0;

	MVDirectChatConnection *ret = [(MVDirectChatConnection *)[MVDirectChatConnection allocWithZone:nil] initWithUser:user];
	[ret _setLocalRequest:YES];
	[ret _setPassive:passive];

	if( passive ) {
		if( ++passiveId > 999 ) passiveId = 1;
		[ret _setPassiveIdentifier:passiveId];

		// register with the main connection so the passive reply can find the original
		[(MVIRCChatConnection *)[user connection] _addDirectClientConnection:ret];

		[user sendSubcodeRequest:@"DCC" withArguments:[NSString stringWithFormat:@"CHAT chat 16843009 0 %lu", passiveId]];
	} else {
		[ret initiate];
	}

	return [ret autorelease];
}

- (void) release {
	if( ! _releasing && ( [self retainCount] - 1 ) == 1 ) {
		_releasing = YES;
		[(MVIRCChatConnection *)[[self user] connection] _removeDirectClientConnection:self];
	}

	[super release];
}

- (void) dealloc {
	[_directClientConnection disconnect];
	[_directClientConnection setDelegate:nil];
	[_directClientConnection release];

	[_startDate release];
	[_host release];
	[_user release];
	[_lastError release];

	_directClientConnection = nil;
	_startDate = nil;
	_host = nil;
	_user = nil;
	_lastError = nil;

	[super dealloc];
}

- (void) finalize {
	[_directClientConnection disconnect];

	[super finalize];
}

#pragma mark -

- (BOOL) isPassive {
	return _passive;
}

- (MVDirectChatConnectionStatus) status {
	return _status;
}

- (MVChatUser *) user {
	return _user;
}

- (NSHost *) host {
	return _host;
}

- (unsigned short) port {
	return _port;
}

#pragma mark -

- (void) initiate {
	if( [_directClientConnection connectionThread] ) return;

	MVSafeAssign( &_directClientConnection, [[MVDirectClientConnection allocWithZone:nil] init] );
	[_directClientConnection setDelegate:self];

	if( _localRequest ) {
		if( ! [self isPassive] ) [_directClientConnection acceptConnectionOnFirstPortInRange:[MVFileTransfer fileTransferPortRange]];
		else [_directClientConnection connectToHost:[[self host] address] onPort:[self port]];
	} else {
		if( [self isPassive] ) [_directClientConnection acceptConnectionOnFirstPortInRange:[MVFileTransfer fileTransferPortRange]];
		else [_directClientConnection connectToHost:[[self host] address] onPort:[self port]];
	}
}

- (void) disconnect {
	[_directClientConnection disconnect];
}

#pragma mark -

- (void) setEncoding:(NSStringEncoding) newEncoding {
	_encoding = newEncoding;
}

- (NSStringEncoding) encoding {
	return _encoding;
}

#pragma mark -

- (void) setOutgoingChatFormat:(MVChatMessageFormat) format {
	if( ! format ) format = MVChatConnectionDefaultMessageFormat;
	_outgoingChatFormat = format;
}

- (MVChatMessageFormat) outgoingChatFormat {
	return _outgoingChatFormat;
}

#pragma mark -

- (void) sendMessage:(NSAttributedString *) message asAction:(BOOL) action {
	[self sendMessage:message withEncoding:[self encoding] asAction:action];
}

- (void) sendMessage:(NSAttributedString *) message withEncoding:(NSStringEncoding) encoding asAction:(BOOL) action {
	NSParameterAssert( message != nil );

	if( [self status] != MVDirectChatConnectionNormalStatus )
		return;

	NSString *cformat = nil;

	switch( [self outgoingChatFormat] ) {
	case MVChatConnectionDefaultMessageFormat:
	case MVChatWindowsIRCMessageFormat:
		cformat = NSChatWindowsIRCFormatType;
		break;
	case MVChatCTCPTwoMessageFormat:
		cformat = NSChatCTCPTwoFormatType;
		break;
	default:
	case MVChatNoMessageFormat:
		cformat = nil;
	}

	NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInt:encoding], @"StringEncoding", cformat, @"FormatType", nil];
	NSData *msg = [message chatFormatWithOptions:options];

	if( action ) {
		NSMutableData *newMsg = [[NSMutableData allocWithZone:nil] initWithCapacity:[msg length] + 11];
		[newMsg appendBytes:"\001ACTION " length:8];
		[newMsg appendData:msg];
		[newMsg appendBytes:"\001\x0D\x0A" length:3];

		[self performSelector:@selector( _writeMessage: ) withObject:newMsg inThread:[_directClientConnection connectionThread]];

		[newMsg release];
	} else {
		NSMutableData *newMsg = [msg mutableCopyWithZone:nil];
		[newMsg appendBytes:"\x0D\x0A" length:2];

		[self performSelector:@selector( _writeMessage: ) withObject:newMsg inThread:[_directClientConnection connectionThread]];

		[newMsg release];
	}
}

#pragma mark -

- (void) directClientConnection:(MVDirectClientConnection *) connection didConnectToHost:(NSString *) host port:(unsigned short) port {
	[self _setStatus:MVDirectChatConnectionNormalStatus];
	[self _setStartDate:[NSDate date]];

	[self _readNextMessage];

	// now that we are connected deregister with the connection
	// do this last incase the connection is the last thing retaining us
	[(MVIRCChatConnection *)[[self user] connection] _removeDirectClientConnection:self];
}

- (void) directClientConnection:(MVDirectClientConnection *) connection acceptingConnectionsToHost:(NSString *) host port:(unsigned short) port {
	NSString *address = MVDCCFriendlyAddress( host );
	[self _setPort:port];

	if( [self isPassive] ) [[self user] sendSubcodeRequest:@"DCC" withArguments:[NSString stringWithFormat:@"CHAT chat %@ %hu %lu", address, [self port], [self _passiveIdentifier]]];
	else [[self user] sendSubcodeRequest:@"DCC" withArguments:[NSString stringWithFormat:@"CHAT chat %@ %hu", address, [self port]]];
}

- (void) directClientConnection:(MVDirectClientConnection *) connection willDisconnectWithError:(NSError *) error {
	NSLog(@"DCC chat willDisconnectWithError: %@", error );
	if( [self status] != MVDirectChatConnectionStoppedStatus )
		[self _setStatus:MVDirectChatConnectionErrorStatus];
}

- (void) directClientConnectionDidDisconnect:(MVDirectClientConnection *) connection {
	if( [self status] != MVDirectChatConnectionStoppedStatus )
		[self _setStatus:MVDirectChatConnectionErrorStatus];
}

- (void) directClientConnection:(MVDirectClientConnection *) connection didReadData:(NSData *) data withTag:(long) tag {
	const char *bytes = (const char *)[data bytes];
	unsigned int len = [data length];
	const char *end = bytes + len - 2; // minus the line endings
	BOOL ctcp = ( *bytes == '\001' && [data length] > 3 ); // three is the one minimum line ending and two \001 chars

	if( *end != '\x0D' )
		end = bytes + len - 1; // this client only uses \x0A for the message line ending, lets work with it

	if( ctcp ) {
		const char *line = bytes + 1; // skip the first \001 char
		const char *current = line;

		if( *( end - 1 ) == '\001' )
			end = end - 1; // minus the last \001 char

		while( line != end && *line != ' ' ) line++;

		NSString *command = [[NSString allocWithZone:nil] initWithBytes:current length:(line - current) encoding:NSASCIIStringEncoding];
		NSData *arguments = nil;
		if( line != end ) {
			line++;
			arguments = [[NSData allocWithZone:nil] initWithBytes:line length:(end - line)];
		}

		if( [command isCaseInsensitiveEqualToString:@"ACTION"] && arguments ) {
			// special case ACTION and send it out like a message with the action flag
			[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVDirectChatConnectionGotMessageNotification object:self userInfo:[NSDictionary dictionaryWithObjectsAndKeys:arguments, @"message", [NSString locallyUniqueString], @"identifier", [NSNumber numberWithBool:YES], @"action", nil]];
		}

		[command release];
		[arguments release];
	} else {
		NSData *msg = [[NSData allocWithZone:nil] initWithBytes:bytes length:(end - bytes)];
		[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVDirectChatConnectionGotMessageNotification object:self userInfo:[NSDictionary dictionaryWithObjectsAndKeys:msg, @"message", [NSString locallyUniqueString], @"identifier", nil]];
		[msg release];
	}

	[self _readNextMessage];
}
@end

#pragma mark -

@implementation MVDirectChatConnection (MVDirectChatConnectionPrivate)
- (id) initWithUser:(MVChatUser *) chatUser {
	if( ( self = [super init] ) ) {
		_status = MVDirectChatConnectionHoldingStatus;
		_encoding = NSUTF8StringEncoding;
		_outgoingChatFormat = MVChatConnectionDefaultMessageFormat;
		_user = [chatUser retain];
		_host = [[NSHost currentHost] retain];
	}

	return self;
}

- (void) _writeMessage:(NSData *) message {
	MVAssertCorrectThreadRequired( [_directClientConnection connectionThread] );
	[_directClientConnection writeData:message withTimeout:-1 withTag:0];
}

- (void) _readNextMessage {
	MVAssertCorrectThreadRequired( [_directClientConnection connectionThread] );

	static NSData *delimiter = nil;
	// DCC chat messages end in \x0D\x0A, but some non-compliant clients only use \x0A
	if( ! delimiter ) delimiter = [[NSData allocWithZone:nil] initWithBytes:"\x0A" length:1];
	[_directClientConnection readDataToData:delimiter withTimeout:-1. withTag:0];
}

- (void) _setStatus:(MVDirectChatConnectionStatus) newStatus {
	_status = newStatus;
}

- (void) _setStartDate:(NSDate *) newStartDate {
	MVSafeRetainAssign( &_startDate, newStartDate );
}

- (void) _setHost:(NSHost *) newHost {
	MVSafeRetainAssign( &_host, newHost );
}

- (void) _setPort:(unsigned short) newPort {
	_port = newPort;
}

- (void) _setPassive:(BOOL) isPassive {
	_passive = isPassive;
}

- (void) _setLocalRequest:(BOOL) localRequest {
	_localRequest = localRequest;
}

- (void) _setPassiveIdentifier:(unsigned int) identifier {
	_passiveId = identifier;
}

- (unsigned int) _passiveIdentifier {
	return _passiveId;
}

- (void) _postError:(NSError *) error {
	[self _setStatus:MVDirectChatConnectionErrorStatus];

	MVSafeRetainAssign( &_lastError, error );

	NSDictionary *info = [[NSDictionary allocWithZone:nil] initWithObjectsAndKeys:error, @"error", nil];
	[[NSNotificationCenter defaultCenter] postNotificationOnMainThreadWithName:MVDirectChatConnectionErrorOccurredNotification object:self userInfo:info];
	[info release];
}
@end
