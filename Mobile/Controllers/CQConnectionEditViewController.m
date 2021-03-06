#import "CQConnectionEditViewController.h"

#import "CQColloquyApplication.h"
#import "CQConnectionAdvancedEditController.h"
#import "CQConnectionPushEditController.h"
#import "CQConnectionsController.h"
#import "CQIgnoreRulesController.h"
#import "CQPreferencesIgnoreEditViewController.h"
#import "CQPreferencesListChannelEditViewController.h"
#import "CQPreferencesDeleteCell.h"
#import "CQPreferencesListViewController.h"
#import "CQPreferencesSwitchCell.h"
#import "CQPreferencesTextCell.h"
#import "KAIgnoreRule.h"
#import "NSStringAdditions.h"

#import <ChatCore/MVChatConnection.h>

static unsigned short ServerTableSection = 0;
static unsigned short PushTableSection = 1;
static unsigned short IdentityTableSection = 2;
static unsigned short AutomaticTableSection = 3;
static unsigned short MultitaskTableSection = 4;
static unsigned short IgnoreTableSection = 5;
static unsigned short AdvancedTableSection = 6;
static unsigned short DeleteTableSection = 7;

#if TARGET_IPHONE_SIMULATOR
static BOOL pushAvailable = NO;
#else
static BOOL pushAvailable = YES;
#endif

static inline __attribute__((always_inline)) BOOL isDefaultValue(NSString *string) {
	return [string isEqualToString:@"<<default>>"];
}

static inline __attribute__((always_inline)) BOOL isPlaceholderValue(NSString *string) {
	return [string isEqualToString:@"<<placeholder>>"];
}

#pragma mark -

@implementation CQConnectionEditViewController

+ (void) initialize {
	static BOOL initialized;

	if (initialized)
		return;

	initialized = YES;

	if (!pushAvailable) {
		--IdentityTableSection;
		--AutomaticTableSection;
		--MultitaskTableSection;
		--AdvancedTableSection;
		--IgnoreTableSection;
		--DeleteTableSection;
	}

	if (![UIDevice currentDevice].multitaskingSupported) {
		--IgnoreTableSection;
		--AdvancedTableSection;
		--DeleteTableSection;
	}
}

- (id) init {
	return (self = [super initWithStyle:UITableViewStyleGrouped]);
}

#pragma mark -

- (void) viewWillAppear:(BOOL) animated {
	[super viewWillAppear:animated];

	if (pushAvailable)
		[self.tableView updateCellAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:PushTableSection] withAnimation:UITableViewRowAnimationNone];
	[self.tableView updateCellAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:AutomaticTableSection] withAnimation:UITableViewRowAnimationNone];
}

#pragma mark -

- (void) setNewConnection:(BOOL)newConnection {
	if (_newConnection ==  newConnection)
		return;

	_newConnection = newConnection;

	if (_newConnection) self.title = NSLocalizedString(@"New Connection", @"New Connection view title");
	else self.title = _connection.displayName;
}

- (void) setConnection:(MVChatConnection *) connection {
	_connection = connection;

	if (!_newConnection)
		self.title = connection.displayName;

	[self.tableView setContentOffset:CGPointZero animated:NO];
	[self.tableView reloadData];
}

#pragma mark -

- (void) showDefaultServerList {
	if (!_servers)
		_servers = [NSArray arrayWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Servers" ofType:@"plist"]];

	CQPreferencesListViewController *listViewController = [[CQPreferencesListViewController alloc] init];
	NSMutableArray *servers = [[NSMutableArray alloc] init];
	NSUInteger selectedServerIndex = NSNotFound;

	NSUInteger index = 0;
	for (NSDictionary *serverInfo in _servers) {
		NSString *name = serverInfo[@"Name"];
		NSString *address = serverInfo[@"Address"];
		NSAssert(name.length, @"Server name required.");

		[servers addObject:name];

		if ([address isEqualToString:_connection.server])
			selectedServerIndex = index;

		++index;
	}

	listViewController.title = NSLocalizedString(@"Servers", @"Servers view title");
	listViewController.itemImage = [UIImage imageNamed:@"server.png"];
	listViewController.allowEditing = NO;
	listViewController.items = servers;
	listViewController.selectedItemIndex = selectedServerIndex;

	listViewController.target = self;
	listViewController.action = @selector(defaultServerPicked:);

	[self endEditing];

	[self.navigationController pushViewController:listViewController animated:YES];
}

#pragma mark -

- (NSInteger) numberOfSectionsInTableView:(UITableView *) tableView {
	NSInteger count = 8;
	if (self.newConnection || !_connection.directConnection)
		count -= 1;
	if (!pushAvailable)
		count -= 1;
	if (![UIDevice currentDevice].multitaskingSupported)
		count -= 1;
	return count;
}

- (NSInteger) tableView:(UITableView *) tableView numberOfRowsInSection:(NSInteger) section {
	if (section == ServerTableSection)
		return 2;
	if (pushAvailable && section == PushTableSection)
		return 1;
	if (section == IdentityTableSection)
		return 2;
	if (section == AutomaticTableSection)
		return 3;
	if ([UIDevice currentDevice].multitaskingSupported && section == MultitaskTableSection)
		return 1;
	if (section == AdvancedTableSection)
		return 1;
	if (section == DeleteTableSection)
		return 1;
	if (section == IgnoreTableSection)
		return 1;
	return 0;
}

- (NSIndexPath *) tableView:(UITableView *) tableView willSelectRowAtIndexPath:(NSIndexPath *) indexPath {
	if (pushAvailable && indexPath.section == PushTableSection && indexPath.row == 0)
		return indexPath;
	if (indexPath.section == AutomaticTableSection && indexPath.row == 2)
		return indexPath;
	if (indexPath.section == AdvancedTableSection && indexPath.row == 0)
		return indexPath;
	if (indexPath.section == IgnoreTableSection)
		return indexPath;
	return nil;
}

- (void) tableView:(UITableView *) tableView didSelectRowAtIndexPath:(NSIndexPath *) indexPath {
	if (pushAvailable && indexPath.section == PushTableSection && indexPath.row == 0) {
		CQConnectionPushEditController *pushEditViewController = [[CQConnectionPushEditController alloc] init];

		pushEditViewController.navigationItem.prompt = self.navigationItem.prompt;
		pushEditViewController.connection = _connection;

		[self endEditing];

		[self.navigationController pushViewController:pushEditViewController animated:YES];


		return;
	}

	if (indexPath.section == AutomaticTableSection && indexPath.row == 2) {
		CQPreferencesListViewController *listViewController = [[CQPreferencesListViewController alloc] init];

		listViewController.title = NSLocalizedString(@"Join Rooms", @"Join Rooms view title");
		listViewController.items = _connection.automaticJoinedRooms;
		if ([[CQSettingsController settingsController] boolForKey:@"CQShowsChatIcons"])
			listViewController.itemImage = [UIImage imageNamed:@"roomIconSmall.png"];
		listViewController.addItemLabelText = NSLocalizedString(@"Add chat room", @"Add chat room label");
		listViewController.noItemsLabelText = NSLocalizedString(@"No chat rooms", @"No chat rooms label");
		listViewController.editViewTitle = NSLocalizedString(@"Edit Chat Room", @"Edit Chat Room view title");
		listViewController.editPlaceholder = NSLocalizedString(@"Chat Room", @"Chat Room placeholder");

		CQPreferencesListChannelEditViewController *editingViewController = [[CQPreferencesListChannelEditViewController alloc] init];
		editingViewController.connection = _connection;
		listViewController.customEditingViewController = editingViewController;

		listViewController.target = self;
		listViewController.action = @selector(automaticJoinRoomsChanged:);

		[self endEditing];

		[self.navigationController pushViewController:listViewController animated:YES];

		return;
	}

	if (indexPath.section == IgnoreTableSection) {
		CQPreferencesListViewController *listViewController = [[CQPreferencesListViewController alloc] init];
		listViewController.title = NSLocalizedString(@"Ignore List", @"Ignore List view title");
		listViewController.items = _connection.ignoreController.ignoreRules;
		listViewController.addItemLabelText = NSLocalizedString(@"Add New Ignore", @"Add New Ignore label");
		listViewController.noItemsLabelText = NSLocalizedString(@"No Ignores Found", @"No Ignores Found");
		listViewController.editViewTitle = NSLocalizedString(@"Edit Ignore Rule", @"Edit Ignore Rule");
		listViewController.editPlaceholder = NSLocalizedString(@"Nickname", @"Nickname");

		CQPreferencesIgnoreEditViewController *ignoreEditViewController = [[CQPreferencesIgnoreEditViewController alloc] initWithConnection:_connection];
		listViewController.customEditingViewController = ignoreEditViewController;
		listViewController.target = self;
		listViewController.action = @selector(ignoreListChanged:);

		[self endEditing];

		[self.navigationController pushViewController:listViewController animated:YES];

		return;
	}

	if (indexPath.section == AdvancedTableSection && indexPath.row == 0) {
		CQConnectionAdvancedEditController *advancedEditViewController = [[CQConnectionAdvancedEditController alloc] init];

		advancedEditViewController.navigationItem.prompt = self.navigationItem.prompt;
		advancedEditViewController.newConnection = _newConnection;
		advancedEditViewController.connection = _connection;

		[self endEditing];

		[self.navigationController pushViewController:advancedEditViewController animated:YES];

		return;
	}
}

- (NSString *) tableView:(UITableView *) tableView titleForHeaderInSection:(NSInteger) section {
	if (section == ServerTableSection)
		return NSLocalizedString(@"Internet Relay Chat Server", @"Internet Relay Chat Server section title");
	if (section == IdentityTableSection)
		return NSLocalizedString(@"Network Identity", @"Network Identity section title");
	if (section == AutomaticTableSection)
		return NSLocalizedString(@"Automatic Actions", @"Automatic Actions section title");
	return nil;
}

- (UITableViewCell *) tableView:(UITableView *) tableView cellForRowAtIndexPath:(NSIndexPath *) indexPath {
	if (indexPath.section == ServerTableSection) {
		CQPreferencesTextCell *cell = [CQPreferencesTextCell reusableTableViewCellInTableView:tableView];

		if (indexPath.row == 1) {
			cell.textLabel.text = NSLocalizedString(@"Address", @"Address connection setting label");
			cell.textField.text = (isPlaceholderValue(_connection.server) ? @"" : _connection.server);
			cell.textField.placeholder = (_newConnection ? @"irc.example.com" : @"");

			if (_connection.directConnection) {
				cell.textField.keyboardType = UIKeyboardTypeURL;
				cell.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
				cell.textField.autocorrectionType = UITextAutocorrectionTypeNo;
				cell.textEditAction = @selector(serverChanged:);
				cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
			} else {
				cell.enabled = NO;
			}

			cell.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"Address: %@", @"Voiceover address label"), cell.textField.text];
			cell.accessibilityHint = NSLocalizedString(@"Required", @"Voiceover required label");
		} else if (indexPath.row == 0) {
			cell.textLabel.text = NSLocalizedString(@"Description", @"Description connection setting label");
			cell.textField.text = (![_connection.displayName isEqualToString:_connection.server] ? _connection.displayName : @"");
			cell.textField.placeholder = NSLocalizedString(@"Optional", @"Optional connection setting placeholder");
			cell.textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
			cell.textEditAction = @selector(descriptionChanged:);

			cell.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"Description: %@", @"Voiceover description label"), cell.textField.text];
			cell.accessibilityHint = NSLocalizedString(@"Optional", @"Voiceover optional label");
			cell.accessibilityHint = NSLocalizedString(@"Optional", @"Voiceover optional label");
		}
		
		return cell;
	} else if (pushAvailable && indexPath.section == PushTableSection && indexPath.row == 0) {
		UITableViewCell *cell = [UITableViewCell reusableTableViewCellWithStyle:UITableViewCellStyleValue1 inTableView:tableView];

		cell.textLabel.text = NSLocalizedString(@"Push Notifications", @"Push Notifications connection setting label");
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

		if (_connection.pushNotifications)
			cell.detailTextLabel.text = NSLocalizedString(@"On", @"On label");
		else cell.detailTextLabel.text = NSLocalizedString(@"Off", @"Off label");

		if (_connection.pushNotifications)
			cell.accessibilityLabel = NSLocalizedString(@"Push Notifications: On", @"Voiceover push notifications on label");
		else cell.accessibilityLabel = NSLocalizedString(@"Push Notifications: Off", @"Voiceover push notification off label");

		return cell;
	} else if (indexPath.section == IdentityTableSection) {
		CQPreferencesTextCell *cell = [CQPreferencesTextCell reusableTableViewCellInTableView:tableView];

		if (indexPath.row == 0) {
			cell.textLabel.text = NSLocalizedString(@"Nickname", @"Nickname connection setting label");
			cell.textField.text = (isDefaultValue(_connection.preferredNickname) ? @"" : _connection.preferredNickname);
			cell.textField.placeholder = [MVChatConnection defaultNickname];
			cell.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
			cell.textField.autocorrectionType = UITextAutocorrectionTypeNo;
			cell.textEditAction = @selector(nicknameChanged:);

			cell.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"Nickname: %@", @"Voiceover nickname label"), (cell.textField.text.length ? cell.textField.text : cell.textField.placeholder)];
		} else if (indexPath.row == 1) {
			cell.textLabel.text = NSLocalizedString(@"Real Name", @"Real Name connection setting label");
			cell.textField.text = (isDefaultValue(_connection.realName) ? @"" : _connection.realName);
			cell.textField.placeholder = [MVChatConnection defaultRealName];

			if (_connection.directConnection) {
				cell.textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
				cell.textEditAction = @selector(realNameChanged:);
			} else {
				cell.enabled = NO;
			}

			cell.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"Real Name: %@", @"Voiceover real name label"), (cell.textField.text.length ? cell.textField.text : cell.textField.placeholder)];
		}

		return cell;
	} else if (indexPath.section == AutomaticTableSection) {
		if (indexPath.row == 0) {
			CQPreferencesSwitchCell *cell = [CQPreferencesSwitchCell reusableTableViewCellInTableView:tableView];

			cell.switchAction = @selector(autoConnectChanged:);
			cell.textLabel.text = NSLocalizedString(@"Connect at Launch", @"Connect at Launch connection setting label");
			cell.on = _connection.automaticallyConnect;

			if (_connection.automaticallyConnect)
				cell.accessibilityLabel = NSLocalizedString(@"Connect at Launch: On", @"Voiceover connect at launch on label");
			else cell.accessibilityLabel = NSLocalizedString(@"Connect at Launch: Off", @"Voiceover connect at launch off label");

			return cell;
		} else if (indexPath.row == 1) {
			CQPreferencesSwitchCell *cell = [CQPreferencesSwitchCell reusableTableViewCellInTableView:tableView];

			cell.switchAction = @selector(autoOpenConsoleChanged:);
			cell.textLabel.text = NSLocalizedString(@"Show Console", @"Show Console connection setting label");
			cell.on = _connection.consoleOnLaunch;

			if (_connection.automaticallyConnect)
				cell.accessibilityLabel = NSLocalizedString(@"Open Console on Launch: On", @"Voiceover connect at launch on label");
			else cell.accessibilityLabel = NSLocalizedString(@"Open Console on Launch: Off", @"Voiceover connect at launch off label");

			return cell;
		} else if (indexPath.row == 2) {
			UITableViewCell *cell = [UITableViewCell reusableTableViewCellWithStyle:UITableViewCellStyleValue1 inTableView:tableView];

			cell.textLabel.text = NSLocalizedString(@"Join Rooms", @"Join Rooms connection setting label");
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

			NSArray *rooms = _connection.automaticJoinedRooms;
			if (rooms.count)
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%tu", rooms.count];
			else cell.detailTextLabel.text = NSLocalizedString(@"None", @"None label");

			if (rooms.count)
				cell.accessibilityLabel = [NSString stringWithFormat:NSLocalizedString(@"Join Rooms: %u rooms", @"Voiceover join rooms label"), rooms.count];
			else cell.accessibilityLabel = NSLocalizedString(@"Join Rooms: None", @"Voiceover join rooms none label");

			return cell;
		}
	} else if ([UIDevice currentDevice].multitaskingSupported && indexPath.section == MultitaskTableSection && indexPath.row == 0) {
		CQPreferencesSwitchCell *cell = [CQPreferencesSwitchCell reusableTableViewCellInTableView:tableView];

		cell.switchAction = @selector(multitaskingChanged:);
		cell.textLabel.text = NSLocalizedString(@"Allow Multitasking", @"Multitasking connection setting label");
		cell.on = _connection.multitaskingSupported && [[CQSettingsController settingsController] doubleForKey:@"CQMultitaskingTimeout"] > 0;

		if (_connection.multitaskingSupported)
			cell.accessibilityLabel = NSLocalizedString(@"Allow Multitasking: On", @"Voiceover allow multitasking on label");
		else cell.accessibilityLabel = NSLocalizedString(@"Allow Multitasking: Off", @"Voiceover allow multitasking off label");

		return cell;
	} else if (indexPath.section == AdvancedTableSection && indexPath.row == 0) {
		UITableViewCell *cell = [UITableViewCell reusableTableViewCellInTableView:tableView];

		cell.textLabel.text = NSLocalizedString(@"Advanced", @"Advanced connection setting label");
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

		return cell;
	} else if (indexPath.section == IgnoreTableSection) {
		UITableViewCell *cell = [UITableViewCell reusableTableViewCellInTableView:tableView];

		cell.textLabel.text = NSLocalizedString(@"Ignore List", @"Ignore List");
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

		return cell;
	} else if (indexPath.section == DeleteTableSection && indexPath.row == 0) {
		CQPreferencesDeleteCell *cell = [CQPreferencesDeleteCell reusableTableViewCellInTableView:tableView];

		cell.deleteAction = @selector(deleteConnection:);

		[cell.deleteButton setTitle:NSLocalizedString(@"Delete Connection", @"Delete Connection button title") forState:UIControlStateNormal];

		return cell;
	}

	NSAssert(NO, @"Should not reach this point.");
	return nil;
}

- (void) tableView:(UITableView *) tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *) indexPath {
	if (indexPath.section == ServerTableSection && indexPath.row == 1)
		[self showDefaultServerList];
}

#pragma mark -

- (void) defaultServerPicked:(CQPreferencesListViewController *) sender {
	if (sender.selectedItemIndex == NSNotFound)
		return;

	NSDictionary *serverInfo = _servers[sender.selectedItemIndex];
	_connection.displayName = serverInfo[@"Name"];
	_connection.server = serverInfo[@"Address"];

	if (!_newConnection)
		self.title = _connection.displayName;

	if (self.navigationItem.rightBarButtonItem.tag == UIBarButtonSystemItemSave)
		self.navigationItem.rightBarButtonItem.enabled = YES;

	[self.tableView updateCellAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:ServerTableSection] withAnimation:UITableViewRowAnimationNone];
	[self.tableView updateCellAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:ServerTableSection] withAnimation:UITableViewRowAnimationNone];
}

- (void) serverChanged:(CQPreferencesTextCell *) sender {
	if (sender.textField.text.length || _newConnection) {
		if ([sender.textField.text isEqualToString:@"irc://"] || [sender.textField.text isEqualToString:@"ircs://"])
			return;
		_connection.server = (sender.textField.text.length ? sender.textField.text : @"<<placeholder>>");
		if (!_newConnection)
			self.title = _connection.displayName;
	}

	sender.textField.text = (isPlaceholderValue(_connection.server) ? @"" : _connection.server);

	if (self.navigationItem.rightBarButtonItem.tag == UIBarButtonSystemItemSave)
		self.navigationItem.rightBarButtonItem.enabled = !isPlaceholderValue(_connection.server);
}

- (void) nicknameChanged:(CQPreferencesTextCell *) sender {
	if (sender.textField.text.length)
		_connection.preferredNickname = sender.textField.text;
	else _connection.preferredNickname = (_newConnection ? @"<<default>>" : sender.textField.placeholder);

	[_connection savePasswordsToKeychain];

	sender.textField.text = (isDefaultValue(_connection.preferredNickname) ? @"" : _connection.preferredNickname);
}

- (void) realNameChanged:(CQPreferencesTextCell *) sender {
	if (sender.textField.text.length)
		_connection.realName = sender.textField.text;
	else _connection.realName = (_newConnection ? @"<<default>>" : sender.textField.placeholder);

	sender.textField.text = (isDefaultValue(_connection.realName) ? @"" : _connection.realName);
}

- (void) descriptionChanged:(CQPreferencesTextCell *) sender {
	_connection.displayName = sender.textField.text;

	if (!_newConnection)
		self.title = _connection.displayName;
}

- (void) autoConnectChanged:(CQPreferencesSwitchCell *) sender {
	_connection.automaticallyConnect = sender.on;
}

- (void) autoOpenConsoleChanged:(CQPreferencesSwitchCell *) sender {
	_connection.consoleOnLaunch = sender.on;
}

- (void) automaticJoinRoomsChanged:(CQPreferencesListViewController *) sender {
	_connection.automaticJoinedRooms = sender.items;

	[self.tableView beginUpdates];
	[self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForItem:2 inSection:AutomaticTableSection]] withRowAnimation:UITableViewRowAnimationAutomatic];
	[self.tableView endUpdates];

}

- (void) ignoreListChanged:(CQPreferencesListViewController *) sender {
	for (KAIgnoreRule *rule in sender.items) {
		if (!rule.user.length && !rule.mask.length)
			continue;

		if (![_connection.ignoreController.ignoreRules containsObject:rule])
			[_connection.ignoreController addIgnoreRule:rule];
	}

	for (KAIgnoreRule *rule in _connection.ignoreController.ignoreRules) {
		if (![sender.items containsObject:rule] || (!rule.user.length && !rule.mask.length))
			[_connection.ignoreController removeIgnoreRule:rule];
	}

	[_connection.ignoreController synchronize];
}

- (void) multitaskingChanged:(CQPreferencesSwitchCell *) sender {
	if (sender.on && ![[CQSettingsController settingsController] doubleForKey:@"CQMultitaskingTimeout"]) {
		[[CQSettingsController settingsController] setDouble:300 forKey:@"CQMultitaskingTimeout"];

		UIAlertView *alert = [[UIAlertView alloc] init];

		alert.title = NSLocalizedString(@"Multitasking Enabled", @"Multitasking enabled alert title");
		alert.message = NSLocalizedString(@"Multitasking was disabled for Colloquy, but has been enabled again with a timeout of 5 minutes.", @"Multitasking enabled alert message");

		alert.cancelButtonIndex = [alert addButtonWithTitle:NSLocalizedString(@"Dismiss", @"Dismiss alert button title")];

		[alert show];
	}

	_connection.multitaskingSupported = sender.on;
}

- (void) deleteConnection:(id) sender {
	if ([[UIDevice currentDevice] isPadModel]) {
		UIAlertView *alert = [[UIAlertView alloc] init];
		alert.delegate = self;

		alert.title = NSLocalizedString(@"Delete Connection", @"Delete Connection alert title");

		alert.cancelButtonIndex = [alert addButtonWithTitle:NSLocalizedString(@"Dismiss", @"Dismiss alert button title")];
		[alert addButtonWithTitle:NSLocalizedString(@"Delete", @"Delete alert button title")];

		[alert show];

		return;
	}

	UIActionSheet *sheet = [[UIActionSheet alloc] init];
	sheet.delegate = self;

	sheet.destructiveButtonIndex = [sheet addButtonWithTitle:NSLocalizedString(@"Delete Connection", @"Delete Connection button title")];
	sheet.cancelButtonIndex = [sheet addButtonWithTitle:NSLocalizedString(@"Cancel", @"Cancel button title")];

	[[CQColloquyApplication sharedApplication] showActionSheet:sheet forSender:sender animated:YES];
}

#pragma mark -

- (void) alertView:(UIAlertView *) alertView clickedButtonAtIndex:(NSInteger) buttonIndex {
	if (buttonIndex == alertView.cancelButtonIndex)
		return;
	[[CQConnectionsController defaultController] removeConnection:_connection];
	[self.navigationController dismissViewControllerAnimated:YES completion:NULL];
}

#pragma mark -

- (void) actionSheet:(UIActionSheet *) actionSheet clickedButtonAtIndex:(NSInteger) buttonIndex {
	if (buttonIndex == actionSheet.cancelButtonIndex)
		return;
	[[CQConnectionsController defaultController] removeConnection:_connection];
	[self.navigationController dismissViewControllerAnimated:YES completion:NULL];
}
@end
