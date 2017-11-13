package SitemasonPl::Mail 8.0;

=head1 NAME

SitemasonPl::Mail

=head1 DESCRIPTION

A common system for sending mail.

=head1 METHODS

=cut

use v5.012;
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

 my $mail = SitemasonPl::Mail->new(
 	smtpHostname	=> $smtpHostname,
	smtpUsername	=> $smtpUsername,
	smtpPassword	=> $smtpPassword,
	
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
		smtpHostname	=> $arg{smtpHostname},
		smtpUsername	=> $arg{smtpUsername},
		smtpPassword	=> $arg{smtpPassword},
		isSMTPSSL		=> TRUE,
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
	
	return $self;
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
		if (is_email($to)) {
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
	
	$mail->{header} ||= 'Sent from mail test';
	$mail->{subject} ||= 'Test of SMTP settings';
	$mail->{from} ||= $mail->{testEmail};
	$mail->{to} ||= $mail->{testEmail};
	$mail->{body} ||= 'This is a test message. Since you received this, your SMTP settings are working properly and we will be able to send mail for you.';
	
	my $message = $self->sendMail($mail);
	return $message;
}


#=====================================================

=head2 B<sendMail>

Sends an email to the specified SMTP server. from and to are required. Returns the text of the message and the basic headers used.

from, to, cc, and bcc can be a scalar, array, or keys in a hash. fromName, toName, and ccName can also be sent and will be included if it makes sense.

x-mailer - if set, will be included under the x-mailer header.

type - if set, will be included in the Content-Type header in the email.

stripHtml - set to 1 to do a crude conversion on the body to convert to text.

debug - set to 1 to log SMTP errors.

smtpHostname, smtpUsername, smtpPassword - Can be used by scripts to specify an smtp host different from the server or user settings.

userId - Can be used by scripts to specify a different user for each call of sendMail.

 my $message = $mail->sendMail( {
	header		=> "Sent from <$url>",
	stripHtml	=> 1,
	from		=> $fromAddress,
	to			=> $toAddress,
	subject		=> $subject,
	body		=> $body
 } );

 my $message = $mail->sendMail( {
	header		=> "Sent from <$url>",
	'x-mailer'	=> "My App",
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
	} elsif ($self->{smtpHostname}) {
		$smtpHostname = $self->{smtpHostname};
		$smtpUsername = $self->{smtpUsername};
		$smtpPassword = $self->{smtpPassword};
		$isSMTPSSL = $self->{isSMTPSSL};
	}
	
	$smtpHostname || return;
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
	
	my $addlheaders = "X-Mailer: SitemasonPL mail library <https://github.com/sitemason>\n";
	if ($mail->{'x-mailer'}) {
		$addlheaders = "X-Mailer: " . $mail->{'x-mailer'} . "\n";
	}
	if ($userEmailAddress) { $addlheaders .= "Return-Path: $userEmailAddress\n"; }
	if ($mail->{precedence} eq 'bulk') { $addlheaders .= "Precedence: bulk\n"; }
	
	# Catch formatted bodies
	if (is_hash($mail->{body})) {
		$mail->{body} = [$mail->{body}];
	}
	if (is_array($mail->{body})) {
		($mail->{mimeBoundary}, $mail->{body}) = $self->formatMail($mail->{body});
	}
	
	if ($mail->{mimeBoundary}) {
		$addlheaders .= "MIME-Version: 1.0\n";
		$addlheaders .= 'Content-Type: multipart/alternative; boundary="' . $mail->{mimeBoundary} . "\"\n";
	}
	elsif ($mail->{type}) { $addlheaders .= "Content-Type: $mail->{type}\n"; }
	
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
$header$addlheaders$body
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
		$smtp->datasend($addlheaders);
		$smtp->datasend($body);
		$smtp->dataend();
		$smtp->quit;
		if ($debug) {
			$self->{debug}->notice("Connected to SMTP server. Test message successful.");
		} else {
			$self->{debug}->notice("Email sent to $to", { header => 0 });
		}
	}
	
	my $message = $header . $body;
	
	return $message;
}


#=====================================================

=head2 B<sendStoredEmail>

Main method for sending formatted emails. Emails should be defined in getEmailTemplate().

 $mail->sendStoredEmail($name, $data);

=cut
#=====================================================
sub sendStoredEmail {
	my $self = shift || return;
	my $name = shift || return;
	my $data = shift;
	
	my $template = $self->getEmailTemplate($name);
	if (!is_hash($template)) { $self->{debug}->debug('Mail template "' . $name . '" does not exist'); return; }
	is_array($template->{body}) || return;
	
	if (is_hash($data)) {
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

=head2 B<formatMail>

=cut
#=====================================================
sub formatMail {
	my $self = shift || return;
	my $message = shift || return;
	
	my $indent = "							";
	my $html;
	my $plain = "EXAMPLE COMPANY\n-----------------------\n\n";
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
		if (is_array_with_content($section->{body})) {
			foreach my $paragraph (@{$section->{body}}) {
				if (is_hash($paragraph)) {
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
	
	$plain .= "-- \nEXAMPLE, ADDRESS | PHONE\n\n\n";
	my $htmlBody = getHTMLTemplate();
	$htmlBody =~ s/\$\{body\}/$html/;
	
	my $boundary = generate_key;
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

sub getHTMLTemplate {
	return <<"EOL";
<html style="margin: 0;padding: 0;">
<head></head>
<body style="margin: 0;padding: 0;">
<div>
\${body}
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
			from_name	=> 'Support',
			from		=> 'support@example.com',
			subject		=> 'Welcome to Example',
			body		=> [ {
				title		=> 'Welcome to Example',
				body		=> 'Thanks for signing up! You can login anytime from http://${hostname}/login with your username ${username}.${emailMessage}'
			}, {
				body		=> [
					'Ready to start? Click below to launch the Getting Started Guide.',
					{
						align	=> 'center',
						html	=> '<a href="http://example.com/Getting-Started">Getting Started Guide</a>',
						text	=> 'Getting Started Guide - http://example.com/Getting-Started'
					},
					'<br>Thanks for choosing us'
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
