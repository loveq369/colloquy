#import <Cocoa/Cocoa.h>
#import "JVStandardCommands.h"
#import "MVConnectionsController.h"
#import "JVChatController.h"
#import "JVDirectChat.h"
#import "JVChatRoom.h"
#import "MVChatConnection.h"

@implementation JVStandardCommands
- (id) initWithBundle:(NSBundle *) bundle {
	self = [super init];
	return self;
}

- (BOOL) processUserCommand:(NSString *) command withArguments:(NSAttributedString *) arguments toRoom:(NSString *) room forConnection:(MVChatConnection *) connection {
	MVConnectionsController *connectionsController = (MVConnectionsController *)[NSClassFromString( @"MVConnectionsController" ) defaultManager];
	JVChatController *chatController = (JVChatController *)[NSClassFromString( @"JVChatController" ) defaultManager];
	NSStringEncoding encoding = [(JVChatRoom *)[chatController chatViewControllerForRoom:room withConnection:connection ifExists:YES] encoding];
	if( [command isEqualToString:@"me"] || [command isEqualToString:@"action"] || [command isEqualToString:@"say"] ) {
		if( [arguments length] ) {
			JVChatRoom *chatView = [chatController chatViewControllerForRoom:room withConnection:connection ifExists:YES];
			[chatView echoSentMessageToDisplay:arguments asAction:( [command isEqualToString:@"me"] || [command isEqualToString:@"action"] )];
			[connection sendMessageToChatRoom:room attributedMessage:arguments withEncoding:encoding asAction:( [command isEqualToString:@"me"] || [command isEqualToString:@"action"] )];
		}
		return YES;
	} else if( [command isEqualToString:@"msg"] || [command isEqualToString:@"query"] ) {
		NSString *to = nil;
		NSAttributedString *msg = nil;
		NSScanner *scanner = [NSScanner scannerWithString:[arguments string]];

		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&to];

		if( ! to ) return NO;

		if( [arguments length] >= [scanner scanLocation] + 1 ) {
			[scanner setScanLocation:[scanner scanLocation] + 1];
			msg = [arguments attributedSubstringFromRange:NSMakeRange( [scanner scanLocation], [arguments length] - [scanner scanLocation] )];
		}

		if( [command isEqualToString:@"query"] ) {
			JVDirectChat *chatView = [chatController chatViewControllerForUser:to withConnection:connection ifExists:NO];
			if( [msg length] ) [chatView echoSentMessageToDisplay:msg asAction:NO];
		}

		if( [msg length] ) [connection sendMessageToUser:to attributedMessage:msg withEncoding:encoding asAction:NO];
		return YES;
	} else if( [command isEqualToString:@"amsg"] || [command isEqualToString:@"ame"] ) {
		if( ! [arguments length] ) return NO;
		NSEnumerator *enumerator = [[chatController chatViewControllersOfClass:NSClassFromString( @"JVChatRoom" )] objectEnumerator];
		id item = nil;
		while( ( item = [enumerator nextObject] ) ) {
			[connection sendMessageToChatRoom:[item target] attributedMessage:arguments withEncoding:encoding asAction:[command isEqualToString:@"ame"]];
			[item echoSentMessageToDisplay:arguments asAction:[command isEqualToString:@"ame"]];
		}
		return YES;
	} else if( [command isEqualToString:@"nick"] ) {
		NSString *nick = nil;
		if( ! [arguments length] ) return NO;
		[[NSScanner scannerWithString:[arguments string]] scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&nick];
		[connection setNickname:nick];
		return YES;
	} else if( [command isEqualToString:@"away"] ) {
		[connection setAwayStatusWithMessage:[arguments string]];
		return YES;
	} else if( [command isEqualToString:@"join"] ) {
		NSArray *rooms = [[arguments string] componentsSeparatedByString:@" "];
		NSEnumerator *enumerator = [rooms objectEnumerator];
		id item = nil;
		if( ! [rooms count] ) return NO;
		while( ( item = [enumerator nextObject] ) )
			[connection joinChatForRoom:item];
		return YES;
	} else if( [command isEqualToString:@"part"] || [command isEqualToString:@"leave"] ) {
		if( ! [arguments length] ) {
			[connection partChatForRoom:room];
		} else {
			NSArray *rooms = [[arguments string] componentsSeparatedByString:@" "];
			NSEnumerator *enumerator = [rooms objectEnumerator];
			id item = nil;
			if( ! [rooms count] ) return NO;
			while( ( item = [enumerator nextObject] ) )
				[connection partChatForRoom:item];
		}
		return YES;
	} else if( [command isEqualToString:@"server"] ) {
		NSURL *url = nil;
		if( [arguments string] && ( url = [NSURL URLWithString:[arguments string]] ) ) {
			[connectionsController handleURL:url andConnectIfPossible:YES];
		} else if( [arguments string] ) {
			NSString *address = nil;
			int port = 0;
			NSScanner *scanner = [NSScanner scannerWithString:[arguments string]];
			[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&address];
			if( [arguments length] >= [scanner scanLocation] + 1 ) {
				[scanner setScanLocation:[scanner scanLocation] + 1];
				[scanner scanInt:&port];
			}
			
			if( address && port ) url = [NSURL URLWithString:[NSString stringWithFormat:@"irc://%@:%du", MVURLEncodeString( address ), port]];
			else if( address && ! port ) url = [NSURL URLWithString:[NSString stringWithFormat:@"irc://%@", MVURLEncodeString( address )]];
			else [connectionsController newConnection:nil];

			if( url ) [connectionsController handleURL:url andConnectIfPossible:YES];
		} else [connectionsController newConnection:nil];
		return YES;
	} else if( [command isEqualToString:@"dcc"] ) {
		NSString *subcmd = nil;
		NSScanner *scanner = [NSScanner scannerWithString:[arguments string]];
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&subcmd];
		if( [subcmd isEqualToString:@"send"] ) {
			NSString *to = nil, *path = nil;

			[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&to];
			if( [arguments length] >= [scanner scanLocation] + 1 ) {
				[scanner setScanLocation:[scanner scanLocation] + 1];
				path = [[arguments string] substringFromIndex:[scanner scanLocation]];
				if( ! [[NSFileManager defaultManager] fileExistsAtPath:path] ) return NO;
			}

			if( ! to ) return NO;

			if( ! [path length] ) {
				NSOpenPanel *panel = [NSOpenPanel openPanel];
				[panel setResolvesAliases:YES];
				[panel setCanChooseFiles:YES];
				[panel setCanChooseDirectories:NO];
				[panel setAllowsMultipleSelection:YES];
				if( [panel runModalForTypes:nil] == NSOKButton ) {
					NSEnumerator *enumerator = [[panel filenames] objectEnumerator];
					while( ( path = [enumerator nextObject] ) )
						[connection sendFileToUser:to withFilePath:path];
				}
			} else [connection sendFileToUser:to withFilePath:path];
			return YES;
		}
		return NO;
	} else if( [command isEqualToString:@"ctcp"] ) {
		NSString *to = nil, *ctcpRequest = nil, *ctcpArgs = nil;
		NSScanner *scanner = [NSScanner scannerWithString:[arguments string]];

		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&to];
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&ctcpRequest];
		[scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\n\r"] intoString:&ctcpArgs];

		if( ! to || ! ctcpRequest ) return NO;

		[connection sendSubcodeRequest:ctcpRequest toUser:to withArguments:ctcpArgs];
		return YES;
	} else if( [command isEqualToString:@"topic"] ) {
		if( ! [arguments length] ) return NO;
		[connection setTopic:arguments withEncoding:encoding forRoom:room];
		return YES;
	} else if( [command isEqualToString:@"mode"] ) {
		NSRange vrange, orange, vsrange, osrange;
		BOOL handled = NO;
		NSScanner *scanner = [NSScanner scannerWithString:[arguments string]];
		NSString *modes = nil, *who = nil;

		if( ! [arguments length] ) return NO;

		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&modes];
		vrange = [modes rangeOfString:@"v"];
		if( vrange.location != NSNotFound ) vsrange = [modes rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"-+"] options:NSBackwardsSearch range:NSMakeRange( 0, vrange.location )];
		orange = [modes rangeOfString:@"o"];
		if( orange.location != NSNotFound ) osrange = [modes rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"-+"] options:NSBackwardsSearch range:NSMakeRange( 0, orange.location )];

		if( [arguments length] >= [scanner scanLocation] + 1 )
			[scanner setScanLocation:[scanner scanLocation] + 1];
		else return NO;

		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&who];

		if( ! who ) return NO;

		if( vrange.location != NSNotFound && vsrange.location != NSNotFound ) {
			if( [modes characterAtIndex:vsrange.location] == '+' ) [connection voiceMember:who inRoom:room];
			else [connection devoiceMember:who inRoom:room];
			handled = YES;
		}

		if( orange.location != NSNotFound && osrange.location != NSNotFound ) {
			if( [modes characterAtIndex:osrange.location] == '+' ) [connection promoteMember:who inRoom:room];
			else [connection demoteMember:who inRoom:room];
			handled = YES;
		}
		return handled;
	} else if( [command isEqualToString:@"names"] ) {
//		MVChatWindowController *window = [chatWindowControllerClass chatWindowForRoom:room withConnection:connection ifExists:YES];
//		[window openMemberDrawer:nil];
//		return YES;
	} else if( [command isEqualToString:@"clear"] ) {
//		MVChatWindowController *window = [chatWindowControllerClass chatWindowForRoom:room withConnection:connection ifExists:YES];
//		[window clearDisplay:nil];
//		return YES;
	} else if( [command isEqualToString:@"kick"] ) {
		NSString *member = nil, *msg = nil;
		NSScanner *scanner = [NSScanner scannerWithString:[arguments string]];

		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&member];
		if( ! member ) return NO;

		if( [arguments length] >= [scanner scanLocation] + 1 ) {
			[scanner setScanLocation:[scanner scanLocation] + 1];
			msg = [[arguments string] substringFromIndex:[scanner scanLocation]];
		}

		[connection kickMember:member inRoom:room forReason:msg];
		return YES;
	} else if( [command isEqualToString:@"quit"] || [command isEqualToString:@"exit"] ) {
		[[NSApplication sharedApplication] terminate:nil];
		return YES;
	} else if( [command isEqualToString:@"disconnect"] ) {
		[connection disconnect];
		return YES;
	}
	return NO;
}

- (BOOL) processUserCommand:(NSString *) command withArguments:(NSAttributedString *) arguments toUser:(NSString *) user forConnection:(MVChatConnection *) connection {
	MVConnectionsController *connectionsController = (MVConnectionsController *)[NSClassFromString( @"MVConnectionsController" ) defaultManager];
	JVChatController *chatController = (JVChatController *)[NSClassFromString( @"JVChatController" ) defaultManager];
	NSStringEncoding encoding = [(JVDirectChat *)[chatController chatViewControllerForUser:user withConnection:connection ifExists:YES] encoding];
	if( [command isEqualToString:@"me"] || [command isEqualToString:@"action"] || [command isEqualToString:@"say"] ) {
		if( [arguments length] ) {
			JVDirectChat *chatView = [chatController chatViewControllerForUser:user withConnection:connection ifExists:YES];
			[chatView echoSentMessageToDisplay:arguments asAction:( [command isEqualToString:@"me"] || [command isEqualToString:@"action"] )];
			[connection sendMessageToUser:user attributedMessage:arguments withEncoding:encoding asAction:( [command isEqualToString:@"me"] || [command isEqualToString:@"action"] )];
		}
		return YES;
	} else if( [command isEqualToString:@"msg"] || [command isEqualToString:@"query"] ) {
		NSString *to = nil;
		NSAttributedString *msg = nil;
		NSScanner *scanner = [NSScanner scannerWithString:[arguments string]];

		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&to];

		if( ! to ) return NO;

		if( [arguments length] >= [scanner scanLocation] + 1 ) {
			[scanner setScanLocation:[scanner scanLocation] + 1];
			msg = [arguments attributedSubstringFromRange:NSMakeRange( [scanner scanLocation], [arguments length] - [scanner scanLocation] )];
		}

		if( [command isEqualToString:@"query"] ) {
			JVDirectChat *chatView = [chatController chatViewControllerForUser:to withConnection:connection ifExists:NO];
			if( [msg length] ) [chatView echoSentMessageToDisplay:msg asAction:NO];
		}

		if( [msg length] ) [connection sendMessageToUser:to attributedMessage:msg withEncoding:encoding asAction:NO];
		return YES;
	} else if( [command isEqualToString:@"amsg"] || [command isEqualToString:@"ame"] ) {
		if( ! [arguments length] ) return NO;
		NSEnumerator *enumerator = [[chatController chatViewControllersOfClass:NSClassFromString( @"JVChatRoom" )] objectEnumerator];
		id item = nil;
		while( ( item = [enumerator nextObject] ) ) {
			[connection sendMessageToChatRoom:[item target] attributedMessage:arguments withEncoding:encoding asAction:[command isEqualToString:@"ame"]];
			[item echoSentMessageToDisplay:arguments asAction:[command isEqualToString:@"ame"]];
		}
		return YES;
	} else if( [command isEqualToString:@"nick"] ) {
		NSString *nick = nil;
		if( ! [arguments length] ) return NO;
		[[NSScanner scannerWithString:[arguments string]] scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&nick];
		[connection setNickname:nick];
		return YES;
	} else if( [command isEqualToString:@"away"] ) {
		[connection setAwayStatusWithMessage:[arguments string]];
		return YES;
	} else if( [command isEqualToString:@"join"] ) {
		NSArray *rooms = [[arguments string] componentsSeparatedByString:@" "];
		NSEnumerator *enumerator = [rooms objectEnumerator];
		id item = nil;
		if( ! [rooms count] ) return NO;
		while( ( item = [enumerator nextObject] ) )
			[connection joinChatForRoom:item];
		return YES;
	} else if( [command isEqualToString:@"server"] ) {
		NSURL *url = nil;
		if( [arguments string] && ( url = [NSURL URLWithString:[arguments string]] ) ) {
			[connectionsController handleURL:url andConnectIfPossible:YES];
		} else if( [arguments string] ) {
			NSString *address = nil;
			int port = 0;
			NSScanner *scanner = [NSScanner scannerWithString:[arguments string]];
			[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&address];
			if( [arguments length] >= [scanner scanLocation] + 1 ) {
				[scanner setScanLocation:[scanner scanLocation] + 1];
				[scanner scanInt:&port];
			}

			if( address && port ) url = [NSURL URLWithString:[NSString stringWithFormat:@"irc://%@:%du", MVURLEncodeString( address ), port]];
			else if( address && ! port ) url = [NSURL URLWithString:[NSString stringWithFormat:@"irc://%@", MVURLEncodeString( address )]];
			else [connectionsController newConnection:nil];

			if( url ) [connectionsController handleURL:url andConnectIfPossible:YES];
		} else [connectionsController newConnection:nil];
		return YES;
	} else if( [command isEqualToString:@"ctcp"] ) {
		NSString *to = nil, *ctcpRequest = nil, *ctcpArgs = nil;
		NSScanner *scanner = [NSScanner scannerWithString:[arguments string]];
		
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&to];
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&ctcpRequest];
		[scanner scanUpToCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\n\r"] intoString:&ctcpArgs];
		
		if( ! to || ! ctcpRequest ) return NO;
		
		[connection sendSubcodeRequest:ctcpRequest toUser:to withArguments:ctcpArgs];
		return YES;
	} else if( [command isEqualToString:@"dcc"] ) {
		NSString *subcmd = nil;
		NSScanner *scanner = [NSScanner scannerWithString:[arguments string]];
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:&subcmd];
		if( [subcmd isEqualToString:@"send"] ) {
			NSString *to = nil, *path = nil;

			[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&to];
			if( [arguments length] >= [scanner scanLocation] + 1 ) {
				[scanner setScanLocation:[scanner scanLocation] + 1];
				path = [[arguments string] substringFromIndex:[scanner scanLocation]];
				if( ! [[NSFileManager defaultManager] fileExistsAtPath:path] ) return NO;
			}

			if( ! to ) return NO;

			if( ! [path length] ) {
				NSOpenPanel *panel = [NSOpenPanel openPanel];
				[panel setResolvesAliases:YES];
				[panel setCanChooseFiles:YES];
				[panel setCanChooseDirectories:NO];
				[panel setAllowsMultipleSelection:YES];
				if( [panel runModalForTypes:nil] == NSOKButton ) {
					NSEnumerator *enumerator = [[panel filenames] objectEnumerator];
					while( ( path = [enumerator nextObject] ) )
						[connection sendFileToUser:to withFilePath:path];
				}
			} else [connection sendFileToUser:to withFilePath:path];
			return YES;
		}
		return NO;
	} else if( [command isEqualToString:@"clear"] ) {
//		MVChatWindowController *window = [chatWindowControllerClass chatWindowWithUser:user withConnection:connection ifExists:YES];
//		[window clearDisplay:nil];
//		return YES;
	} else if( [command isEqualToString:@"quit"] || [command isEqualToString:@"exit"] ) {
		[[NSApplication sharedApplication] terminate:nil];
		return YES;
	} else if( [command isEqualToString:@"disconnect"] ) {
		[connection disconnect];
		return YES;
	}
	return NO;
}
@end
