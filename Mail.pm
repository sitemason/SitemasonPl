package SitemasonPl::Mail;
$VERSION = '8.0';

=head1 NAME

SitemasonPl::Mail

=head1 DESCRIPTION

A common system for sending mail.

=head1 METHODS

=cut

use strict;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use Net::SMTP;

use SitemasonPl::Common;
use SitemasonPl::Debug;
use SitemasonPl::Database;


#=====================================================

=head2 B<new>

Create a new mail handle.

This uses the Database module to look up server and user settings. Send dbHost and dbPort if not local and default.

userId is not required, but is encouraged for setting Return-Path and using user smtp settings. If writing a script that will send mail from multiple users, this may be specified at the time mail is sent.

 my $mail = SitemasonPl::Mail->new( userId => $userId );

 my $mail = SitemasonPl::Mail->new(
 	userId	=> $userId,
 	
 	dbHost	=> $dbHost,
 	dbPort	=> $dbPort,
 	
 	dbh		=> $dbh,
	
	# pass original script's debug to share timing and logging
	debug		=> $debug
 );

If settings check out for sending mail, $mail->{canSend} will be set to 1.

=cut
#=====================================================
sub new {
	my ($class, %arg) = @_;
	$class || return;
	my $self = {
		dbh		=> $arg{dbh},	# required
		log		=> {
			send	=> 0,
			db		=> 0
		}
	};
	bless $self, $class;
	
	if ($arg{debug}) {
		$self->{debug} = $arg{debug};
	} else {
		$self->{debug} = SitemasonPl::Debug->new(
			logLevel	=> 'debug',
			logLevelAll	=> 'info',
			logTags		=> []
		);
	}
	$self->{debug}->call;
	
# 	unless ($self->{dbh}) { $self->{debug}->critical("No database handler available. Exiting from SitemasonPl::Mail"); return; }
	
	if ($self->{dbh}) {
		my $locale = $self->{dbh}->selectallHashref("
			select name, description from locale where name = 'local_mail' or name like 'smtp_%' or name = 'hostname'
		", 'name', $self->{log}->{db});
		$self->{localMail} = $locale->{localMail}->{description};
		$self->{smtpHostname} = $locale->{smtpHostname}->{description};
		$self->{smtpUsername} = $locale->{smtpUsername}->{description};
		$self->{smtpPassword} = $locale->{smtpPassword}->{description};
		$self->{isSMTPSSL} = $locale->{isSMTPSSL}->{description};
		$self->{hostname} = $locale->{hostname}->{description};
		my ($emailAddress, $smtpHostname, $smtpUsername, $smtpPassword, $isSMTPSSL, $hasCheckedSMTP) = $self->getUserSMTP($arg{userId});
		$self->{userEmailAddress} = $emailAddress;
		$self->{userId} = $arg{userId};
		$self->{hasCheckedSMTP} = $hasCheckedSMTP;
		if ($smtpHostname) {
			$self->{userSMTPHostname} = $smtpHostname;
			$self->{userSMTPUsername} = $smtpUsername;
			$self->{userSMTPPassword} = $smtpPassword;
			$self->{userIsSMTPSSL} = $isSMTPSSL;
		}
	} else {
		$self->{smtpHostname} = 'secure.emailsrvr.com:465';
		$self->{smtpUsername} = 'websites@sitemasonhost.com';
		$self->{smtpPassword} = 'web-smtp';
		$self->{isSMTPSSL} = TRUE;
	}
	
	if ($self->{smtpHostname} || $self->{userSMTPHostname} || $self->{localMail}) { $self->{canSend} = 1; }
	
	return $self;
}


#=====================================================

=head2 B<getUserSMTP>

Returns the email address and smtp settings of the given user. Mainly for internal use.

 $mail->getUserSMTP($userId);

=cut
#=====================================================
sub getUserSMTP {
	my $self = shift || return; $self->{debug}->call;
	my $userId = shift || return;
	$self->{dbh} || return;
	
	my $quserOid = $self->{dbh}->quote($userId);
	my ($emailAddress) = $self->{dbh}->selectrowArray("
		select email_address
		from user_contact
		where user_oid = $quserOid
	", $self->{log}->{db});
	my ($smtpHostname, $smtpUsername, $smtpPassword, $isSMTPSSL, $hasCheckedSMTP) = $self->{dbh}->selectRowArray("
		select smtp_hostname, smtp_username, smtp_password, is_smtp_ssl, has_checked_smtp
		from basic_user_prefs
		where user_oid = $quserOid
	", $self->{log}->{db});
	return ($emailAddress, $smtpHostname, $smtpUsername, $smtpPassword, $isSMTPSSL, $hasCheckedSMTP);
}


#=====================================================

=head2 B<cleanEmailName>

=cut
#=====================================================
sub cleanEmailName {
	my $self = shift || return; $self->{debug}->call;
	my $name = shift || return;
	$name =~ s/[^\w \.\-]+//g;
	return $name;
}


#=====================================================

=head2 B<cleanAddress>

=cut
#=====================================================
sub cleanAddress {
	my $self = shift || return; $self->{debug}->call;
	my $toAddress = shift || return;
	
	my @to = split(/\s*,\s*/, $toAddress);
	my @new;
	foreach my $to (@to) {
		$to =~ s/(?:^.*<|>.*$)//g;
		$to =~ s/\s+//g;
		if (isEmail($to)) {
			push(@new, $to);
		}
	}
	return @new;
}


#=====================================================

=head2 B<sendTest>

Sends a test message to the given SMTP server. FROM and TO are set to the address in testEmail. All other mail settings may be specified. header, subject, and body are filled in if left blank. Basically, give it the following and it will send an appropriate test message.

 my $message = $mail->sendTest( {
	testEmail		=> $testEmail,
	smtpHostname	=> $smtpHostname,
	smtpUsername	=> $smtpUsername,
	smtpPassword	=> $smtpPassword,
	isSMTPSSL		=> $isSMTPSSL
 } );

=cut
#=====================================================
sub sendTest {
	my $self = shift || return; $self->{debug}->call;
	my $mail = shift || return;
	
	$mail->{header} ||= 'Sent from Sitemason mail test';
	$mail->{subject} ||= 'Test of SMTP settings from Sitemason';
	$mail->{from} ||= $mail->{testEmail};
	$mail->{to} ||= $mail->{testEmail};
	$mail->{body} ||= 'This is a test message from Sitemason. Since you received this, your SMTP settings in Sitemason are working properly and Sitemason will be able to send mail for you.';
	
	my $message = $self->sendMail($mail);
	return $message;
}


#=====================================================

=head2 B<sendMail>

Sends an email to the specified SMTP server. from and to are required. Returns the text of the message and the basic headers used.

from, to, cc, and bcc can be a scalar, array, or keys in a hash. fromName, toName, and ccName can also be sent and will be included if it makes sense.

header - if set, will be included under the X-Sitemason header in the email.

app - if set, will be included in the X-Mailer header in the email.

type - if set, will be included in the Content-Type header in the email.

stripHtml - set to 1 to do a crude conversion on the body to convert to text.

debug - set to 1 to log SMTP errors.

smtpHostname, smtpUsername, smtpPassword - Can be used by scripts to specify an smtp host different from the server or user settings.

userId - Can be used by scripts to specify a different user for each call of sendMail.

 my $message = $mail->sendMail( {
	header		=> "Sent from <$url>",
	app			=> "Calendar",
	stripHtml	=> 1,
	from		=> $fromAddress,
	to			=> $toAddress,
	subject		=> $subject,
	body		=> $body
 } );

 my $message = $mail->sendMail( {
	header		=> "Sent from <$url>",
	'x-mailer'	=> "Sitemason Calendar",
	app			=> "Calendar",
	precedence	=> "bulk",
	
	type		=> 'text/html',
	stripHtml	=> 1,
	debug		=> 1,
	
	from		=> $fromAddress,
	fromName	=> $fromName,
	to			=> $toAddress,
	toName		=> $toName,
	cc			=> $ccAddress,
	ccName		=> $ccName,
	bcc			=> $bccAddress,
	subject		=> $subject,
	body		=> $body,
	
	smtpHostname	=> $smtpHostname,
	smtpUsername	=> $smtpUsername,
	smtpPassword	=> $smtpPassword,
	isSMTPSSL		=> $isSMTPSSL,
	
	userId			=> $userId,
 } );


=cut
#=====================================================
sub sendMail {
	my $self = shift || return; $self->{debug}->call;
	my $mail = shift || return;
	
	my $debug = $mail->{debug} || $self->{log}->{send};
	
	my $userEmailAddress = $self->{userEmailAddress};
	my ($smtpHostname, $smtpUsername, $smtpPassword, $isSMTPSSL);
	if ($mail->{smtpHostname}) {
		$smtpHostname = $mail->{smtpHostname};
		$smtpUsername = $mail->{smtpUsername};
		$smtpPassword = $mail->{smtpPassword};
		$isSMTPSSL = $mail->{isSMTPSSL};
	} elsif ($mail->{userId} && ($mail->{userId} != $self->{userId})) {
		# Warning: This should only be used in scripts that need to mail from multiple users.
		($userEmailAddress, $smtpHostname, $smtpUsername, $smtpPassword, $isSMTPSSL) = $self->getUserSMTP($mail->{userId});
		unless ($smtpHostname) {
			$smtpHostname = $self->{smtpHostname};
			$smtpUsername = $self->{smtpUsername};
			$smtpPassword = $self->{smtpPassword};
			$isSMTPSSL = $self->{isSMTPSSL};
		}
	} elsif ($self->{userSMTPHostname}) {
		$smtpHostname = $self->{userSMTPHostname};
		$smtpUsername = $self->{userSMTPUsername};
		$smtpPassword = $self->{userSMTPPassword};
		$isSMTPSSL = $self->{userIsSMTPSSL};
	} elsif ($self->{smtpHostname}) {
		$smtpHostname = $self->{smtpHostname};
		$smtpUsername = $self->{smtpUsername};
		$smtpPassword = $self->{smtpPassword};
		$isSMTPSSL = $self->{isSMTPSSL};
	}
	
	unless ($smtpHostname || $self->{localMail}) { return; }
	if ($smtpHostname && ($smtpHostname !~ /^([a-z0-9-]+\.)+[a-z]{2,6}(?::\d+)?$/)) { return; }
	
	my $from = refToScalar($mail->{from}, ', ');
	unless ($from) {
		$self->{debug}->warning("Missing FROM address when sending mail");
		return;
	}
	my $fromName = $self->cleanEmailName($mail->{fromName});
	if ($fromName && ($from !~ /[<,]/)) { $from = "\"$fromName\" <$from>"; }
	else { ($from) = $self->cleanAddress($from); }
	my $to = refToScalar($mail->{to}, ', ');
	unless ($to) {
		$self->{debug}->notice("Missing TO address when sending mail");
		return;
	}
	my $toName = $self->cleanEmailName($mail->{toName});
	my @to;
	if ($toName && ($to !~ /[<,]/)) { push(@to, "\"$toName\" <$to>"); }
	else { @to = $self->cleanAddress($to); }
	$to = join(', ', @to);
	my $cc = refToScalar($mail->{cc}, ', ');
	my $ccName = $self->cleanEmailName($mail->{ccName});
	my @cc;
	if ($ccName && ($cc !~ /[<,]/)) { push(@cc, "\"$ccName\" <$cc>"); }
	else { @cc = $self->cleanAddress($cc); }
	$cc = join(', ', @cc);
	my $bcc = refToScalar($mail->{bcc}, ', ');
	my @bcc = $self->cleanAddress($bcc);
	$bcc = join(', ', @bcc);
	
	my $subject = $mail->{subject};
	$subject =~ s/\s/ /g;
	
	my $header = <<"EOL";
From: $from
To: $to
EOL
	if ($mail->{cc}) { $header .= "Cc: $cc\n"; }
	if ($mail->{bcc}) { $header .= "Bcc: $bcc\n"; }
	$header .= <<"EOL";
Subject: $subject
EOL
	
	my $sitemason = "X-Mailer: Sitemason Content Management System <http://www.sitemason.com/>\n";
	if ($mail->{'x-mailer'}) {
		$sitemason = "X-Mailer: " . $mail->{'x-mailer'} . "\n";
	} elsif ($mail->{app}) {
		$sitemason = "X-Mailer: Sitemason $mail->{app} <http://www.sitemason.com/>\n";
	}
	if ($mail->{header}) { $sitemason .= "X-Sitemason: $mail->{header}\n"; }
	if ($userEmailAddress) { $sitemason .= "Return-Path: $userEmailAddress\n"; }
	if ($mail->{precedence} eq 'bulk') { $sitemason .= "Precedence: bulk\n"; }
	
	# Catch formatted bodies
	if (isHash($mail->{body})) {
		$mail->{body} = [$mail->{body}];
	}
	if (isArray($mail->{body})) {
		($mail->{mimeBoundary}, $mail->{body}) = $self->formatSitemasonMail($mail->{body});
	}
	
	if ($mail->{mimeBoundary}) {
		$sitemason .= "MIME-Version: 1.0\n";
		$sitemason .= 'Content-Type: multipart/alternative; boundary="' . $mail->{mimeBoundary} . "\"\n";
	}
	elsif ($mail->{type}) { $sitemason .= "Content-Type: $mail->{type}\n"; }
	
	my $body = "\n" . $mail->{body};
	if ($mail->{stripHTML}) {
		$body =~ s/(<(?:br|p)\s*\/?\s*>|<\/?(?:div|p|h\d).*?>|<\/?p>)/\n/ig;
		$body =~ s/<a.+?href="(.+?)".*?>/<$1>/ig;
		$body =~ s/<(?!(?:https?:|ftp:|mailto:|[^>]+?\@)).*?>//g;
		$body =~ s/\r\n/\n/g;
	}
	
	eval {
		require Net::SMTP::SSL;
		Net::SMTP::SSL->import();
	};
	if ($@) {
		undef $isSMTPSSL;
		$self->{debug}->error("Failed to use Net::SMTP::SSL");
	}
	
	my $smtpModule = 'SMTP';
	if ($smtpHostname) {
		my $smtp;
		if ($debug) {
			my $message = <<"EOL";
Sending via Net::SMTP to $smtpHostname
$header$sitemason$body
EOL
			$self->{debug}->debug($message);
			if ($isSMTPSSL) {
				if (!($smtp = Net::SMTP::SSL->new(
					Host	=> $smtpHostname,
					Hello	=> $self->{hostname},
					Timeout	=> 60,
					Debug	=> 1
				))) {
					$self->{debug}->error("Failed to connect to SSL SMTP server ($smtpHostname)");
					return;
				}
			} else {
				if (!($smtp = Net::SMTP->new(
					Host	=> $smtpHostname,
					Hello	=> $self->{hostname},
					Timeout	=> 60,
					Debug	=> 1
				))) {
					$self->{debug}->error("Failed to connect to SMTP server ($smtpHostname)");
					return;
				}
			}
		} else {
			if ($isSMTPSSL) {
				if (!($smtp = Net::SMTP::SSL->new(
					Host	=> $smtpHostname,
					Hello	=> $self->{hostname},
					Timeout => 60
				))) {
					$self->{debug}->error("Failed to connect to SSL SMTP server ($smtpHostname)");
					return;
				}
			} else {
				if (!($smtp = Net::SMTP->new(
					Host	=> $smtpHostname,
					Hello	=> $self->{hostname},
					Timeout => 60
				))) {
					$self->{debug}->error("Failed to connect to SMTP server ($smtpHostname)");
					return;
				}
			}
		}
		if ($smtpUsername && $smtpPassword) {
			if (!$smtp->auth($smtpUsername, $smtpPassword)) {
				$self->{debug}->error("Failed to auth to SMTP server ($smtpHostname, $smtpUsername)");
			}
		}
		
		if (!$smtp->mail($from)) {
			$self->{debug}->warning("Invalid FROM address ($from)");
			return;
		}
		if (!$smtp->to(@to)) {
			$self->{debug}->notice("Invalid TO address ($to)");
			return;
		}
		if (@cc) { $smtp->cc(@cc); }
		if (@bcc) { $smtp->bcc(@bcc); }
		
		$smtp->data();
		$smtp->datasend($header);
		$smtp->datasend($sitemason);
		$smtp->datasend($body);
		$smtp->dataend();
		$smtp->quit;
		if ($debug) {
			$self->{debug}->notice("Connected to SMTP server. Test message successful.");
		} else {
			$self->{debug}->notice("Email sent to $to", { header => 0 });
		}
	} elsif ($self->{localMail}) {
		if ($debug) {
			my $message = <<"EOL";
Piping to /var/qmail/bin/qmail-inject
$header$sitemason$body
EOL
			$self->{debug}->notice($message);
		}
		unless (open(MAIL,"|/var/qmail/bin/qmail-inject")) {
			$self->{debug}->alert("Could not open pipe to qmail-inject");
		}
		print MAIL <<"EOL";
$header$sitemason$body
EOL
		close(MAIL);
		unless ($debug) { $self->{debug}->notice("Email sent to $to"); }
	}
	
	my $message = $header . $body;
	
	return $message;
}


#=====================================================

=head2 B<sendStoredEmail>

Main method for sending Sitemason-formatted emails. Emails should be defined in getEmailTemplate().

 $mail->sendStoredEmail($name, $data);

=cut
#=====================================================
sub sendStoredEmail {
	my $self = shift || return;
	my $name = shift || return;
	my $data = shift;
	
	my $template = $self->getEmailTemplate($name);
	if (!isHash($template)) { $self->{debug}->debug('Mail template "' . $name . '" does not exist'); return; }
	isArray($template->{body}) || return;
	
	if (isHash($data)) {
		if ($data->{app}) { $template->{app} = $data->{app}; }
		if ($data->{fromName}) { $template->{fromName} = $data->{fromName}; }
		if ($data->{from}) { $template->{from} = $data->{from}; }
		if ($data->{to}) { $template->{to} = $data->{to}; }
		if ($data->{cc}) { $template->{cc} = $data->{cc}; }
		if ($data->{bcc}) { $template->{bcc} = $data->{bcc}; }
		if ($data->{subject}) { $template->{subject} = $data->{subject}; }
		$template->{body} = insertData($template->{body}, $data);
	}
	
	return $self->sendMail($template);
}


#=====================================================

=head2 B<formatSitemasonMail>

=cut
#=====================================================
sub formatSitemasonMail {
	my $self = shift || return;
	my $message = shift || return;
	
	my $indent = "							";
	my $html;
	my $plain = "SITEMASON BUILD ON US\n-----------------------\n\n";
	my $cnt;
	foreach my $section (@{$message}) {
		if (!$cnt) {
			$html .= <<"EOL";
					<tr>
						<td valign="top" bgcolor="#ffffff" style="padding: 20px 30px 40px 30px; line-height: 1.5;" width="100%">
EOL
		} elsif ($cnt % 2) {
			$html .= <<"EOL";
					<tr>
						<td valign="top" bgcolor="#f9f9f9" style="padding: 20px 30px 40px 30px; line-height: 1.5;border-top: 1px solid #eee;border-bottom: 1px solid #eee;">
EOL
		} else {
			$html .= <<"EOL";
					<tr>
						<td valign="top" bgcolor="#ffffff" style="padding: 20px 30px 40px 30px; line-height: 1.5;">
EOL
		}
		if ($section->{title}) {
			if ($cnt) { $html .= "$indent<h2>" . $section->{title} . "</h2>\n"; }
			else { $html .= "$indent<h1>" . $section->{title} . "</h1>\n"; }
			$plain .= $section->{title} . "\n\n";
		}
		if ($section->{body} && !ref($section->{body})) { $section->{body} = [$section->{body}]; }
		if (isArrayWithContent($section->{body})) {
			foreach my $paragraph (@{$section->{body}}) {
				if (isHash($paragraph)) {
					$plain .= $paragraph->{text} . "\n\n";
					my $align;
					if ($paragraph->{align}) { $align = ' style="text-align:' . $paragraph->{align} . ';"'; }
					$html .= "$indent<p$align>" . $paragraph->{html} . "</p>\n";
				} else {
					$plain .= stripHTML($paragraph, {
						use_newlines		=> 1,
						convert_links		=> 1,
						convert_entities	=> 1
					} );
					$plain .= "\n\n";
					
					$paragraph =~ s/(?<!")\b(https?:\/\/(.*?))(?=[,.]?\s|[,.]?$)/<a href="$1">$2<\/a>/ig;
					$html .= "$indent<p>" . $paragraph . "</p>\n";
				}
			}
		}
		$html .= <<"EOL";
						</td>
					</tr>
EOL
		$plain .= "\n";
		$cnt++;
	}
	
	$plain .= "-- \nSITEMASON | 110 30TH AVE NORTH, SUITE 5 | NASHVILLE, TN 37203 | 615-301-2600\n\n\n";
	my $htmlBody = getSitemasonHTMLTemplate();
	$htmlBody =~ s/\$\{body\}/$html/;
	
	my $boundary = generateKey;
	my $emailBody = <<"EOL";
--$boundary
Content-Type: text/plain

$plain
--$boundary
Content-Type: text/html

$htmlBody
--$boundary--
EOL
	
	return ($boundary, $emailBody);
}

sub getSitemasonHTMLTemplate {
	return <<"EOL";
<html style="margin: 0;padding: 0;">
<head></head>
<body style="margin: 0;padding: 0;">
<div>
	<table align="center" border="0" cellpadding="0" cellspacing="0" style="background:#202a2f url(http://www.sitemason.com/email/bg.gif); font-family: 'Open Sans',helvetica,arial,sans-serif; color: #333; text-align: left;" width="100%">
		<tr>
			<td align="center" valign="top" style="padding: 0 0 50px 0;" width="100%">
				<table border="0" cellpadding="0" cellspacing="0" width="610" align="center">
					<tr>
						<td style="padding: 10px 0 0 0;">
							<a href="http://www.sitemason.com"><img alt="Sitemason" border="0" height="100" src="http://www.sitemason.com/email/logo-large.png" width="650"/></a>
						</td>
					</tr>
\${body}
					<tr>
						<td>
							<p style="color: #fff;text-align: center;font-size: 12px;margin: 10px 0 0 0;letter-spacing: 1px;">SITEMASON <span style="color: #4d6571;padding: 0 5px;">|</span> 110 30TH AVE NORTH, SUITE 5 <span style="color: #4d6571;padding: 0 5px;">|</span> NASHVILLE, TN 37203 <span style="color: #4d6571;padding: 0 5px;">|</span> 615-301-2600</p>
						</td>
					</tr>
				</table>
			</td>
		</tr>
	</table>
</div>
<style>
\@import url("http://fonts.googleapis.com/css?family=Open+Sans:400,700,900");
a {
	color: #2984cf;
	text-decoration: none
}
a img {
	border: none
}
h1 {
	font-size: 24px;
	margin: 0 0 20px 0;
}
p {
	line-height: 1.5;
	font-size: 14px;
	margin: 0 0 14px 0;
}
h2 {
	font-size: 20px;
}
h3 {
	font-size: 16px;
}
</style>
</body>
</html>
EOL
}


#=====================================================

=head2 B<getEmailTemplate>

=cut
#=====================================================
sub getEmailTemplate {
	my $self = shift || return;
	my $name = shift || return;
	
	my $template = {
		signup => {
			app			=> "Signup",
			from_name	=> 'Sitemason Support',
			from		=> 'support@sitemason.com',
			subject		=> 'Welcome to Sitemason',
			body		=> [ {
				title		=> 'Welcome to Sitemason',
				body		=> 'Thanks for signing up! You can login anytime from http://${hostname}/login with your username ${username}.${emailMessage}'
			}, {
				title		=> 'Sitemason Resources',
				body		=> [
					'Get the most out of Sitemason by checking out the documentation on our <a href="http://www.sitemason.com/support">support</a> site. Join the conversation in our <a href="http://support.sitemason.com/categories/5947-Community-Forums">Community Forums</a>, or spend some time reviewing the <a href="http://www.sitemason.com/community/resources/">Resources</a> section to find helpful guides and recommendations. Developers will feel right at home with our <a href="http://www.sitemason.com/developers">Developer Documentation</a>.',
					'Need help with development, design, or marketing services? Reach out to one of our incredible <a href="http://www.sitemason.com/community/partners">Partners</a> to find the best of the best.  Also, don\'t forget to subscribe to our <a href="http://www.sitemason.com/about/news">Blog</a> to keep up on industry best practices and the goings-on in the Sitemason community.'
				]
			}, {
				body		=> [
					'Ready to dig in? Click below to launch the Sitemason Getting Started Guide for new users.',
					{
						align	=> 'center',
						html	=> '<a href="http://support.sitemason.com/entries/21517824-Getting-Started-with-Sitemason-6"><img src="http://www.sitemason.com/email/getting-started.png" alt="Getting Started Guide" title="Getting Started Guide" /></a>',
						text	=> 'Getting Started Guide - http://support.sitemason.com/entries/21517824-Getting-Started-with-Sitemason-6'
					},
					'<br>Thanks for choosing to Build On Us,<br>The Sitemason Team'
				]
			} ]
		},
		
		folderSharing => {
			app			=> "Folder Sharing",
			from_name	=> 'Sitemason Support',
			from		=> 'support@sitemason.com',
			subject		=> 'Sitemason Site Sharing',
			body		=> [ {
				title		=> 'Site Sharing',
				body		=> '${shareText}'
			}, {
				title		=> 'Instructions',
				body		=> [
					'To accept this invitation, click the following link:',
					'http://${hostname}/sharing?shareKey=${key}',
					'This invitation expires in 3 days.'
				]
			} ]
		},
		
		forgotPassword => {
			app			=> "Forgot Password",
			from_name	=> 'Sitemason Support',
			from		=> 'support@sitemason.com',
			subject		=> 'Sitemason Password Reset',
			body		=> [ {
				title		=> 'Password Reset',
				body		=> [
					'A request was made to reset your password. If you did not make that request, there is nothing you need to do and your password will remain the same.',
					'If you did make this request, follow the instructions below.'
				]
			}, {
				title		=> 'Instructions',
				body		=> [
					'To reset your password, click the following link:',
					'http://${hostname}/reset?resetKey=${key}',
					'This link expires in 3 days.'
				]
			} ]
		},
		
		accountChange => {
			app			=> "Account Change",
			from_name	=> 'Sitemason Support',
			from		=> 'support@sitemason.com',
			subject		=> 'Sitemason Account Change',
			body		=> [ {
				title		=> 'Account Change',
				body		=> '${changeText}'
			}, {
				title		=> 'Instructions',
				body		=> [
					'If you made this change, you don\'t need to do anything else.',
					'If you did not make this change, please contact support@sitemason.com immediately.'
				]
			} ]
		},
		
		sslReminder => {
			app			=> "SSL Certificate Renewal",
			from_name	=> 'Sitemason Hostmaster',
			from		=> 'hostmaster@sitemason.com',
			subject		=> 'Sitemason SSL Certificate Renewal',
			body		=> [ {
				title		=> 'SSL Certificate Renewal',
				body		=> 'It is time to renew the SSL certificate for the ${hostname} website.${expiration} Renewal is complex and requires many steps. However, Sitemason takes care of all but one of those steps for you. You must approve the renewal process for your SSL certificate to be generated. Follow the instructions below to approve your new SSL certificate.'
			}, {
				title		=> 'Instructions',
				body		=> [
					'Within the next day, an email will be sent to ${admin_email} from sslorders@geotrust.com asking for approval.',
					'1) Click the link in the email to go to the appoval web page.',
					'2) Click the &quot;I Approve&quot; button.',
					'That\'s it!'
				]
			}, {
				title		=> 'More Information',
				body		=> [
					'Reply to this email if you have any questions or changes.',
					'For more information, read about <a href="http://www.sitemason.com/about/news/secure-site-hosting.693176">Sitemason Secure Site Hosting</a> on our support website.'
				]
			} ]
		}
		
	};
	
	return $template->{$name};
}

=head1 CHANGES

  20071105 TJM - v0.01 started development
  20120105 TJM - v6.0 moved from Sitemason::System to Sitemason6::Library
  20150415 TJM - v7.0 updated for Sitemason 7.
  20171109 TJM - v8.0 Moved to SitemasonPL open source project

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
