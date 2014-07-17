/**
 * Name: CrashReporter
 * Type: iOS application
 * Desc: iOS app for viewing the details of a crash, determining the possible
 *       cause of said crash, and reporting this information to the developer(s)
 *       responsible.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: GPL v3 (See LICENSE file for details)
 */

#import "ContactViewController.h"

#import <MessageUI/MessageUI.h>
#import <RegexKitLite/RegexKitLite.h>

#import "CrashLogViewController.h"
#import "ModalActionSheet.h"
#import "pastie.h"

#import "IncludeInstruction.h"
#import "LinkInstruction.h"
#import "Package.h"

@interface UIColor ()
+ (id)tableCellBlueTextColor;
@end

@interface ContactViewController () <MFMailComposeViewControllerDelegate, UITableViewDataSource, UITableViewDelegate>
@end

@implementation ContactViewController {
    UITextView *textView_;
    UITableView *tableView_;

    Package *package_;
    NSString *suspect_;
    LinkInstruction *linkInstruction_;
    NSArray *includeInstructions_;
}

- (id)initWithPackage:(Package *)package suspect:(NSString *)suspect linkInstruction:(LinkInstruction *)linkInstruction includeInstructions:(NSArray *)includeInstructions {
    self = [super init];
    if (self != nil) {
        package_ = [package retain];
        suspect_ = [suspect copy];
        linkInstruction_ = [linkInstruction retain];
        includeInstructions_ = [includeInstructions copy];

        self.title = [suspect lastPathComponent];
        UIBarButtonItem *buttonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(barButtonTapped)];
        self.navigationItem.rightBarButtonItem = buttonItem;
        [buttonItem release];
    }
    return self;
}

- (void)dealloc {
    [textView_ release];
    [tableView_ release];

    [package_ release];
    [suspect_ release];
    [linkInstruction_ release];
    [includeInstructions_ release];

    [super dealloc];
}

- (void)loadView {
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    CGFloat tableViewHeight = 23.0 + 44.0 * MIN(4.0, [includeInstructions_ count]);
    CGFloat textViewHeight = (screenBounds.size.height - tableViewHeight);

    UITextView *textView = [[UITextView alloc] initWithFrame:CGRectMake(0.0, 0.0, screenBounds.size.width, textViewHeight)];
    textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    textView.text = [self defaultMessageBody];
    textView_ = textView;

    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectMake(0.0, textViewHeight, screenBounds.size.width, tableViewHeight)];
    tableView.allowsSelectionDuringEditing = YES;
    tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.editing = YES;
    tableView_ = tableView;

    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, screenBounds.size.width, screenBounds.size.height)];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.backgroundColor = [UIColor whiteColor];
    [view addSubview:textView];
    [view addSubview:tableView];
    self.view = view;
    [view release];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown;
}

#pragma mark - Other

- (NSString *)defaultMessageBody {
    NSString *string = nil;

    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *author = [package_.author stringByReplacingOccurrencesOfRegex:@"\\s*<[^>]+>" withString:@""] ?: @"developer";
    if (package_.isAppStore) {
        NSString *msgPath = [mainBundle pathForResource:@"Message_AppStore" ofType:@"txt"];
        NSString *msg = [NSString stringWithContentsOfFile:msgPath usedEncoding:NULL error:NULL];
        string = [NSString stringWithFormat:msg, author, package_.name];
    } else {
        NSString *msgPath = [mainBundle pathForResource:@"Message_Cydia" ofType:@"txt"];
        NSString *msg = [NSString stringWithContentsOfFile:msgPath usedEncoding:NULL error:NULL];
        string = [NSString stringWithFormat:msg, author, suspect_, package_.name];
    }

    return string;
}

- (NSArray *)selectedAttachments {
    // Determine selected attachments.
    NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
    for (NSIndexPath *indexPath in [tableView_ indexPathsForSelectedRows]) {
        [indexSet addIndex:indexPath.row];
    }
    return [includeInstructions_ objectsAtIndexes:indexSet];
}

- (NSString *)uploadAttachments {
    NSMutableString *urlsString = nil;

    ModalActionSheet *hud = [ModalActionSheet new];
    [hud show];

    NSArray *contents = [[self selectedAttachments] valueForKey:@"content"];
    if ([contents count] > 0) {
        NSArray *urls = pastie(contents, hud);
        if (urls != nil) {
            urlsString = [NSMutableString string];
            for (NSURL *url in urls) {
                [urlsString appendString:[url absoluteString]];
                [urlsString appendString:@"\n"];
            }
        } else {
            NSBundle *mainBundle = [NSBundle mainBundle];
            NSString *title = [mainBundle localizedStringForKey:@"Upload failed" value:nil table:nil];
            NSString *message = [mainBundle localizedStringForKey:@"pastie.org is unreachable." value:nil table:nil];
            NSString *cancel = [mainBundle localizedStringForKey:@"OK" value:nil table:nil];
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:message delegate:nil
                cancelButtonTitle:cancel otherButtonTitles:nil];
            [alert show];
            [alert release];
        }
    }

    [hud hide];
    [hud release];

    return urlsString;
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [includeInstructions_ count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return [[NSBundle mainBundle] localizedStringForKey:@"Attachments" value:nil table:nil];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Returning "3" enables multiple cell selection.
    // NOTE: Versions of iOS prior to 5.0 supported multiple cell
    //       selection, but only via the private API.
    // FIXME: As this is private, this might change in a future release.
    return 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UILabel *textLabel = nil;
    UILabel *detailTextLabel = nil;

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"."];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"."] autorelease];
        cell.indentationWidth = 0.0;

        textLabel = cell.textLabel;

        detailTextLabel = cell.detailTextLabel;
        detailTextLabel.font = [UIFont systemFontOfSize:9.0];
        detailTextLabel.lineBreakMode = UILineBreakModeMiddleTruncation;
        detailTextLabel.numberOfLines = 2;
    }

    cell.editingAccessoryType = UITableViewCellAccessoryDetailDisclosureButton;
    textLabel.textColor = [UIColor blackColor];

    IncludeInstruction *instruction = [includeInstructions_ objectAtIndex:indexPath.row];
    textLabel.text = [instruction title];
    detailTextLabel.text = [instruction filepath];
    [tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    CrashLogViewController *controller = [CrashLogViewController new];
    controller.instruction = [includeInstructions_ objectAtIndex:indexPath.row];
    [self.navigationController pushViewController:controller animated:YES];
    [controller release];
}


#pragma mark - UIBarButtonItem Actions

- (void)barButtonTapped {
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *okMessage = [mainBundle localizedStringForKey:@"OK" value:nil table:nil];

    if ([linkInstruction_ isEmail]) {
        if ([MFMailComposeViewController canSendMail]) {
            // Setup mail controller.
            MFMailComposeViewController *controller = [MFMailComposeViewController new];
            [controller setMailComposeDelegate:self];
            [controller setMessageBody:textView_.text isHTML:NO];
            [controller setSubject:[@"Crash Report: " stringByAppendingString:(package_.name ?: @"(unknown product)")]];
            [controller setToRecipients:[[linkInstruction_ recipients] componentsSeparatedByRegex:@",\\s*"]];

            // Add attachments.
            for (IncludeInstruction *instruction in [self selectedAttachments]) {
                // Attach to the email.
                NSData *data = [[instruction content] dataUsingEncoding:NSUTF8StringEncoding];
                if (data != nil) {
                    NSString *filepath = [instruction filepath];
                    NSString *filename = ([instruction type] == IncludeInstructionTypeCommand) ?
                        [[instruction title] stringByAppendingPathExtension:@"txt"] : [filepath lastPathComponent];
                    NSString *mimeType = ([instruction type] == IncludeInstructionTypePlist) ?
                        @"application/x-plist" : @"text/plain";
                    [controller addAttachmentData:data mimeType:mimeType fileName:filename];
                }
            }

            // Present the mail controller for confirmation.
            [self presentModalViewController:controller animated:YES];
            [controller release];
        } else {
            NSString *cannotMailMessage = [mainBundle localizedStringForKey:@"CANNOT_EMAIL" value:@"Cannot send email from this device." table:nil];
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:cannotMailMessage message:nil delegate:nil cancelButtonTitle:okMessage otherButtonTitles:nil];
            [alert show];
            [alert release];
        }
    } else {
        // Upload attachments to paste site and open support link.
        NSString *urlsString = [self uploadAttachments];
        if (urlsString != nil) {
            NSMutableString *string = [textView_.text mutableCopy];
            [string appendString:@"\n"];
            [string appendString:urlsString];
            [UIPasteboard generalPasteboard].string = string;
            [[UIApplication sharedApplication] openURL:[linkInstruction_ url]];
            [string release];
        }
    }
}

#pragma mark - MFMailComposeViewControllerDelegate

- (void)mailComposeController:(MFMailComposeViewController *)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error {
    [self dismissModalViewControllerAnimated:YES];

    if (result == MFMailComposeResultFailed) {
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSString *message = [[mainBundle localizedStringForKey:@"EMAIL_FAILED_1" value:@"Failed to send email.\nError: " table:nil]
            stringByAppendingString:[error localizedDescription]];
        NSString *okMessage = [mainBundle localizedStringForKey:@"OK" value:nil table:nil];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:nil message:message delegate:nil
            cancelButtonTitle:okMessage otherButtonTitles:nil];
        [alert show];
        [alert release];
    }
}

@end

/* vim: set ft=objc ff=unix sw=4 ts=4 tw=80 expandtab: */