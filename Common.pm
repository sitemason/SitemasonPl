package SitemasonPl::Common 8.0;

=head1 NAME

Common

=head1 DESCRIPTION

Contains standard routines that defy a more specific locale.

=cut

use v5.012;
use strict;
use utf8;
use constant TRUE => 1;
use constant FALSE => 0;

use B qw(svref_2object);
use DateTime;
use DateTime::TimeZone;
use Digest::MD5;
use Digest::SHA;
use Encode qw(from_to is_utf8 decode);
#use JSON::Parse 'json_to_perl';
use JSON;
use LWP::UserAgent;
use Math::Trig qw(deg2rad pi great_circle_distance asin acos);
use Text::Unidecode;
# use XML::Parser::Expat;
use Time::gmtime;
use Unicode::Collate;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(read_cookie generate_password
	get_filename_utc_minute get_filename_utc_hour get_filename_utc_date convert_arrays_to_csv read_file_list read_file write_file
	get_url post_url parse_query_string url_decode url_encode
	parse_json make_json make_json parse_xml make_xml jsonify xmlify
	html_entities_to_text to_html_entities from_html_entities convert_to_utf8 read_vfile
	is_boolean is_text is_json is_pos_int is_number is_ordinal is_array is_array_with_content is_hash is_hash_with_content is_hash_key is_array_hash is_array_hash_with_content is_object
	isDomain isHostname isEmail isIPv4 isIPv6 getDomainName isStateCode getStateCode getRegionCode getRegionAliases getPostalCode getCountryCode getMonth
	round significant percent max min isClose summarizeNumber summarizeBytes makeOrdinal pluralize join_text
	arrayLength first value ref_to_scalar refToScalar array_to_list arrayToList list_to_array listToArray list_to_array_auto add_to_list remove_from_array to_array to_list to_hash
	arrayhash_to_hashhash to_hash_hash array_to_hash arrayToHash unique_array uniqueArray contains by_any max_length
	unique compare compress_var compressRef merge_hashes mergeHashes newHash copyRef joinRef diff
	check_id checkId encode_id encodeId encode6_id encode6Id decode_id decodeId unique_key uniqueKey generateKey smmd5_2008 smsha2012 makeDigest
	normalize strip strip_extra_white_space stripExtraWhiteSpace stripControlCharacters clean_filename cleanFilename strip_html stripHTML stripHTMLLink stripOutside
	insertData summarize context to_camel_case from_camel_case is_camel_case camel_case kebab_case snake_case
	toLatLong toLatLongHash toCoordinates distanceInMiles lookUpIP identifyNIC
	convertStringToDateTime convertStringToEpoch convertDateTimeToString getDurationSummary getEstimatedTimeRemaining
	get_unique_name
);


sub read_cookie {
#=====================================================

=head2 B<read_cookie>

Why? Because Apache2::Cookie chokes on cookies with commas.

 read_cookie($req);
 read_cookie($req, $cookieName);

=cut
#=====================================================
	my $req = shift || return;
	my $name = shift;
	my $cookieString = $req->headers_in->{Cookie} || return;
	
	my @cookies = split(/;\s*/, $cookieString);
	my $cookieHash;
	foreach my $cookie (@cookies) {
		my ($key, $value) = $cookie =~ /^(.*?)=(.*)$/;
		if ($key) {
			$key = url_decode($key);
			$value = url_decode($value);
			if ($name && ($key eq $name)) { return $value; }
			$cookieHash->{$key} = $value;
		}
	}
	$name && return;
	
	return $cookieHash;
}


sub generate_password {
#=====================================================

=head2 B<generate_password>

 my $password = generate_password($options);
 $options = {
 	charset	=> 'default' || 'alpha' || 'letters' || 'numeric' || 'lower' || 'upper' || 'blank',	# defaults to 'default'
 	length	=> $lengthOfPassword	# defaults to 32
 }
 
=cut
#=====================================================
	my $defaultOption = shift;
	my $options = shift;
	if (is_hash($defaultOption)) { $options = $defaultOption; }
	if (!is_hash($options)) { $options = {}; }
	
	if (is_pos_int($defaultOption)) { $options->{length} = $defaultOption; }
	elsif (is_text($defaultOption)) { $options->{charset} = $defaultOption; }
	$options->{length} ||= 32;
	$options->{charset} ||= 'default';
	if ($options->{charset} eq 'blank') { return; }
	
	my @chars = ('a'..'z', 'A'..'Z', 0..9, '`', '~', '!', '@', '#', '$', '^', '&', '*', '(', ')', '-', '_', '=', '+', '[', '{', ']', '}', '|', ';', ',', '<', '.', '>', '/', '?');
	if ($options->{charset} eq 'alpha') { @chars = ('a'..'z', 'A'..'Z', 0..9); }
	elsif ($options->{charset} eq 'letters') { @chars = ('a'..'z', 'A'..'Z'); }
	elsif ($options->{charset} eq 'numeric') { @chars = (0..9); }
	elsif ($options->{charset} eq 'lower') { @chars = ('a'..'z'); }
	elsif ($options->{charset} eq 'upper') { @chars = ('A'..'Z'); }
	
	my $pass;
	for (my $i = 0; $i < $options->{length}; $i++) {
		$pass .= $chars[int(rand(@chars))];
	}
	return $pass;
}


sub get_filename_utc_minute {
	my $gm = gmtime();
	my $year = $gm->year + 1900; my $mon = $gm->mon + 1;
	return sprintf("%04d-%02d-%02d_%02d-%02d", $year, $mon, $gm->mday, $gm->hour, $gm->min);
}

sub get_filename_utc_hour {
	my $gm = gmtime();
	my $year = $gm->year + 1900; my $mon = $gm->mon + 1;
	return sprintf("%04d-%02d-%02d_%02d", $year, $mon, $gm->mday, $gm->hour);
}

sub get_filename_utc_date {
	my $gm = gmtime();
	my $year = $gm->year + 1900; my $mon = $gm->mon + 1;
	return sprintf("%04d-%02d-%02d", $year, $mon, $gm->mday);
}

sub convert_arrays_to_csv {
#=====================================================

=head2 B<convert_arrays_to_csv>

 my $csv = convert_arrays_to_csv($table, $debug);

=cut
#=====================================================
	my $data = shift || return;
	my $debug = shift;
	my $csv;
	my $cnt;
	foreach my $row (@{$data}) {
		my @csvRow;
		foreach my $value (@{$row}) {
			$value =~ s/"/""/g;
			if ($value =~ /[",\n\r]/) { $value = "\"$value\""; }
			push(@csvRow, $value);
		}
		my $line = join(',',@csvRow);
		$csv .=  "$line\r\n";
		if (($cnt <= 2) && $debug) { print "convert_arrays_to_csv: $line\n"; }
		elsif (($cnt == 3) && $debug) { print "convert_arrays_to_csv: ...\n"; }
		$cnt++
	}
	return $csv;
}

sub read_file_list {
# my $array = read_file_list($basePath);
	my $base = shift || return;
	my $path = shift;
	my $array = shift || [];
	my $filepath = $base;
	if ($path) { $filepath .= "/$path"; }
	
	if (!opendir(FILES, $filepath)) { print STDERR "Can't open dir $filepath: $!"; return; }
	my @files = grep { !/^\./ } readdir(FILES);
	closedir FILES;
	
	foreach my $file (@files) {
		my $output = $file;
		if ($path) { $output = "$path/$file"; }
		if (-d "$filepath/$file") {
			my $innerArray = read_file_list($base, $output);
			push(@{$array}, @{$innerArray});
		}
		elsif (-f "$filepath/$file") {
			push(@{$array}, $output);
		}
	}
	return $array;
}

sub read_file {
#=====================================================

=head2 B<read_file>

 my $data = read_file($filename);

=cut
#=====================================================
	my $filename = shift || return;
	if (-s $filename) {
		my $data;
		my @data;
		open(IMPORT, '<:encoding(UTF-8)', $filename) || return;
		while(<IMPORT>) {
			$data .= $_;
			chomp;
			push(@data, $_);
		}
		close(IMPORT);
		if (wantarray) { return @data; }
		else { return $data; }
	}
}

sub write_file {
#=====================================================

=head2 B<write_file>

 my $newpath = write_file($path, $content, {
 	addDate		=> TRUE || FALSE,
 	makeDirs	=> TRUE || FALSE,
 	overwrite	=> TRUE || FALSE,
 	printErrors	=> TRUE || FALSE,
 }, $debug);

=cut
#=====================================================
	my $fullpath = shift || return;
	my $content = shift || return;
	my $options = shift;
	my $debug = shift;
	if (!is_hash($options)) { $options = {}; }
	if ($debug) { $options->{printErrors} = TRUE; }
	
	my ($path, $filename) = $fullpath =~ /(?:(.*)\/)?(.*?)$/;
	
	# Make dir, if needed
	if ($path && !-d $path) {
		if ($options->{makeDirs}) { system("mkdir -p $path"); }
		else {
			$options->{printErrors} && print STDERR "ERROR: Directory doesn't exist: $path\n";
			return;
		}
	}
	
	if ($options->{addDate}) {
		my $time = get_filename_utc_date;
		my ($name, $ext) = $filename =~ /(.*)\.(.*?)$/;
		if ($name && $ext) {
			$filename = "${name}_$time.$ext";
		} else {
			$filename .= "_$time";
		}
		$fullpath = "$path/$filename";
	}
	
	if (!$options->{overwrite} && -s $fullpath) {
		$options->{printErrors} && print STDERR "ERROR: File already exists: $fullpath\n";
		return;
	}
	
	unless (open(FILE, ">$fullpath")) {
		$options->{printErrors} && print STDERR "ERROR: Can't open file for writing: $fullpath\n";
		return;
	}
	print FILE $content;
	close(FILE);
	if ($filename =~ /\.(sh|pl|py|js)$/) { chmod 0755, $fullpath; }
	
	$debug && print "write_file: path: $fullpath\n";
	return $fullpath;
}


sub get_url {
#=====================================================

=head2 B<get_url>

 my $content, $status = get_url($url);
 my $content = get_url($url, $userAgentString);
 my $content = get_url($url, $userAgentString, $serverIp);

=cut
#=====================================================
	my $url = shift || return;
	my $args = shift;
	my ($agent, $ip);
	if (!is_hash($args)) {
		$agent = $args;
		$ip = shift;
		$args = {};
	}
	$agent ||= $args->{agent} || 'Mozilla/5.0 (Linux; en-us) Sitemason/' . $SitemasonPl::Common::VERSION;
	$ip ||= $args->{ip};
	my $timeout = $args->{timeout} || 15;
	
	my $ua = LWP::UserAgent->new;
	$ua->agent($agent);
	$ua->timeout($timeout);
	
	my $host;
	if ($ip) {
		($host) = $url =~ m#://(.*?)(?:/|:|$)#;
		if ($host) { $url =~ s#://.*?(/|:|$)#://$ip$1#; }
	}
	
	my $req = HTTP::Request->new(GET => $url);
	if ($host) { $req->header(HOST => $host); }
	$req->header(HTTP_ACCEPT => '*/*');
	$req->header(HTTP_ACCEPT_LANGUAGE => 'en-us');
	if ($args->{headers}) {
		while (my($header, $value) = each(%{$args->{headers}})) {
			$req->header(uc($header) => $value);
		}
	}
	my $res = $ua->request($req);
	if ($res->is_success) {
		my $content = decode('utf-8', $res->content);
		return $content;
	} else {
		return 0, $res->status_line;
	}
}


sub post_url {
#=====================================================

=head2 B<post_url>

 my $content, $status = post_url($url, $data, $headers);
 my $content = postURL($url, $data, $headers);
 my $content = postURL($url, $data, $headers, $serverIp);

=cut
#=====================================================
	my $url = shift || return;
	my $data = shift;
	my $headers = shift;
	my $ip = shift;
	if (!is_hash($data)) { $data = {}; }
	if (!is_hash($headers)) { $headers = {}; }
	
	my $agent = $headers->{agent} || 'Mozilla/5.0 (Linux; en-us) Sitemason/' . $SitemasonPl::Common::VERSION;
	my $ua = LWP::UserAgent->new;
	$ua->agent($agent);
	$ua->timeout(15);
	
	my $host;
	if ($ip) {
		($host) = $url =~ m#://(.*?)(?:/|:|$)#;
		if ($host) { $url =~ s#://.*?(/|:|$)#://$ip$1#; }
	}
	
	my $req = HTTP::Request->new(POST => $url);
	if ($host) { $req->header(HOST => $host); }
	if ($headers->{username}) {
		$req->authorization_basic($headers->{username}, $headers->{password});
		delete $headers->{username};
		delete $headers->{password};
	}
	while (my($name, $value) = each(%{$headers})) {
		if (lc($name) eq 'accept-encoding') { next; }
		elsif (lc($name) eq 'host') { next; }
		elsif (lc($name) eq 'content-length') { next; }
		$req->header($name => $value);
	}
	$req->header(HTTP_ACCEPT => '*/*');
	$req->header(HTTP_ACCEPT_LANGUAGE => 'en-us');
	$req->header('Content-Type' => 'application/x-www-form-urlencoded');
	my @content;
	while (my($field, $value) = each(%{$data})) {
		my $qfield = url_encode($field);
		my $qvalue = url_encode($value);
		push(@content, "$qfield=$qvalue");
	}
	my $content = join('&', @content) || '';
	$req->content($content);
	
	my $res = $ua->request($req);
	if ($res->is_success) {
		return $res->content;
	} else {
		return 0, $res->status_line;
	}
}


sub parse_query_string {
#=====================================================

=head2 B<parse_query_string>

=cut
#=====================================================
	my $queryString = shift || return '';
	my @pairs = split('&', $queryString);
	my $queryHash;
	foreach my $pair (@pairs) {
		my ($name, $value) = split('=', $pair);
		my $newName = url_decode($name);
		my $newValue = url_decode($value);
		if (ref($queryHash->{$newName}) eq 'ARRAY') {
			push(@{$queryHash->{$newName}}, $newValue);
		} elsif ($queryHash->{$newName}) {
			$queryHash->{$newName} = [$queryHash->{$newName}, $newValue];
		} else {
			$queryHash->{$name} = $value;
		}
	}
	return $queryHash;
}


sub url_decode {
#=====================================================

=head2 B<url_decode>

URL decodes scalar and array values and hash keys and values.
Does not recurse.

=cut
#=====================================================
	my $input = shift;
	if (is_hash($input)) {
		my $newHash;
		while (my($name, $value) = each(%{$input})) {
			my $newName = _url_decode_scalar($name);
			$newHash->{$newName} = _url_decode_scalar($value);
		}
		return $newHash;
	} elsif (ref($input) eq 'ARRAY') {
		my $newArray = [];
		foreach my $value (@{$input}) {
			my $newValue = _url_decode_scalar($value);
			push(@{$newArray}, $newValue);
		}
		return $newArray;
	} elsif (ref($input) eq 'SCALAR') {
		my $newScalar = _url_decode_scalar(${$input});
		return _url_decode_scalar(\$newScalar);
	} elsif (!ref($input)) {
		return _url_decode_scalar($input);
	}
}

sub _url_decode_scalar {
	my $input = shift || return '';
	if (!ref($input)) {
		$input =~ tr/+/ /;
		$input =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
		return $input;
	}
	return '';
}


sub url_encode {
#=====================================================

=head2 B<url_encode>

URL decodes scalar and array values and hash keys and values.
Does not recurse.

=cut
#=====================================================
	my $input = shift;
	if (is_hash($input)) {
		my $newHash;
		while (my($name, $value) = each(%{$input})) {
			my $newName = _url_encode_scalar($name);
			$newHash->{$newName} = _url_encode_scalar($value);
		}
		return $newHash;
	} elsif (ref($input) eq 'ARRAY') {
		my $newArray = [];
		foreach my $value (@{$input}) {
			my $newValue = _url_encode_scalar($value);
			push(@{$newArray}, $newValue);
		}
		return $newArray;
	} elsif (ref($input) eq 'SCALAR') {
		my $newScalar = _url_encode_scalar(${$input});
		return _url_encode_scalar(\$newScalar);
	} elsif (!ref($input)) {
		return _url_encode_scalar($input);
	}
}

sub _url_encode_scalar {
	my $input = shift || return '';
	if (!ref($input)) {
		$input =~ s/([^A-Za-z0-9 ])/sprintf("%%%02X", ord($1))/seg;
		$input =~ tr/ /+/;
		return $input;
	}
	return '';
}


sub parse_json {
#=====================================================

=head2 B<parse_json>

Returns a reference matching the given JSON if successful or scalar error message, if not.

 my $ref = parse_json($jsonString);

=cut
#=====================================================
	my $jsonString = shift || return;
	
	# Newer JSON code
	my $json = JSON->new;
	$json = $json->utf8(0);
	my $perl;
	
	eval { $perl = $json->decode($jsonString); };
	if ($@) {
		print "Error parsing JSON: $@";
		return;
	}
	
	return $perl;
}


sub make_json {
#=====================================================

=head2 B<make_json>

 my $json = make_json($jsonRef);
 my $jsonToPrint = make_json($jsonRef, {
 	splitValues	=> 1,		# Split values greater than 32k
 	includeNulls	=> 1,		# Includes all entries, even those with blank, false, or null values
 	compress		=> 1,		# Don't include unnecessary tabs, spaces, or CRs
 	outputHTML		=> 1,
 	unidecode		=> 1,		# Convert unicode characters to standard ASCII
 	jsonp			=> $callbackFunction	# Return as jsonp using the specified callback function
 } );

=cut
#=====================================================
	my $data = shift;
	my $options = shift;
	my $depth = shift;
	my $tabs = "\t" x $depth;
	my $tabsplus = "$tabs\t";
	my $space = ' ';
	my $n = "\n";
	
	my ($ls, $vs, $qs, $es, $se);
	if ($options->{outputHTML}) {
		$ls = '<span class="l">';
		$vs = '<span class="v">';
		$qs = '<span class="q">';
		$es = '<span class="e">';
		$se = '</span>';
		$tabs = '<span class="t' . $depth . '"></span>';
		$tabsplus = '<span class="t' . ($depth + 1) . '"></span>';
		$space = '&nbsp;';
		$n = "<br />\n";
	}
	
	if ($depth >= 16) {
		print STDERR "Sitemason::Common::make_json - EXCEEDED DEPTH LIMIT ($depth)\n";
		$options->{linesCount}++;
		return "$es\"[EXCEEDED DEPTH LIMIT]\"$se";
	}
	if ($options->{linesCount} >= 100000) {
		print STDERR "Sitemason::Common::make_json - EXCEEDED LINE LIMIT ($options->{linesCount})\n";
		$options->{linesCount}++;
		return "$es\"[EXCEEDED LINE LIMIT]\"$se";
	}
	
	my $splitXML = $options->{splitValues} || $options->{split_values};
	my $includeNulls = $options->{includeNulls} || $options->{include_nulls};
	my $compress = $options->{compress};
	my $jsonp = $options->{jsonp};
	my $json;
	my @subJSON;
	if ($compress) { $tabs = $tabsplus = $space = $n = ''; }
	
	if (ref($data) eq 'HASH') {
		foreach my $name (sort { by_any($a,$b) } (keys(%{$data}))) {
# 			if ($name !~ /^\w/i) { next; }
			if ($name =~ /[^a-zA-Z0-9_:-]/) { next; }
			my $value = $data->{$name};
			if (ref($value) eq 'SCALAR') { $value = ${$value}; }
			if (is_boolean($value)) {
				# booleans
				if ($value) { push(@subJSON, "${tabsplus}${ls}\"$name\"${se}:${space}true"); }
				elsif ($includeNulls) { push(@subJSON, "${tabsplus}${ls}\"$name\"${se}:${space}false"); }
			} elsif ((ref($value) eq 'HASH') || (ref($value) eq 'ARRAY')) {
				my $subJSON = make_json($value,$options,$depth+1);
				if ($subJSON) { push(@subJSON, "${tabsplus}${ls}\"$name\"${se}:${space}$subJSON"); }
			} elsif (!ref($value)) {
				if (defined($value) || $includeNulls) {
					if (!defined($value) && $includeNulls) {
						# nulls
						push(@subJSON, "${tabsplus}${ls}\"$name\"${se}:${space}${vs}null${se}");
					} elsif (($name =~ /^(?:is|does|should|supports|use|include|allow|can|has|require|show|track|display_developer)(?:_|[A-Z])/)) {
						# booleans
						if ($value) { push(@subJSON, "${tabsplus}${ls}\"$name\"${se}:${space}${vs}true${se}"); }
						elsif ($includeNulls) { push(@subJSON, "${tabsplus}${ls}\"$name\"${se}:${space}${vs}false${se}"); }
					} elsif (($name =~ /^display(?:_|[A-Z])/) && !$value && !$includeNulls) {
						# probably booleans
					} elsif ($value || is_number($value)) {
						if (is_number($value) && !$value) { $value = '0'; }
						else { $value = jsonify($value, $options->{outputHTML}, $options->{unidecode}); }
						push(@subJSON, "${tabsplus}${ls}\"$name\"${se}:${space}${qs}\"$value\"${se}");
					} elsif ($includeNulls) {
						# blanks
						$value = jsonify($value, $options->{outputHTML}, $options->{unidecode});
						push(@subJSON, "${tabsplus}${ls}\"$name\"${se}:${space}${qs}\"$value\"${se}");
					}
				}
			}
		}
		if (@subJSON) {
			my $cnt = @subJSON;
			$options->{linesCount} += $cnt;
			$json = "\{${n}";
			foreach my $subJSON (@subJSON) {
				$cnt--;
				if ($cnt) { $json .= "$subJSON,${n}"; }
				else { $json .= "$subJSON${n}"; }
			}
			$json .= "${tabs}\}";
		}
	} elsif (ref($data) eq 'ARRAY') {
		foreach my $item (@{$data}) {
			my $value = $item;
			if (ref($value) eq 'SCALAR') { $value = ${$value}; }
			if ((ref($value) eq 'HASH') || (ref($value) eq 'ARRAY')) {
				my $subJSON = make_json($value,$options,$depth+1);
				if ($subJSON) { push(@subJSON, $subJSON); }
			} elsif (!ref($value)) {
				if (defined($value)) {
					# non nulls
					$value = jsonify($value, $options->{outputHTML}, $options->{unidecode});
					push(@subJSON, "${tabsplus}${qs}\"$value\"${se}");
				} else {
					# nulls
					push(@subJSON, "${tabsplus}${vs}null${se}");
				}
			}
		}
		if (@subJSON) {
			my $cnt = 0;
			$options->{linesCount} += $cnt;
			$json = "\[${n}";
			if (@subJSON[0] =~ /^[\{\[]/) { $json = "\[${n}${tabsplus}"; }
			foreach my $subJSON (@subJSON) {
				$cnt++;
				if ($cnt == @subJSON) { # last
					$json .= "$subJSON${n}";
				}
				else {
					if (@subJSON[$cnt] =~ /^[\{\[]/) {
						$json .= "$subJSON,${space}";
					} else {
						$json .= "$subJSON,${n}";
					}
				}
			}
			$json .= "${tabs}\]";
		}
	}
	
	if ($jsonp && !$depth) { $json = "$jsonp($json)"; }
	
	return $json;
}


sub jsonify {
#=====================================================

=head2 B<jsonify>

Escape text values for JSON.

=cut
#=====================================================
	my $value = shift || return;
	my $isHTML = shift;
	my $shouldUnidecode = shift;
	if ($shouldUnidecode) {
		$value = unidecode($value);
	}
	if ($isHTML) {
		$value = xmlify($value);
		$value =~ s/(?:\r\n|\r|\n)/<br>\n/g;
		$value =~ s/\t/&nbsp; &nbsp; /g;
	} else {
		$value =~ s/\\/\\\\/g;
		$value =~ s/\//\\\//g;
		$value =~ s/"/\\"/g;
		$value =~ s/\r/\\r/g;
		$value =~ s/\n/\\n/g;
		$value =~ s/\t/\\t/g;
#		$value =~ s/[\x00-\x09\x0b-\x1f\x7f]//g;
#		$value =~ s/([\x80-\xff])/'&#'.ord($1).';'/eg;
		$value =~ s/[\xa0]/ /g;
	}
	
	return $value;
}

sub xmlify {
#=====================================================

=head2 B<xmlify>

Escape text values for XML.

=cut
#=====================================================
	foreach (@_) {
		s/&/&#x26;/g;
		s/</&#x3C;/g;
		s/>/&#x3E;/g;
		s/\"/&#x22;/g;
		s/[\x00-\x09\x0b-\x1f\x7f]//g;
		s/(?<![\x80-\xff])([\x80-\xff])(?![\x80-\xff])/'&#'.ord($1).';'/eg;
	}
	if (@_ == 1) { return $_[0]; }
	else { return @_; }
}


sub html_entities_to_text {
#=====================================================

=head2 B<html_entities_to_text>

 my $text = html_entities_to_text($html);

 (c) - &copy; - &#169; - &#xA9;

=cut
#=====================================================
	my $text = shift || return '';
	my @mapping = (
		{ text => ' ',  html => '&nbsp;', unicode => '&#160;', hexcode => '&#xA0;' },
		{ text => '(c)',  html => '&copy;', unicode => '&#196;', hexcode => '&#xA9;' },
		{ text => '(r)',  html => '&reg;', unicode => '&#174;', hexcode => '&#xAE;' },
		{ text => ' degrees',  html => '&deg;', unicode => '&#176;', hexcode => '&#xB0;' },
		{ text => '*',  html => '&middot;', unicode => '&#183;', hexcode => '&#xB7;' },
		{ text => '*', html => '&bull;', unicode => '&#8226;', hexcode => '&#x2022;' },
		{ text => '...', html => '&hellip;', unicode => '&#8230;', hexcode => '&#x2026;' },
		{ text => '(tm)', html => '&trade;', unicode => '&#8482;', hexcode => '&#x2122;' },
		{ text => ' ', html => '&ensp;', unicode => '&#8194;', hexcode => '&#x2002;' },
		{ text => '  ', html => '&emsp;', unicode => '&#8195;', hexcode => '&#x2003;' },
		{ text => ' ', html => '&thinsp;', unicode => '&#8201;', hexcode => '&#x2009;' },
		{ text => '-', html => '&ndash;', unicode => '&#8211;', hexcode => '&#x2013;' },
		{ text => '--', html => '&mdash;', unicode => '&#8212;', hexcode => '&#x2014;' },
		{ text => '\'', html => '&lsquo;', unicode => '&#8216;', hexcode => '&#x2018;' },
		{ text => '\'', html => '&rsquo;', unicode => '&#8217;', hexcode => '&#x2019;' },
		{ text => '"', html => '&ldquo;', unicode => '&#8220;', hexcode => '&#x201C;' },
		{ text => '"', html => '&rdquo;', unicode => '&#8221;', hexcode => '&#x201D;' },
		{ text => '*', html => '&dagger;', unicode => '&#8224;', hexcode => '&#x2020;' },
		{ text => '**', html => '&Dagger;', unicode => '&#8225;', hexcode => '&#x2021;' },
		{ text => ' 0/00', html => '&permil;', unicode => '&#8240;', hexcode => '&#x2030;' },
		{ text => '>', html => '&gt;', unicode => '&#62;', hexcode => '&#x3E;' },
		{ text => '<', html => '&lt;', unicode => '&#60;', hexcode => '&#x3C;' },
		{ text => '"', html => '&quot;', unicode => '&#34;', hexcode => '&#x22;' },
		{ text => "'", html => '&apos;', unicode => '&#39;', hexcode => '&#x27' },
		{ text => '&', html => '&amp;', unicode => '&#38;', hexcode => '&#x26;' }
	);
	
	foreach my $map (@mapping) {
		$text =~ s/$map->{html}/$map->{text}/ig;
		$map->{unicode} =~ s/#/#0*/;
		$text =~ s/$map->{unicode}/$map->{text}/g;
		$map->{hexcode} =~ s/#x/#x0*/;
		$text =~ s/$map->{hexcode}/$map->{text}/ig;
	}
	return $text;
}

sub to_html_entities {
#=====================================================

=head2 B<to_html_entities>

 my $html = to_html_entities($utf8);

=cut
#=====================================================
	my $text = shift || return '';
	my @mapping = (
		{ unicode => '160',  html => '&nbsp;' },
		{ unicode => '169',  html => '&copy;' },
		{ unicode => '174',  html => '&reg;' },
		{ unicode => '176',  html => '&deg;' },
		{ unicode => '183',  html => '&middot;' },
		{ unicode => '8226', html => '&bull;' },
		{ unicode => '8230', html => '&hellip;' },
		{ unicode => '8482', html => '&trade;' },
		{ unicode => '8194', html => '&ensp;' },
		{ unicode => '8195', html => '&emsp;' },
		{ unicode => '8201', html => '&thinsp;' },
		{ unicode => '8211', html => '&ndash;' },
		{ unicode => '8212', html => '&mdash;' },
		{ unicode => '8216', html => '&lsquo;' },
		{ unicode => '8217', html => '&rsquo;' },
		{ unicode => '8220', html => '&ldquo;' },
		{ unicode => '8221', html => '&rdquo;' },
		{ unicode => '8224', html => '&dagger;' },
		{ unicode => '8225', html => '&Dagger;' },
		{ unicode => '8240', html => '&permil;' }
	);
	
	foreach my $map (@mapping) {
		my $char = pack('U', $map->{unicode});
		$text =~ s/$char/$map->{html}/g;
	}
	return $text;
}

sub from_html_entities {
#=====================================================

=head2 B<from_html_entities>

From http://www.w3.org/TR/html4/sgml/entities.html

 my $utf8 = from_html_entities($html);

=cut
#=====================================================
	my $text = shift || return '';
	$text =~ s/\&#(\d+);/chr($1)/eg;
	$text =~ s/\&#x([a-f0-9]+);/chr(hex($1))/ieg;
	if ($text !~ /\&[a-z]+;/i) { return $text; }
	
	my @mapping = (
		{ entity => 'quot',     code => 34 },	# quotation mark = APL quote, U+0022 ISOnum
		{ entity => 'amp',      code => 38 },	# ampersand, U+0026 ISOnum
		{ entity => 'lt',       code => 60 },	# less-than sign, U+003C ISOnum
		{ entity => 'gt',       code => 62 },	# greater-than sign, U+003E ISOnum
		{ entity => 'ensp',     code => 8194 },	# en space, U+2002 ISOpub
		{ entity => 'emsp',     code => 8195 },	# em space, U+2003 ISOpub
		{ entity => 'thinsp',   code => 8201 },	# thin space, U+2009 ISOpub
		{ entity => 'zwnj',     code => 8204 },	# zero width non-joiner, U+200C NEW RFC 2070
		{ entity => 'zwj',      code => 8205 },	# zero width joiner, U+200D NEW RFC 2070
		{ entity => 'lrm',      code => 8206 },	# left-to-right mark, U+200E NEW RFC 2070
		{ entity => 'rlm',      code => 8207 },	# right-to-left mark, U+200F NEW RFC 2070
		{ entity => 'ndash',    code => 8211 },	# en dash, U+2013 ISOpub
		{ entity => 'mdash',    code => 8212 },	# em dash, U+2014 ISOpub
		{ entity => 'lsquo',    code => 8216 },	# left single quotation mark, U+2018 ISOnum
		{ entity => 'rsquo',    code => 8217 },	# right single quotation mark, U+2019 ISOnum
		{ entity => 'sbquo',    code => 8218 },	# single low-9 quotation mark, U+201A NEW
		{ entity => 'ldquo',    code => 8220 },	# left double quotation mark, U+201C ISOnum
		{ entity => 'rdquo',    code => 8221 },	# right double quotation mark, U+201D ISOnum
		{ entity => 'bdquo',    code => 8222 },	# double low-9 quotation mark, U+201E NEW
		{ entity => 'dagger',   code => 8224 },	# dagger, U+2020 ISOpub
		{ entity => 'Dagger',   code => 8225 },	# double dagger, U+2021 ISOpub
		{ entity => 'permil',   code => 8240 },	# per mille sign, U+2030 ISOtech
		{ entity => 'lsaquo',   code => 8249 },	# single left-pointing angle quotation mark, U+2039 ISO proposed
		{ entity => 'rsaquo',   code => 8250 },	# single right-pointing angle quotation mark, U+203A ISO proposed
		{ entity => 'nbsp',     code => 160 },	# no-break space = non-breaking space, U+00A0 ISOnum
		{ entity => 'iexcl',    code => 161 },	# inverted exclamation mark, U+00A1 ISOnum
		{ entity => 'cent',     code => 162 },	# cent sign, U+00A2 ISOnum
		{ entity => 'pound',    code => 163 },	# pound sign, U+00A3 ISOnum
		{ entity => 'curren',   code => 164 },	# currency sign, U+00A4 ISOnum
		{ entity => 'yen',      code => 165 },	# yen sign = yuan sign, U+00A5 ISOnum
		{ entity => 'euro',     code => 8364 },	# euro sign, U+20AC NEW
		{ entity => 'brvbar',   code => 166 },	# broken bar = broken vertical bar, U+00A6 ISOnum
		{ entity => 'sect',     code => 167 },	# section sign, U+00A7 ISOnum
		{ entity => 'uml',      code => 168 },	# diaeresis = spacing diaeresis, U+00A8 ISOdia
		{ entity => 'copy',     code => 169 },	# copyright sign, U+00A9 ISOnum
		{ entity => 'ordf',     code => 170 },	# feminine ordinal indicator, U+00AA ISOnum
		{ entity => 'laquo',    code => 171 },	# left-pointing double angle quotation mark = left pointing guillemet, U+00AB ISOnum
		{ entity => 'not',      code => 172 },	# not sign, U+00AC ISOnum
		{ entity => 'shy',      code => 173 },	# soft hyphen = discretionary hyphen, U+00AD ISOnum
		{ entity => 'reg',      code => 174 },	# registered sign = registered trade mark sign, U+00AE ISOnum
		{ entity => 'macr',     code => 175 },	# macron = spacing macron = overline = APL overbar, U+00AF ISOdia
		{ entity => 'deg',      code => 176 },	# degree sign, U+00B0 ISOnum
		{ entity => 'plusmn',   code => 177 },	# plus-minus sign = plus-or-minus sign, U+00B1 ISOnum
		{ entity => 'sup2',     code => 178 },	# superscript two = superscript digit two = squared, U+00B2 ISOnum
		{ entity => 'sup3',     code => 179 },	# superscript three = superscript digit three = cubed, U+00B3 ISOnum
		{ entity => 'acute',    code => 180 },	# acute accent = spacing acute, U+00B4 ISOdia
		{ entity => 'micro',    code => 181 },	# micro sign, U+00B5 ISOnum
		{ entity => 'para',     code => 182 },	# pilcrow sign = paragraph sign, U+00B6 ISOnum
		{ entity => 'middot',   code => 183 },	# middle dot = Georgian comma = Greek middle dot, U+00B7 ISOnum
		{ entity => 'cedil',    code => 184 },	# cedilla = spacing cedilla, U+00B8 ISOdia
		{ entity => 'sup1',     code => 185 },	# superscript one = superscript digit one, U+00B9 ISOnum
		{ entity => 'ordm',     code => 186 },	# masculine ordinal indicator, U+00BA ISOnum
		{ entity => 'raquo',    code => 187 },	# right-pointing double angle quotation mark = right pointing guillemet, U+00BB ISOnum
		{ entity => 'frac14',   code => 188 },	# vulgar fraction one quarter = fraction one quarter, U+00BC ISOnum
		{ entity => 'frac12',   code => 189 },	# vulgar fraction one half = fraction one half, U+00BD ISOnum
		{ entity => 'frac34',   code => 190 },	# vulgar fraction three quarters = fraction three quarters, U+00BE ISOnum
		{ entity => 'iquest',   code => 191 },	# inverted question mark = turned question mark, U+00BF ISOnum
		{ entity => 'Agrave',   code => 192 },	# latin capital letter A with grave = latin capital letter A grave, U+00C0 ISOlat1
		{ entity => 'Aacute',   code => 193 },	# latin capital letter A with acute, U+00C1 ISOlat1
		{ entity => 'Acirc',    code => 194 },	# latin capital letter A with circumflex, U+00C2 ISOlat1
		{ entity => 'Atilde',   code => 195 },	# latin capital letter A with tilde, U+00C3 ISOlat1
		{ entity => 'Auml',     code => 196 },	# latin capital letter A with diaeresis, U+00C4 ISOlat1
		{ entity => 'Aring',    code => 197 },	# latin capital letter A with ring above = latin capital letter A ring, U+00C5 ISOlat1
		{ entity => 'AElig',    code => 198 },	# latin capital letter AE = latin capital ligature AE, U+00C6 ISOlat1
		{ entity => 'Ccedil',   code => 199 },	# latin capital letter C with cedilla, U+00C7 ISOlat1
		{ entity => 'Egrave',   code => 200 },	# latin capital letter E with grave, U+00C8 ISOlat1
		{ entity => 'Eacute',   code => 201 },	# latin capital letter E with acute, U+00C9 ISOlat1
		{ entity => 'Ecirc',    code => 202 },	# latin capital letter E with circumflex, U+00CA ISOlat1
		{ entity => 'Euml',     code => 203 },	# latin capital letter E with diaeresis, U+00CB ISOlat1
		{ entity => 'Igrave',   code => 204 },	# latin capital letter I with grave, U+00CC ISOlat1
		{ entity => 'Iacute',   code => 205 },	# latin capital letter I with acute, U+00CD ISOlat1
		{ entity => 'Icirc',    code => 206 },	# latin capital letter I with circumflex, U+00CE ISOlat1
		{ entity => 'Iuml',     code => 207 },	# latin capital letter I with diaeresis, U+00CF ISOlat1
		{ entity => 'ETH',      code => 208 },	# latin capital letter ETH, U+00D0 ISOlat1
		{ entity => 'Ntilde',   code => 209 },	# latin capital letter N with tilde, U+00D1 ISOlat1
		{ entity => 'Ograve',   code => 210 },	# latin capital letter O with grave, U+00D2 ISOlat1
		{ entity => 'Oacute',   code => 211 },	# latin capital letter O with acute, U+00D3 ISOlat1
		{ entity => 'Ocirc',    code => 212 },	# latin capital letter O with circumflex, U+00D4 ISOlat1
		{ entity => 'Otilde',   code => 213 },	# latin capital letter O with tilde, U+00D5 ISOlat1
		{ entity => 'Ouml',     code => 214 },	# latin capital letter O with diaeresis, U+00D6 ISOlat1
		{ entity => 'times',    code => 215 },	# multiplication sign, U+00D7 ISOnum
		{ entity => 'Oslash',   code => 216 },	# latin capital letter O with stroke = latin capital letter O slash, U+00D8 ISOlat1
		{ entity => 'Ugrave',   code => 217 },	# latin capital letter U with grave, U+00D9 ISOlat1
		{ entity => 'Uacute',   code => 218 },	# latin capital letter U with acute, U+00DA ISOlat1
		{ entity => 'Ucirc',    code => 219 },	# latin capital letter U with circumflex, U+00DB ISOlat1
		{ entity => 'Uuml',     code => 220 },	# latin capital letter U with diaeresis, U+00DC ISOlat1
		{ entity => 'Yacute',   code => 221 },	# latin capital letter Y with acute, U+00DD ISOlat1
		{ entity => 'THORN',    code => 222 },	# latin capital letter THORN, U+00DE ISOlat1
		{ entity => 'szlig',    code => 223 },	# latin small letter sharp s = ess-zed, U+00DF ISOlat1
		{ entity => 'agrave',   code => 224 },	# latin small letter a with grave = latin small letter a grave, U+00E0 ISOlat1
		{ entity => 'aacute',   code => 225 },	# latin small letter a with acute, U+00E1 ISOlat1
		{ entity => 'acirc',    code => 226 },	# latin small letter a with circumflex, U+00E2 ISOlat1
		{ entity => 'atilde',   code => 227 },	# latin small letter a with tilde, U+00E3 ISOlat1
		{ entity => 'auml',     code => 228 },	# latin small letter a with diaeresis, U+00E4 ISOlat1
		{ entity => 'aring',    code => 229 },	# latin small letter a with ring above = latin small letter a ring, U+00E5 ISOlat1
		{ entity => 'aelig',    code => 230 },	# latin small letter ae = latin small ligature ae, U+00E6 ISOlat1
		{ entity => 'ccedil',   code => 231 },	# latin small letter c with cedilla, U+00E7 ISOlat1
		{ entity => 'egrave',   code => 232 },	# latin small letter e with grave, U+00E8 ISOlat1
		{ entity => 'eacute',   code => 233 },	# latin small letter e with acute, U+00E9 ISOlat1
		{ entity => 'ecirc',    code => 234 },	# latin small letter e with circumflex, U+00EA ISOlat1
		{ entity => 'euml',     code => 235 },	# latin small letter e with diaeresis, U+00EB ISOlat1
		{ entity => 'igrave',   code => 236 },	# latin small letter i with grave, U+00EC ISOlat1
		{ entity => 'iacute',   code => 237 },	# latin small letter i with acute, U+00ED ISOlat1
		{ entity => 'icirc',    code => 238 },	# latin small letter i with circumflex, U+00EE ISOlat1
		{ entity => 'iuml',     code => 239 },	# latin small letter i with diaeresis, U+00EF ISOlat1
		{ entity => 'eth',      code => 240 },	# latin small letter eth, U+00F0 ISOlat1
		{ entity => 'ntilde',   code => 241 },	# latin small letter n with tilde, U+00F1 ISOlat1
		{ entity => 'ograve',   code => 242 },	# latin small letter o with grave, U+00F2 ISOlat1
		{ entity => 'oacute',   code => 243 },	# latin small letter o with acute, U+00F3 ISOlat1
		{ entity => 'ocirc',    code => 244 },	# latin small letter o with circumflex, U+00F4 ISOlat1
		{ entity => 'otilde',   code => 245 },	# latin small letter o with tilde, U+00F5 ISOlat1
		{ entity => 'ouml',     code => 246 },	# latin small letter o with diaeresis, U+00F6 ISOlat1
		{ entity => 'divide',   code => 247 },	# division sign, U+00F7 ISOnum
		{ entity => 'oslash',   code => 248 },	# latin small letter o with stroke, = latin small letter o slash, U+00F8 ISOlat1
		{ entity => 'ugrave',   code => 249 },	# latin small letter u with grave, U+00F9 ISOlat1
		{ entity => 'uacute',   code => 250 },	# latin small letter u with acute, U+00FA ISOlat1
		{ entity => 'ucirc',    code => 251 },	# latin small letter u with circumflex, U+00FB ISOlat1
		{ entity => 'uuml',     code => 252 },	# latin small letter u with diaeresis, U+00FC ISOlat1
		{ entity => 'yacute',   code => 253 },	# latin small letter y with acute, U+00FD ISOlat1
		{ entity => 'thorn',    code => 254 },	# latin small letter thorn, U+00FE ISOlat1
		{ entity => 'yuml',     code => 255 },	# latin small letter y with diaeresis, U+00FF ISOlat1
		{ entity => 'fnof',     code => 402 },	# latin small f with hook = function = florin, U+0192 ISOtech
		{ entity => 'Alpha',    code => 913 },	# greek capital letter alpha, U+0391
		{ entity => 'Beta',     code => 914 },	# greek capital letter beta, U+0392
		{ entity => 'Gamma',    code => 915 },	# greek capital letter gamma, U+0393 ISOgrk3
		{ entity => 'Delta',    code => 916 },	# greek capital letter delta, U+0394 ISOgrk3
		{ entity => 'Epsilon',  code => 917 },	# greek capital letter epsilon, U+0395
		{ entity => 'Zeta',     code => 918 },	# greek capital letter zeta, U+0396
		{ entity => 'Eta',      code => 919 },	# greek capital letter eta, U+0397
		{ entity => 'Theta',    code => 920 },	# greek capital letter theta, U+0398 ISOgrk3
		{ entity => 'Iota',     code => 921 },	# greek capital letter iota, U+0399
		{ entity => 'Kappa',    code => 922 },	# greek capital letter kappa, U+039A
		{ entity => 'Lambda',   code => 923 },	# greek capital letter lambda, U+039B ISOgrk3
		{ entity => 'Mu',       code => 924 },	# greek capital letter mu, U+039C
		{ entity => 'Nu',       code => 925 },	# greek capital letter nu, U+039D
		{ entity => 'Xi',       code => 926 },	# greek capital letter xi, U+039E ISOgrk3
		{ entity => 'Omicron',  code => 927 },	# greek capital letter omicron, U+039F
		{ entity => 'Pi',       code => 928 },	# greek capital letter pi, U+03A0 ISOgrk3
		{ entity => 'Rho',      code => 929 },	# greek capital letter rho, U+03A1
		{ entity => 'Sigma',    code => 931 },	# greek capital letter sigma, U+03A3 ISOgrk3
		{ entity => 'Tau',      code => 932 },	# greek capital letter tau, U+03A4
		{ entity => 'Upsilon',  code => 933 },	# greek capital letter upsilon, U+03A5 ISOgrk3
		{ entity => 'Phi',      code => 934 },	# greek capital letter phi, U+03A6 ISOgrk3
		{ entity => 'Chi',      code => 935 },	# greek capital letter chi, U+03A7
		{ entity => 'Psi',      code => 936 },	# greek capital letter psi, U+03A8 ISOgrk3
		{ entity => 'Omega',    code => 937 },	# greek capital letter omega, U+03A9 ISOgrk3
		{ entity => 'alpha',    code => 945 },	# greek small letter alpha, U+03B1 ISOgrk3
		{ entity => 'beta',     code => 946 },	# greek small letter beta, U+03B2 ISOgrk3
		{ entity => 'gamma',    code => 947 },	# greek small letter gamma, U+03B3 ISOgrk3
		{ entity => 'delta',    code => 948 },	# greek small letter delta, U+03B4 ISOgrk3
		{ entity => 'epsilon',  code => 949 },	# greek small letter epsilon, U+03B5 ISOgrk3
		{ entity => 'zeta',     code => 950 },	# greek small letter zeta, U+03B6 ISOgrk3
		{ entity => 'eta',      code => 951 },	# greek small letter eta, U+03B7 ISOgrk3
		{ entity => 'theta',    code => 952 },	# greek small letter theta, U+03B8 ISOgrk3
		{ entity => 'iota',     code => 953 },	# greek small letter iota, U+03B9 ISOgrk3
		{ entity => 'kappa',    code => 954 },	# greek small letter kappa, U+03BA ISOgrk3
		{ entity => 'lambda',   code => 955 },	# greek small letter lambda, U+03BB ISOgrk3
		{ entity => 'mu',       code => 956 },	# greek small letter mu, U+03BC ISOgrk3
		{ entity => 'nu',       code => 957 },	# greek small letter nu, U+03BD ISOgrk3
		{ entity => 'xi',       code => 958 },	# greek small letter xi, U+03BE ISOgrk3
		{ entity => 'omicron',  code => 959 },	# greek small letter omicron, U+03BF NEW
		{ entity => 'pi',       code => 960 },	# greek small letter pi, U+03C0 ISOgrk3
		{ entity => 'rho',      code => 961 },	# greek small letter rho, U+03C1 ISOgrk3
		{ entity => 'sigmaf',   code => 962 },	# greek small letter final sigma, U+03C2 ISOgrk3
		{ entity => 'sigma',    code => 963 },	# greek small letter sigma, U+03C3 ISOgrk3
		{ entity => 'tau',      code => 964 },	# greek small letter tau, U+03C4 ISOgrk3
		{ entity => 'upsilon',  code => 965 },	# greek small letter upsilon, U+03C5 ISOgrk3
		{ entity => 'phi',      code => 966 },	# greek small letter phi, U+03C6 ISOgrk3
		{ entity => 'chi',      code => 967 },	# greek small letter chi, U+03C7 ISOgrk3
		{ entity => 'psi',      code => 968 },	# greek small letter psi, U+03C8 ISOgrk3
		{ entity => 'omega',    code => 969 },	# greek small letter omega, U+03C9 ISOgrk3
		{ entity => 'thetasym', code => 977 },	# greek small letter theta symbol, U+03D1 NEW
		{ entity => 'upsih',    code => 978 },	# greek upsilon with hook symbol, U+03D2 NEW
		{ entity => 'piv',      code => 982 },	# greek pi symbol, U+03D6 ISOgrk3
		{ entity => 'bull',     code => 8226 },	# bullet = black small circle, U+2022 ISOpub 
		{ entity => 'hellip',   code => 8230 },	# horizontal ellipsis = three dot leader, U+2026 ISOpub 
		{ entity => 'prime',    code => 8242 },	# prime = minutes = feet, U+2032 ISOtech
		{ entity => 'Prime',    code => 8243 },	# double prime = seconds = inches, U+2033 ISOtech
		{ entity => 'oline',    code => 8254 },	# overline = spacing overscore, U+203E NEW
		{ entity => 'frasl',    code => 8260 },	# fraction slash, U+2044 NEW
		{ entity => 'weierp',   code => 8472 },	# script capital P = power set = Weierstrass p, U+2118 ISOamso
		{ entity => 'image',    code => 8465 },	# blackletter capital I = imaginary part, U+2111 ISOamso
		{ entity => 'real',     code => 8476 },	# blackletter capital R = real part symbol, U+211C ISOamso
		{ entity => 'trade',    code => 8482 },	# trade mark sign, U+2122 ISOnum
		{ entity => 'alefsym',  code => 8501 },	# alef symbol = first transfinite cardinal, U+2135 NEW
		{ entity => 'larr',     code => 8592 },	# leftwards arrow, U+2190 ISOnum
		{ entity => 'uarr',     code => 8593 },	# upwards arrow, U+2191 ISOnum
		{ entity => 'rarr',     code => 8594 },	# rightwards arrow, U+2192 ISOnum
		{ entity => 'darr',     code => 8595 },	# downwards arrow, U+2193 ISOnum
		{ entity => 'harr',     code => 8596 },	# left right arrow, U+2194 ISOamsa
		{ entity => 'crarr',    code => 8629 },	# downwards arrow with corner leftwards = carriage return, U+21B5 NEW
		{ entity => 'lArr',     code => 8656 },	# leftwards double arrow, U+21D0 ISOtech
		{ entity => 'uArr',     code => 8657 },	# upwards double arrow, U+21D1 ISOamsa
		{ entity => 'rArr',     code => 8658 },	# rightwards double arrow, U+21D2 ISOtech
		{ entity => 'dArr',     code => 8659 },	# downwards double arrow, U+21D3 ISOamsa
		{ entity => 'hArr',     code => 8660 },	# left right double arrow, U+21D4 ISOamsa
		{ entity => 'forall',   code => 8704 },	# for all, U+2200 ISOtech
		{ entity => 'part',     code => 8706 },	# partial differential, U+2202 ISOtech 
		{ entity => 'exist',    code => 8707 },	# there exists, U+2203 ISOtech
		{ entity => 'empty',    code => 8709 },	# empty set = null set = diameter, U+2205 ISOamso
		{ entity => 'nabla',    code => 8711 },	# nabla = backward difference, U+2207 ISOtech
		{ entity => 'isin',     code => 8712 },	# element of, U+2208 ISOtech
		{ entity => 'notin',    code => 8713 },	# not an element of, U+2209 ISOtech
		{ entity => 'ni',       code => 8715 },	# contains as member, U+220B ISOtech
		{ entity => 'prod',     code => 8719 },	# n-ary product = product sign, U+220F ISOamsb
		{ entity => 'sum',      code => 8721 },	# n-ary sumation, U+2211 ISOamsb
		{ entity => 'minus',    code => 8722 },	# minus sign, U+2212 ISOtech
		{ entity => 'lowast',   code => 8727 },	# asterisk operator, U+2217 ISOtech
		{ entity => 'radic',    code => 8730 },	# square root = radical sign, U+221A ISOtech
		{ entity => 'prop',     code => 8733 },	# proportional to, U+221D ISOtech
		{ entity => 'infin',    code => 8734 },	# infinity, U+221E ISOtech
		{ entity => 'ang',      code => 8736 },	# angle, U+2220 ISOamso
		{ entity => 'and',      code => 8743 },	# logical and = wedge, U+2227 ISOtech
		{ entity => 'or',       code => 8744 },	# logical or = vee, U+2228 ISOtech
		{ entity => 'cap',      code => 8745 },	# intersection = cap, U+2229 ISOtech
		{ entity => 'cup',      code => 8746 },	# union = cup, U+222A ISOtech
		{ entity => 'int',      code => 8747 },	# integral, U+222B ISOtech
		{ entity => 'there4',   code => 8756 },	# therefore, U+2234 ISOtech
		{ entity => 'sim',      code => 8764 },	# tilde operator = varies with = similar to, U+223C ISOtech
		{ entity => 'cong',     code => 8773 },	# approximately equal to, U+2245 ISOtech
		{ entity => 'asymp',    code => 8776 },	# almost equal to = asymptotic to, U+2248 ISOamsr
		{ entity => 'ne',       code => 8800 },	# not equal to, U+2260 ISOtech
		{ entity => 'equiv',    code => 8801 },	# identical to, U+2261 ISOtech
		{ entity => 'le',       code => 8804 },	# less-than or equal to, U+2264 ISOtech
		{ entity => 'ge',       code => 8805 },	# greater-than or equal to, U+2265 ISOtech
		{ entity => 'sub',      code => 8834 },	# subset of, U+2282 ISOtech
		{ entity => 'sup',      code => 8835 },	# superset of, U+2283 ISOtech
		{ entity => 'nsub',     code => 8836 },	# not a subset of, U+2284 ISOamsn
		{ entity => 'sube',     code => 8838 },	# subset of or equal to, U+2286 ISOtech
		{ entity => 'supe',     code => 8839 },	# superset of or equal to, U+2287 ISOtech
		{ entity => 'oplus',    code => 8853 },	# circled plus = direct sum, U+2295 ISOamsb
		{ entity => 'otimes',   code => 8855 },	# circled times = vector product, U+2297 ISOamsb
		{ entity => 'perp',     code => 8869 },	# up tack = orthogonal to = perpendicular, U+22A5 ISOtech
		{ entity => 'sdot',     code => 8901 },	# dot operator, U+22C5 ISOamsb
		{ entity => 'lceil',    code => 8968 },	# left ceiling = apl upstile, U+2308 ISOamsc 
		{ entity => 'rceil',    code => 8969 },	# right ceiling, U+2309 ISOamsc 
		{ entity => 'lfloor',   code => 8970 },	# left floor = apl downstile, U+230A ISOamsc 
		{ entity => 'rfloor',   code => 8971 },	# right floor, U+230B ISOamsc 
		{ entity => 'lang',     code => 9001 },	# left-pointing angle bracket = bra, U+2329 ISOtech
		{ entity => 'rang',     code => 9002 },	# right-pointing angle bracket = ket, U+232A ISOtech
		{ entity => 'loz',      code => 9674 },	# lozenge, U+25CA ISOpub
		{ entity => 'spades',   code => 9824 },	# black spade suit, U+2660 ISOpub
		{ entity => 'clubs',    code => 9827 },	# black club suit = shamrock, U+2663 ISOpub
		{ entity => 'hearts',   code => 9829 },	# black heart suit = valentine, U+2665 ISOpub
		{ entity => 'diams',    code => 9830 },	# black diamond suit, U+2666 ISOpub
		{ entity => 'OElig',    code => 338 },	# latin capital ligature OE, U+0152 ISOlat2
		{ entity => 'oelig',    code => 339 },	# latin small ligature oe, U+0153 ISOlat2
		{ entity => 'Scaron',   code => 352 },	# latin capital letter S with caron, U+0160 ISOlat2
		{ entity => 'scaron',   code => 353 },	# latin small letter s with caron, U+0161 ISOlat2
		{ entity => 'Yuml',     code => 376 },	# latin capital letter Y with diaeresis, U+0178 ISOlat2
		{ entity => 'circ',     code => 710 },	# modifier letter circumflex accent, U+02C6 ISOpub
		{ entity => 'tilde',    code => 732 },	# small tilde, U+02DC ISOdia
	);
	
	my $cnt = 1;
	foreach my $map (@mapping) {
		unless ($cnt++ % 10) {
			if ($text !~ /\&[a-z]+;/i) { last; }
		}
		my $char = pack('U', $map->{code});
		$text =~ s/\&$map->{entity};/$char/g;
	}
	return $text;
}


sub convert_to_utf8 {
#=====================================================

=head2 B<convert_to_utf8>

=cut
#=====================================================
	my $source = shift;
	my $list = to_array($source);
	my $mapping = {
		'25'	=> 0x27,
		'128'	=> 0xC4,	'129'	=> 0xC5,	'130'	=> 0xC7,	'131'	=> 0xC9,
		'132'	=> 0xD1,	'133'	=> 0xD6,	'134'	=> 0xDC,	'135'	=> 0xE1,
		'136'	=> 0xE0,	'137'	=> 0xE2,	'138'	=> 0xE4,	'139'	=> 0xE3,
		'140'	=> 0xE5,	'141'	=> 0xE7,	'142'	=> 0xE9,	'143'	=> 0xE8,
		'144'	=> 0xEA,	'145'	=> 0xEB,	'146'	=> 0xED,	'147'	=> 0xEC,
		'148'	=> 0xEE,	'149'	=> 0xEF,	'150'	=> 0xF1,	'151'	=> 0xF3,
		'152'	=> 0xF2,	'153'	=> 0xF4,	'154'	=> 0xF6,	'155'	=> 0xF5,
		'156'	=> 0xFA,	'157'	=> 0xF9,	'158'	=> 0xFB,	'159'	=> 0xFC,
		'160'	=> 0x2020,	'161'	=> 0xB0,	'162'	=> 0xA2,	'163'	=> 0xA3,
		'164'	=> 0xA7,	'165'	=> 0x2022,	'166'	=> 0xB6,	'167'	=> 0xDF,
		'168'	=> 0xAE,	'169'	=> 0xA9,	'170'	=> 0x2122,	'171'	=> 0xB4,
		'172'	=> 0xA8,	'173'	=> 0x2260,	'174'	=> 0xC6,	'175'	=> 0xD8,
		'176'	=> 0x221E,	'177'	=> 0xB1,	'178'	=> 0x2264,	'179'	=> 0x2265,
		'180'	=> 0xA5,	'181'	=> 0xB5,	'182'	=> 0x2202,	'183'	=> 0x2211,
		'184'	=> 0x220F,	'185'	=> 0x03C0,	'186'	=> 0x222B,	'187'	=> 0xAA,
		'188'	=> 0xBA,	'189'	=> 0x03A9,	'190'	=> 0xE6,	'191'	=> 0xF8,
		'192'	=> 0xBF,	'193'	=> 0xA1,	'194'	=> 0xAC,	'195'	=> 0x221A,
		'196'	=> 0x0192,	'197'	=> 0x2248,	'198'	=> 0x2206,	'199'	=> 0xAB,
		'200'	=> 0xBB,	'201'	=> 0x2026,	'202'	=> 0xA0,	'203'	=> 0xC0,
		'204'	=> 0xC3,	'205'	=> 0xD5,	'206'	=> 0x0152,	'207'	=> 0x0153,
		'208'	=> 0x2013,	'209'	=> 0x2014,	'210'	=> 0x201C,	'211'	=> 0x201D,
		'212'	=> 0x2018,	'213'	=> 0x2019,	'214'	=> 0xF7,	'215'	=> 0x25CA,
		'216'	=> 0xFF,	'217'	=> 0x0178,	'218'	=> 0x2044,	'219'	=> 0x20AC,
		'220'	=> 0x2039,	'221'	=> 0x203A,	'222'	=> 0xFB01,	'223'	=> 0xFB02,
		'224'	=> 0x2021,	'225'	=> 0xB7,	'226'	=> 0x201A,	'227'	=> 0x201E,
		'228'	=> 0x2030,	'229'	=> 0xC2,	'230'	=> 0xCA,	'231'	=> 0xC1,
		'232'	=> 0xCB,	'233'	=> 0xC8,	'234'	=> 0xCD,	'235'	=> 0xCE,
		'236'	=> 0xCF,	'237'	=> 0xCC,	'238'	=> 0xD3,	'239'	=> 0xD4,
		'240'	=> 0xF8FF,	'241'	=> 0xD2,	'242'	=> 0xDA,	'243'	=> 0xDB,
		'244'	=> 0xD9,	'245'	=> 0x0131,	'246'	=> 0x02C6,	'247'	=> 0x02DC,
		'248'	=> 0xAF,	'249'	=> 0x02D8,	'250'	=> 0x02D9,	'251'	=> 0x02DA,
		'252'	=> 0xB8,	'253'	=> 0x02DD,	'254'	=> 0x02DB,	'255'	=> 0x02C7
	};
	my $utf8List = [];
	foreach my $text (@{$list}) {
		my $utf8;
		my $lastChar;
		my $isUTF8;
		my $hasSpecials;
		my @chars = split('', $text);
		my @log;
		foreach my $char (@chars) {
			my $o = ord($char);
			if ($o > 127) { push(@log, $char); }
			if ($mapping->{$o}) {
				my $code = pack('U', $mapping->{$o});
				$utf8 .= $code;
				$hasSpecials = 1;
			}
			elsif ($o >= 32) { $utf8 .= $char; }
			elsif (($o == 9) || ($o == 10) || ($o == 12) || ($o == 13)) { $utf8 .= $char; }
			if (($o > 127) && ($lastChar > 127)) { $isUTF8 = 1; last; }
			$lastChar = $o;
		}
		if ($isUTF8) { $utf8 = $text; }
		elsif ($hasSpecials) {
			print STDERR "Converting from old encoding to utf8\n";
			from_to($utf8, "unicode", "utf8");
		}
		push(@{$utf8List}, $utf8);
	}
	if (!ref($source)) { return $utf8List->[0]; }
	elsif (ref($source) eq 'ARRAY') { return $utf8List; }
}


sub read_vfile {
#=====================================================

=head2 B<read_vfile>

=cut
#=====================================================
	my $vfile = shift || return;
	
	eval {
		require Text::vFile::asData;
		Text::vFile::asData->import();
	};
	if ($@) { return; }
	
	my @lines = split("(?:\r\n|\r|\n)", $vfile);
	my $vfileRef = Text::vFile::asData->new->parse_lines( @lines );
	my $container = _read_vfile_internal(first($vfileRef->{objects}));
	
	return $container;
}

sub _read_vfile_internal {
	my $item = shift || return;
	my $convertedItem = { type => lc($item->{type}) };
	
	if ($item->{properties}) {
		while (my($name, $value) = each(%{$item->{properties}})) {
			if (is_array($value) && @{$value} > 1) {
				foreach my $subitem (@{$value}) {
					my $convertedSubItem = {};
					_read_vfile_property($convertedSubItem, $name, $subitem);
					push(@{$convertedItem->{lc($name) . '_array'}}, $convertedSubItem);
				}
			}
			my $entry = first($value);
			_read_vfile_property($convertedItem, $name, $entry);
		}
	}
	
	if (is_array_with_content($item->{objects})) {
		$convertedItem->{items} = [];
		foreach my $subitem (@{$item->{objects}}) {
			my $convertedSubItem = _read_vfile_internal($subitem);
			push(@{$convertedItem->{items}}, $convertedSubItem);
		}
	}
	
	return $convertedItem;
}

sub _read_vfile_property {
	my $item = shift || return;
	my $name = shift || return;
	my $entry = shift || return;
	
	if ($name =~ /^(?:completed|created|dtend|dtstamp|dtstart|due|last-modified)$/i) {
		if ($entry->{value} =~ /^(\d{4})(\d{2})(\d{2})$/) {
			$item->{lc($name)} = sprintf("%04d-%02d-%02d", $1, $2, $3);
		} elsif ($entry->{value} =~ /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})z$/i) {
			$item->{lc($name)} = sprintf("%04d-%02d-%02d %d:%02d:%02d z", $1, $2, $3, $4, $5, $6);
		} elsif ($entry->{value} =~ /^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})$/) {
			$item->{lc($name)} = sprintf("%04d-%02d-%02d %d:%02d:%02d", $1, $2, $3, $4, $5, $6);
		} else {
			$item->{lc($name)} = _unvfileify($entry->{value});
		}
	} else {
		$item->{lc($name)} = _unvfileify($entry->{value});
	}
	if ($entry->{param}) {
		while (my($pname, $pvalue) = each(%{$entry->{param}})) {
			$item->{lc($name) . '_' . lc($pname)} = $pvalue;
		}
	}
}

sub _unvfileify {
	my $icsValue = shift || return;
	$icsValue =~ s/\\n/\n/g;
	$icsValue =~ s/\\(.)/$1/g;
	$icsValue =~ s/(?:^\s+|\s+$)//g;
	return $icsValue;
}

sub is_boolean {
#=====================================================

=head2 B<is_boolean>

 is_boolean($value) || return;

=cut
#=====================================================
	my $value = shift;
	if (ref($value) =~ /\bBoolean$/i) {
		return TRUE;
	}
	return undef;
}

sub is_text {
#=====================================================

=head2 B<is_text>

 is_text($value) || return;

=cut
#=====================================================
	my $value = shift;
	if (!ref($value) && defined($value)) {
		if ($value =~ /\S/) {
			return TRUE;
		}
	}
	return undef;
}

sub is_json {
#=====================================================

=head2 B<is_json>

 is_json($value) || return;

=cut
#=====================================================
	my $value = shift;
	if (!ref($value) && defined($value)) {
		if (($value =~ /^\s*\{/) && ($value =~ /\}\s*$/)) { return TRUE; }
		if (($value =~ /^\s*\[/) && ($value =~ /\]\s*$/)) { return TRUE; }
	}
	return undef;
}

sub is_pos_int {
#=====================================================

=head2 B<is_pos_int>

 is_pos_int($value) || return;
 is_pos_int($value, $min, $max) || return;

=cut
#=====================================================
	my $value = shift;
	my $min = shift;
	my $max = shift;
	if (!ref($value) && defined($value)) {
		if ($value =~ /^(\d+)$/) {
			my $inRange = TRUE;
			if (defined($min) && ($value < $min)) { undef $inRange; }
			if (defined($max) && ($value > $max)) { undef $inRange; }
			return $inRange;
		}
	}
	return undef;
}

sub is_number {
#=====================================================

=head2 B<is_number>

Started with a simple number to text comparison, then it got out of hand. If there are any problems with this, it will be time to scrap this approach and find something simpler.

 is_number($value) || return;
 is_number($value, $min, $max) || return;

=cut
#=====================================================
	my $value = shift;
	my $min = shift;
	my $max = shift;
	if (!ref($value) && defined($value)) {
		# Strip leading zeros
		if ($value =~ /\./) { $value =~ s/\b0+(\d*?\.)/$1/; }
		elsif ($value) { $value =~ s/\b0+(\d*?)/$1/; }
		# Crop digits
		if ($value =~ /\./) {
			# Count digits before decimal point
			my $pre;
			if ($value =~ /\d\./) { ($pre) = $value =~ /\b(\d+)(?:\.|\b)/; }
			else { $value =~ s/\./0\./; }
			# Count digits after decimal point
			my ($post) = $value =~ /\.(\d+)\b/;
			if ((length($pre) + length($post)) > 15) {
				# Crop zeros
				my $target = 15 - length($pre);
				if ($target > 0) {
					$value =~ s/(\.\d{$target})\d+\b/$1/;
				} else {
					$value =~ s/\.\d+\b/$1/;
				}
			}
		}
		# Strip trailing zeros
		$value =~ s/(\.\d*?)0+\b/$1/;
		if (($value+0) eq $value) {
			my $inRange = TRUE;
			if (defined($min) && ($value < $min)) { undef $inRange; }
			if (defined($max) && ($value > $max)) { undef $inRange; }
			return $inRange;
		}
	}
	return undef;
}

sub is_ordinal {
#=====================================================

=head2 B<is_ordinal>

 Recognizes English and English metaphones of digit-based ordinals.

=cut
#=====================================================
	my $ordinal = shift;
	
	if ($ordinal =~ /^[1-9]\d*(?:st|n[dt]|r[dt]|th)$/i) { return TRUE; }
}

sub is_array {
#=====================================================

=head2 B<is_array>

Returns 1 if the argument is an array ref and has one or more elements.

=cut
#=====================================================
	my $array = shift || return;
	if (ref($array) eq 'ARRAY') { return TRUE; }
	return;
}

sub is_array_with_content {
#=====================================================

=head2 B<is_array_with_content>

=cut
#=====================================================
	my $array = shift || return;
	if (is_array($array) && @{$array}) { return TRUE; }
	return;
}

sub is_hash {
#=====================================================

=head2 B<is_hash>

Returns positive if the argument is a hash ref.

=cut
#=====================================================
	my $hash = shift || return;
	if ((ref($hash) eq 'HASH') || ($hash =~ /=HASH\(/)) { return TRUE; }
	return;
}

sub is_hash_with_content {
#=====================================================

=head2 B<is_hash_with_content>

=cut
#=====================================================
	my $hash = shift || return;
	if (is_hash($hash) && keys(%{$hash})) { return TRUE; }
	return;
}

sub is_hash_key {
#=====================================================

=head2 B<is_hash_key>

 if (is_hash_key($hash, $key))

=cut
#=====================================================
	my $hash = shift || return;
	my $key = shift || return;
	if (is_hash($hash) && exists($hash->{$key})) { return TRUE; }
	return;
}


sub is_array_hash {
#=====================================================

=head2 B<is_array_hash>

Returns positive if argument is an array containing only one or more hash refs.
Returns defined if argument is an array containing only zero or more hash refs.
Does not recurse.

 if (is_array_hash($arrayHash))			# array with only hashes
 if (defined(is_array_hash($arrayHash)))	# empty array or array with only hashes

=cut
#=====================================================
	my $array = shift || return;
	my $answer;
	if (ref($array) eq 'ARRAY') {
		if (@{$array}) {
			foreach my $value (@{$array}) {
				if (ref($value) ne 'HASH') { return; }
			}
			return TRUE;
		}
		return 0;
	}
	return;
}

sub is_array_hash_with_content {
#=====================================================

=head2 B<is_array_hash_with_content>

=cut
#=====================================================
	my $array = shift || return;
	if (is_array_hash($array) && @{$array}) { return TRUE; }
	return;
}

sub is_object {
#=====================================================

=head2 B<is_object>

Returns positive if the argument is an object.

=cut
#=====================================================
	my $object = shift || return;
	if ((ref($object) =~ /::/) && is_hash($object)) { return TRUE; }
	return;
}

sub isDomain {
#=====================================================

=head2 B<isDomain>

=cut
#=====================================================
	my $domain = lc(shift) || return;
	
	# http://data.iana.org/TLD/tlds-alpha-by-domain.txt
	# Version 2017020900
	my $topLevelList = ['COM', 'ORG', 'EDU', 'NET',
'AAA', 'AARP', 'ABARTH', 'ABB', 'ABBOTT', 'ABBVIE', 'ABC', 'ABLE', 'ABOGADO', 'ABUDHABI', 'AC', 'ACADEMY',
'ACCENTURE', 'ACCOUNTANT', 'ACCOUNTANTS', 'ACO', 'ACTIVE', 'ACTOR', 'AD', 'ADAC', 'ADS', 'ADULT', 'AE', 'AEG',
'AERO', 'AETNA', 'AF', 'AFAMILYCOMPANY', 'AFL', 'AG', 'AGAKHAN', 'AGENCY', 'AI', 'AIG', 'AIGO', 'AIRBUS',
'AIRFORCE', 'AIRTEL', 'AKDN', 'AL', 'ALFAROMEO', 'ALIBABA', 'ALIPAY', 'ALLFINANZ', 'ALLSTATE', 'ALLY', 'ALSACE', 'ALSTOM',
'AM', 'AMERICANEXPRESS', 'AMERICANFAMILY', 'AMEX', 'AMFAM', 'AMICA', 'AMSTERDAM', 'ANALYTICS', 'ANDROID', 'ANQUAN', 'ANZ', 'AO',
'AOL', 'APARTMENTS', 'APP', 'APPLE', 'AQ', 'AQUARELLE', 'AR', 'ARAMCO', 'ARCHI', 'ARMY', 'ARPA', 'ART',
'ARTE', 'AS', 'ASDA', 'ASIA', 'ASSOCIATES', 'AT', 'ATHLETA', 'ATTORNEY', 'AU', 'AUCTION', 'AUDI', 'AUDIBLE',
'AUDIO', 'AUSPOST', 'AUTHOR', 'AUTO', 'AUTOS', 'AVIANCA', 'AW', 'AWS', 'AX', 'AXA', 'AZ', 'AZURE',
'BA', 'BABY', 'BAIDU', 'BANAMEX', 'BANANAREPUBLIC', 'BAND', 'BANK', 'BAR', 'BARCELONA', 'BARCLAYCARD', 'BARCLAYS', 'BAREFOOT',
'BARGAINS', 'BASEBALL', 'BASKETBALL', 'BAUHAUS', 'BAYERN', 'BB', 'BBC', 'BBT', 'BBVA', 'BCG', 'BCN', 'BD',
'BE', 'BEATS', 'BEAUTY', 'BEER', 'BENTLEY', 'BERLIN', 'BEST', 'BESTBUY', 'BET', 'BF', 'BG', 'BH',
'BHARTI', 'BI', 'BIBLE', 'BID', 'BIKE', 'BING', 'BINGO', 'BIO', 'BIZ', 'BJ', 'BLACK', 'BLACKFRIDAY',
'BLANCO', 'BLOCKBUSTER', 'BLOG', 'BLOOMBERG', 'BLUE', 'BM', 'BMS', 'BMW', 'BN', 'BNL', 'BNPPARIBAS', 'BO',
'BOATS', 'BOEHRINGER', 'BOFA', 'BOM', 'BOND', 'BOO', 'BOOK', 'BOOKING', 'BOOTS', 'BOSCH', 'BOSTIK', 'BOSTON',
'BOT', 'BOUTIQUE', 'BOX', 'BR', 'BRADESCO', 'BRIDGESTONE', 'BROADWAY', 'BROKER', 'BROTHER', 'BRUSSELS', 'BS', 'BT',
'BUDAPEST', 'BUGATTI', 'BUILD', 'BUILDERS', 'BUSINESS', 'BUY', 'BUZZ', 'BV', 'BW', 'BY', 'BZ', 'BZH',
'CA', 'CAB', 'CAFE', 'CAL', 'CALL', 'CALVINKLEIN', 'CAM', 'CAMERA', 'CAMP', 'CANCERRESEARCH', 'CANON', 'CAPETOWN',
'CAPITAL', 'CAPITALONE', 'CAR', 'CARAVAN', 'CARDS', 'CARE', 'CAREER', 'CAREERS', 'CARS', 'CARTIER', 'CASA', 'CASE',
'CASEIH', 'CASH', 'CASINO', 'CAT', 'CATERING', 'CATHOLIC', 'CBA', 'CBN', 'CBRE', 'CBS', 'CC', 'CD',
'CEB', 'CENTER', 'CEO', 'CERN', 'CF', 'CFA', 'CFD', 'CG', 'CH', 'CHANEL', 'CHANNEL', 'CHASE',
'CHAT', 'CHEAP', 'CHINTAI', 'CHLOE', 'CHRISTMAS', 'CHROME', 'CHRYSLER', 'CHURCH', 'CI', 'CIPRIANI', 'CIRCLE', 'CISCO',
'CITADEL', 'CITI', 'CITIC', 'CITY', 'CITYEATS', 'CK', 'CL', 'CLAIMS', 'CLEANING', 'CLICK', 'CLINIC', 'CLINIQUE',
'CLOTHING', 'CLOUD', 'CLUB', 'CLUBMED', 'CM', 'CN', 'CO', 'COACH', 'CODES', 'COFFEE', 'COLLEGE', 'COLOGNE',
'COMCAST', 'COMMBANK', 'COMMUNITY', 'COMPANY', 'COMPARE', 'COMPUTER', 'COMSEC', 'CONDOS', 'CONSTRUCTION', 'CONSULTING', 'CONTACT', 'CONTRACTORS',
'COOKING', 'COOKINGCHANNEL', 'COOL', 'COOP', 'CORSICA', 'COUNTRY', 'COUPON', 'COUPONS', 'COURSES', 'CR', 'CREDIT', 'CREDITCARD',
'CREDITUNION', 'CRICKET', 'CROWN', 'CRS', 'CRUISE', 'CRUISES', 'CSC', 'CU', 'CUISINELLA', 'CV', 'CW', 'CX',
'CY', 'CYMRU', 'CYOU', 'CZ', 'DABUR', 'DAD', 'DANCE', 'DATA', 'DATE', 'DATING', 'DATSUN', 'DAY',
'DCLK', 'DDS', 'DE', 'DEAL', 'DEALER', 'DEALS', 'DEGREE', 'DELIVERY', 'DELL', 'DELOITTE', 'DELTA', 'DEMOCRAT',
'DENTAL', 'DENTIST', 'DESI', 'DESIGN', 'DEV', 'DHL', 'DIAMONDS', 'DIET', 'DIGITAL', 'DIRECT', 'DIRECTORY', 'DISCOUNT',
'DISCOVER', 'DISH', 'DIY', 'DJ', 'DK', 'DM', 'DNP', 'DO', 'DOCS', 'DOCTOR', 'DODGE', 'DOG',
'DOHA', 'DOMAINS', 'DOT', 'DOWNLOAD', 'DRIVE', 'DTV', 'DUBAI', 'DUCK', 'DUNLOP', 'DUNS', 'DUPONT', 'DURBAN',
'DVAG', 'DVR', 'DZ', 'EARTH', 'EAT', 'EC', 'ECO', 'EDEKA', 'EDUCATION', 'EE', 'EG', 'EMAIL',
'EMERCK', 'ENERGY', 'ENGINEER', 'ENGINEERING', 'ENTERPRISES', 'EPOST', 'EPSON', 'EQUIPMENT', 'ER', 'ERICSSON', 'ERNI', 'ES',
'ESQ', 'ESTATE', 'ESURANCE', 'ET', 'EU', 'EUROVISION', 'EUS', 'EVENTS', 'EVERBANK', 'EXCHANGE', 'EXPERT', 'EXPOSED',
'EXPRESS', 'EXTRASPACE', 'FAGE', 'FAIL', 'FAIRWINDS', 'FAITH', 'FAMILY', 'FAN', 'FANS', 'FARM', 'FARMERS', 'FASHION',
'FAST', 'FEDEX', 'FEEDBACK', 'FERRARI', 'FERRERO', 'FI', 'FIAT', 'FIDELITY', 'FIDO', 'FILM', 'FINAL', 'FINANCE',
'FINANCIAL', 'FIRE', 'FIRESTONE', 'FIRMDALE', 'FISH', 'FISHING', 'FIT', 'FITNESS', 'FJ', 'FK', 'FLICKR', 'FLIGHTS',
'FLIR', 'FLORIST', 'FLOWERS', 'FLY', 'FM', 'FO', 'FOO', 'FOOD', 'FOODNETWORK', 'FOOTBALL', 'FORD', 'FOREX',
'FORSALE', 'FORUM', 'FOUNDATION', 'FOX', 'FR', 'FREE', 'FRESENIUS', 'FRL', 'FROGANS', 'FRONTDOOR', 'FRONTIER', 'FTR',
'FUJITSU', 'FUJIXEROX', 'FUN', 'FUND', 'FURNITURE', 'FUTBOL', 'FYI', 'GA', 'GAL', 'GALLERY', 'GALLO', 'GALLUP',
'GAME', 'GAMES', 'GAP', 'GARDEN', 'GB', 'GBIZ', 'GD', 'GDN', 'GE', 'GEA', 'GENT', 'GENTING',
'GEORGE', 'GF', 'GG', 'GGEE', 'GH', 'GI', 'GIFT', 'GIFTS', 'GIVES', 'GIVING', 'GL', 'GLADE',
'GLASS', 'GLE', 'GLOBAL', 'GLOBO', 'GM', 'GMAIL', 'GMBH', 'GMO', 'GMX', 'GN', 'GODADDY', 'GOLD',
'GOLDPOINT', 'GOLF', 'GOO', 'GOODHANDS', 'GOODYEAR', 'GOOG', 'GOOGLE', 'GOP', 'GOT', 'GOV', 'GP', 'GQ',
'GR', 'GRAINGER', 'GRAPHICS', 'GRATIS', 'GREEN', 'GRIPE', 'GROUP', 'GS', 'GT', 'GU', 'GUARDIAN', 'GUCCI',
'GUGE', 'GUIDE', 'GUITARS', 'GURU', 'GW', 'GY', 'HAIR', 'HAMBURG', 'HANGOUT', 'HAUS', 'HBO', 'HDFC',
'HDFCBANK', 'HEALTH', 'HEALTHCARE', 'HELP', 'HELSINKI', 'HERE', 'HERMES', 'HGTV', 'HIPHOP', 'HISAMITSU', 'HITACHI', 'HIV',
'HK', 'HKT', 'HM', 'HN', 'HOCKEY', 'HOLDINGS', 'HOLIDAY', 'HOMEDEPOT', 'HOMEGOODS', 'HOMES', 'HOMESENSE', 'HONDA',
'HONEYWELL', 'HORSE', 'HOSPITAL', 'HOST', 'HOSTING', 'HOT', 'HOTELES', 'HOTMAIL', 'HOUSE', 'HOW', 'HR', 'HSBC',
'HT', 'HTC', 'HU', 'HUGHES', 'HYATT', 'HYUNDAI', 'IBM', 'ICBC', 'ICE', 'ICU', 'ID', 'IE',
'IEEE', 'IFM', 'IKANO', 'IL', 'IM', 'IMAMAT', 'IMDB', 'IMMO', 'IMMOBILIEN', 'IN', 'INDUSTRIES', 'INFINITI',
'INFO', 'ING', 'INK', 'INSTITUTE', 'INSURANCE', 'INSURE', 'INT', 'INTEL', 'INTERNATIONAL', 'INTUIT', 'INVESTMENTS', 'IO',
'IPIRANGA', 'IQ', 'IR', 'IRISH', 'IS', 'ISELECT', 'ISMAILI', 'IST', 'ISTANBUL', 'IT', 'ITAU', 'ITV',
'IVECO', 'IWC', 'JAGUAR', 'JAVA', 'JCB', 'JCP', 'JE', 'JEEP', 'JETZT', 'JEWELRY', 'JIO', 'JLC',
'JLL', 'JM', 'JMP', 'JNJ', 'JO', 'JOBS', 'JOBURG', 'JOT', 'JOY', 'JP', 'JPMORGAN', 'JPRS',
'JUEGOS', 'JUNIPER', 'KAUFEN', 'KDDI', 'KE', 'KERRYHOTELS', 'KERRYLOGISTICS', 'KERRYPROPERTIES', 'KFH', 'KG', 'KH', 'KI',
'KIA', 'KIM', 'KINDER', 'KINDLE', 'KITCHEN', 'KIWI', 'KM', 'KN', 'KOELN', 'KOMATSU', 'KOSHER', 'KP',
'KPMG', 'KPN', 'KR', 'KRD', 'KRED', 'KUOKGROUP', 'KW', 'KY', 'KYOTO', 'KZ', 'LA', 'LACAIXA',
'LADBROKES', 'LAMBORGHINI', 'LAMER', 'LANCASTER', 'LANCIA', 'LANCOME', 'LAND', 'LANDROVER', 'LANXESS', 'LASALLE', 'LAT', 'LATINO',
'LATROBE', 'LAW', 'LAWYER', 'LB', 'LC', 'LDS', 'LEASE', 'LECLERC', 'LEFRAK', 'LEGAL', 'LEGO', 'LEXUS',
'LGBT', 'LI', 'LIAISON', 'LIDL', 'LIFE', 'LIFEINSURANCE', 'LIFESTYLE', 'LIGHTING', 'LIKE', 'LILLY', 'LIMITED', 'LIMO',
'LINCOLN', 'LINDE', 'LINK', 'LIPSY', 'LIVE', 'LIVING', 'LIXIL', 'LK', 'LOAN', 'LOANS', 'LOCKER', 'LOCUS',
'LOFT', 'LOL', 'LONDON', 'LOTTE', 'LOTTO', 'LOVE', 'LPL', 'LPLFINANCIAL', 'LR', 'LS', 'LT', 'LTD',
'LTDA', 'LU', 'LUNDBECK', 'LUPIN', 'LUXE', 'LUXURY', 'LV', 'LY', 'MA', 'MACYS', 'MADRID', 'MAIF',
'MAISON', 'MAKEUP', 'MAN', 'MANAGEMENT', 'MANGO', 'MARKET', 'MARKETING', 'MARKETS', 'MARRIOTT', 'MARSHALLS', 'MASERATI', 'MATTEL',
'MBA', 'MC', 'MCD', 'MCDONALDS', 'MCKINSEY', 'MD', 'ME', 'MED', 'MEDIA', 'MEET', 'MELBOURNE', 'MEME',
'MEMORIAL', 'MEN', 'MENU', 'MEO', 'METLIFE', 'MG', 'MH', 'MIAMI', 'MICROSOFT', 'MIL', 'MINI', 'MINT',
'MIT', 'MITSUBISHI', 'MK', 'ML', 'MLB', 'MLS', 'MM', 'MMA', 'MN', 'MO', 'MOBI', 'MOBILE',
'MOBILY', 'MODA', 'MOE', 'MOI', 'MOM', 'MONASH', 'MONEY', 'MONSTER', 'MONTBLANC', 'MOPAR', 'MORMON', 'MORTGAGE',
'MOSCOW', 'MOTO', 'MOTORCYCLES', 'MOV', 'MOVIE', 'MOVISTAR', 'MP', 'MQ', 'MR', 'MS', 'MSD', 'MT',
'MTN', 'MTPC', 'MTR', 'MU', 'MUSEUM', 'MUTUAL', 'MV', 'MW', 'MX', 'MY', 'MZ', 'NA',
'NAB', 'NADEX', 'NAGOYA', 'NAME', 'NATIONWIDE', 'NATURA', 'NAVY', 'NBA', 'NC', 'NE', 'NEC', 'NETBANK',
'NETFLIX', 'NETWORK', 'NEUSTAR', 'NEW', 'NEWHOLLAND', 'NEWS', 'NEXT', 'NEXTDIRECT', 'NEXUS', 'NF', 'NFL', 'NG',
'NGO', 'NHK', 'NI', 'NICO', 'NIKE', 'NIKON', 'NINJA', 'NISSAN', 'NISSAY', 'NL', 'NO', 'NOKIA',
'NORTHWESTERNMUTUAL', 'NORTON', 'NOW', 'NOWRUZ', 'NOWTV', 'NP', 'NR', 'NRA', 'NRW', 'NTT', 'NU', 'NYC',
'NZ', 'OBI', 'OBSERVER', 'OFF', 'OFFICE', 'OKINAWA', 'OLAYAN', 'OLAYANGROUP', 'OLDNAVY', 'OLLO', 'OM', 'OMEGA',
'ONE', 'ONG', 'ONL', 'ONLINE', 'ONYOURSIDE', 'OOO', 'OPEN', 'ORACLE', 'ORANGE', 'ORGANIC', 'ORIENTEXPRESS', 'ORIGINS',
'OSAKA', 'OTSUKA', 'OTT', 'OVH', 'PA', 'PAGE', 'PAMPEREDCHEF', 'PANASONIC', 'PANERAI', 'PARIS', 'PARS', 'PARTNERS',
'PARTS', 'PARTY', 'PASSAGENS', 'PAY', 'PCCW', 'PE', 'PET', 'PF', 'PFIZER', 'PG', 'PH', 'PHARMACY',
'PHILIPS', 'PHONE', 'PHOTO', 'PHOTOGRAPHY', 'PHOTOS', 'PHYSIO', 'PIAGET', 'PICS', 'PICTET', 'PICTURES', 'PID', 'PIN',
'PING', 'PINK', 'PIONEER', 'PIZZA', 'PK', 'PL', 'PLACE', 'PLAY', 'PLAYSTATION', 'PLUMBING', 'PLUS', 'PM',
'PN', 'PNC', 'POHL', 'POKER', 'POLITIE', 'PORN', 'POST', 'PR', 'PRAMERICA', 'PRAXI', 'PRESS', 'PRIME',
'PRO', 'PROD', 'PRODUCTIONS', 'PROF', 'PROGRESSIVE', 'PROMO', 'PROPERTIES', 'PROPERTY', 'PROTECTION', 'PRU', 'PRUDENTIAL', 'PS',
'PT', 'PUB', 'PW', 'PWC', 'PY', 'QA', 'QPON', 'QUEBEC', 'QUEST', 'QVC', 'RACING', 'RADIO',
'RAID', 'RE', 'READ', 'REALESTATE', 'REALTOR', 'REALTY', 'RECIPES', 'RED', 'REDSTONE', 'REDUMBRELLA', 'REHAB', 'REISE',
'REISEN', 'REIT', 'RELIANCE', 'REN', 'RENT', 'RENTALS', 'REPAIR', 'REPORT', 'REPUBLICAN', 'REST', 'RESTAURANT', 'REVIEW',
'REVIEWS', 'REXROTH', 'RICH', 'RICHARDLI', 'RICOH', 'RIGHTATHOME', 'RIL', 'RIO', 'RIP', 'RMIT', 'RO', 'ROCHER',
'ROCKS', 'RODEO', 'ROGERS', 'ROOM', 'RS', 'RSVP', 'RU', 'RUHR', 'RUN', 'RW', 'RWE', 'RYUKYU',
'SA', 'SAARLAND', 'SAFE', 'SAFETY', 'SAKURA', 'SALE', 'SALON', 'SAMSCLUB', 'SAMSUNG', 'SANDVIK', 'SANDVIKCOROMANT', 'SANOFI',
'SAP', 'SAPO', 'SARL', 'SAS', 'SAVE', 'SAXO', 'SB', 'SBI', 'SBS', 'SC', 'SCA', 'SCB',
'SCHAEFFLER', 'SCHMIDT', 'SCHOLARSHIPS', 'SCHOOL', 'SCHULE', 'SCHWARZ', 'SCIENCE', 'SCJOHNSON', 'SCOR', 'SCOT', 'SD', 'SE',
'SEAT', 'SECURE', 'SECURITY', 'SEEK', 'SELECT', 'SENER', 'SERVICES', 'SES', 'SEVEN', 'SEW', 'SEX', 'SEXY',
'SFR', 'SG', 'SH', 'SHANGRILA', 'SHARP', 'SHAW', 'SHELL', 'SHIA', 'SHIKSHA', 'SHOES', 'SHOP', 'SHOPPING',
'SHOUJI', 'SHOW', 'SHOWTIME', 'SHRIRAM', 'SI', 'SILK', 'SINA', 'SINGLES', 'SITE', 'SJ', 'SK', 'SKI',
'SKIN', 'SKY', 'SKYPE', 'SL', 'SLING', 'SM', 'SMART', 'SMILE', 'SN', 'SNCF', 'SO', 'SOCCER',
'SOCIAL', 'SOFTBANK', 'SOFTWARE', 'SOHU', 'SOLAR', 'SOLUTIONS', 'SONG', 'SONY', 'SOY', 'SPACE', 'SPIEGEL', 'SPOT',
'SPREADBETTING', 'SR', 'SRL', 'SRT', 'ST', 'STADA', 'STAPLES', 'STAR', 'STARHUB', 'STATEBANK', 'STATEFARM', 'STATOIL',
'STC', 'STCGROUP', 'STOCKHOLM', 'STORAGE', 'STORE', 'STREAM', 'STUDIO', 'STUDY', 'STYLE', 'SU', 'SUCKS', 'SUPPLIES',
'SUPPLY', 'SUPPORT', 'SURF', 'SURGERY', 'SUZUKI', 'SV', 'SWATCH', 'SWIFTCOVER', 'SWISS', 'SX', 'SY', 'SYDNEY',
'SYMANTEC', 'SYSTEMS', 'SZ', 'TAB', 'TAIPEI', 'TALK', 'TAOBAO', 'TARGET', 'TATAMOTORS', 'TATAR', 'TATTOO', 'TAX',
'TAXI', 'TC', 'TCI', 'TD', 'TDK', 'TEAM', 'TECH', 'TECHNOLOGY', 'TEL', 'TELECITY', 'TELEFONICA', 'TEMASEK',
'TENNIS', 'TEVA', 'TF', 'TG', 'TH', 'THD', 'THEATER', 'THEATRE', 'TIAA', 'TICKETS', 'TIENDA', 'TIFFANY',
'TIPS', 'TIRES', 'TIROL', 'TJ', 'TJMAXX', 'TJX', 'TK', 'TKMAXX', 'TL', 'TM', 'TMALL', 'TN',
'TO', 'TODAY', 'TOKYO', 'TOOLS', 'TOP', 'TORAY', 'TOSHIBA', 'TOTAL', 'TOURS', 'TOWN', 'TOYOTA', 'TOYS',
'TR', 'TRADE', 'TRADING', 'TRAINING', 'TRAVEL', 'TRAVELCHANNEL', 'TRAVELERS', 'TRAVELERSINSURANCE', 'TRUST', 'TRV', 'TT', 'TUBE',
'TUI', 'TUNES', 'TUSHU', 'TV', 'TVS', 'TW', 'TZ', 'UA', 'UBANK', 'UBS', 'UCONNECT', 'UG',
'UK', 'UNICOM', 'UNIVERSITY', 'UNO', 'UOL', 'UPS', 'US', 'UY', 'UZ', 'VA', 'VACATIONS', 'VANA',
'VANGUARD', 'VC', 'VE', 'VEGAS', 'VENTURES', 'VERISIGN', 'VERSICHERUNG', 'VET', 'VG', 'VI', 'VIAJES', 'VIDEO',
'VIG', 'VIKING', 'VILLAS', 'VIN', 'VIP', 'VIRGIN', 'VISA', 'VISION', 'VISTA', 'VISTAPRINT', 'VIVA', 'VIVO',
'VLAANDEREN', 'VN', 'VODKA', 'VOLKSWAGEN', 'VOLVO', 'VOTE', 'VOTING', 'VOTO', 'VOYAGE', 'VU', 'VUELOS', 'WALES',
'WALMART', 'WALTER', 'WANG', 'WANGGOU', 'WARMAN', 'WATCH', 'WATCHES', 'WEATHER', 'WEATHERCHANNEL', 'WEBCAM', 'WEBER', 'WEBSITE',
'WED', 'WEDDING', 'WEIBO', 'WEIR', 'WF', 'WHOSWHO', 'WIEN', 'WIKI', 'WILLIAMHILL', 'WIN', 'WINDOWS', 'WINE',
'WINNERS', 'WME', 'WOLTERSKLUWER', 'WOODSIDE', 'WORK', 'WORKS', 'WORLD', 'WOW', 'WS', 'WTC', 'WTF', 'XBOX',
'XEROX', 'XFINITY', 'XIHUAN', 'XIN', 'XPERIA', 'XXX', 'XYZ', 'YACHTS', 'YAHOO', 'YAMAXUN', 'YANDEX', 'YE',
'YODOBASHI', 'YOGA', 'YOKOHAMA', 'YOU', 'YOUTUBE', 'YT', 'YUN', 'ZA', 'ZAPPOS', 'ZARA', 'ZERO', 'ZIP',
'ZIPPO', 'ZM', 'ZONE', 'ZUERICH', 'ZW'];
	
	if ($domain =~ /((^|\.)\-|\-(\.|$))/) { return; }
	if ($domain =~ /^[a-z0-9-]{1,63}\.([a-z]{2,})$/) {
		my $topLevel = $1;
		foreach my $top (@{$topLevelList}) {
			if (lc($top) eq $topLevel) { return TRUE; }
		}
	}
	return;
}

#=====================================================

=head2 B<isHostname>

LDH (letter-digit-hyphen), no hyphen at start or end of label, labels are from 1 to 63 characters, top-level is 2 or more letters or numbers.

=cut
#=====================================================
sub isHostname {
	my $hostname = shift || return;
	
	if ($hostname =~ /((^|\.)\-|\-(\.|$))/) { return; }
	if ($hostname =~ /^(?:[a-z0-9][a-z0-9-]{0,62}\.)*([a-z0-9][a-z0-9-]{0,62}\.[a-z]{2,})\.?$/) {
		return isDomain($1);
	}
	return;
}

#=====================================================

=head2 B<isEmail>

=cut
#=====================================================
sub isEmail {
	my $email = shift || return;
	
#	if ($email =~ /^[a-z0-9][a-z0-9\!\$\^\*\(\)_\-\+~`\\\[\]\{\}",\.]*\@(.+)$/) {
	# From http://www.regular-expressions.info/email.html
	if ($email =~ /^[a-z0-9!#$%&'*+\/=?^_`{|}~-]+(?:\.[a-z0-9!#$%&'*+\/=?^_`{|}~-]+)*\@(.+)$/i) {
		return isHostname($1);
	}
	return;
}

#=====================================================

=head2 B<isIPv4>

=cut
#=====================================================
sub isIPv4 {
	my $ipv4 = shift || return;
	if ($ipv4 =~ /^((25[0-5]|2[0-4]\d|[0-1]\d\d|\d\d?)\.){3}(25[0-5]|2[0-4]\d|[0-1]\d\d|\d\d?)$/) {
		return TRUE;
	}
}

#=====================================================

=head2 B<isIPv6>

=cut
#=====================================================
sub isIPv6 {
	my $ipv6 = shift || return;
	# ---
	# IPv6 Validator courtesy of Dartware, LLC (http://intermapper.com)
	# For full details see http://intermapper.com/ipv6validator
	# ---
	if ($ipv6 =~ /^\s*((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?\s*$/) {
		return TRUE;
	}
}

#=====================================================

=head2 B<getDomainName>

 my $domain = getDomainName($domain || $hostname || $emailAddress);

=cut
#=====================================================
sub getDomainName {
	my $address = shift || return;
	my ($domain) = $address =~ /([a-z0-9-]+\.[a-z0-9]+)$/;
	if (isDomain($domain)) { return $domain; }
	return;
}

#=====================================================

=head2 B<isStateCode>

=cut
#=====================================================
sub isStateCode {
	my $state = shift || return;
	my $code = getRegionCode($state, 'US');
	if (lc($state) eq lc($code)) { return TRUE; }
}

#=====================================================

=head2 B<getStateCode>

=cut
#=====================================================
sub getStateCode {
	my $string = shift || return;
	return getRegionCode($string, 'US');
}

#=====================================================

=head2 B<_getRegions>

  http://en.wikipedia.org/wiki/ISO_3166-2
  http://en.wikipedia.org/wiki/ISO_3166-2:US
  http://en.wikipedia.org/wiki/ISO_3166-2:GB
  http://en.wikipedia.org/wiki/Chapman_code

US States that don't conflict with other regions:
  AK, AZ, DE, DC, HI, ID, IL, IN, IA, KS, LA, ME, MI, NV, NJ, NM, NY, ND, OH, OK, SD, TN, TX, VT, WV, WI, WY, MP, UM
US States that do conflict with other regions:
  AL, AR, AS, CA, CO, CT, FL, GA, GU, KY, MA, MD, MN, MO, MS, MT, NC, NE, NH, OR, PA, PR, RI, SC, UT, VA, VI, WA

=cut
#=====================================================
sub _getRegions {
	return [ {
		cc		=> 'US',
		regions => {
			AL => ['alabama', 'ala'],
			AK => ['alaska', 'alas'],
			AZ => ['arizona', 'ariz'],
			AR => ['arkansas', 'ark'],
			CA => ['california', 'calif',  'cal',  'cali'],
			CO => ['colorado', 'colo',  'col'],
			CT => ['connecticut', 'conn'],
			DE => ['delaware', 'del'],
			DC => ['district-of-columbia', 'wash-dc'],
			FL => ['florida', 'fla',  'flor'],
			GA => ['georgia'],
			HI => ['hawaii'],
			ID => ['idaho', 'ida'],
			IL => ['illinois', 'ill',  'ills'],
			IN => ['indiana', 'ind'],
			IA => ['iowa'],
			KS => ['kansas', 'kans',  'kan',  'ka'],
			KY => ['kentucky', 'ken'],
			LA => ['louisiana'],
			ME => ['maine'],
			MD => ['maryland'],
			MA => ['massachusetts', 'mass'],
			MI => ['michigan', 'mich'],
			MN => ['minnesota', 'minn'],
			MS => ['mississippi', 'miss'],
			MO => ['missouri'],
			MT => ['montana', 'mont'],
			NE => ['nebraska', 'nebr',  'neb'],
			NV => ['nevada', 'nev'],
			NH => ['new-hampshire'],
			NJ => ['new-jersey'],
			NM => ['new-mexico', 'n-mex',  'new-m'],
			NY => ['new-york', 'n-york'],
			NC => ['north-carolina', 'n-car'],
			ND => ['north-dakota', 'n-dak',  'nodak'],
			OH => ['ohio', 'o'],
			OK => ['oklahoma', 'okla'],
			OR => ['oregon', 'oreg',  'ore'],
			PA => ['pennsylvania', 'penn',  'penna'],
			RI => ['rhode-island', 'ri-pp',  'r-isl'],
			SC => ['south-carolina', 's-car'],
			SD => ['south-dakota', 's-dak',  'sodak'],
			TN => ['tennessee', 'tenn'],
			TX => ['texas', 'tex'],
			UT => ['utah'],
			VT => ['vermont'],
			VA => ['virginia', 'virg'],
			WA => ['washington', 'wash',  'wn'],
			WV => ['west-virginia', 'w-va',  'wva',  'w-virg'],
			WI => ['wisconsin', 'wis',  'wisc'],
			WY => ['wyoming', 'wyo'],
			AS => ['american-samoa'],
			GU => ['guam'],
			MP => ['northern-mariana-islands'],
			PR => ['puerto-rico'],
			VI => ['virgin-islands', 'usvi'],
			UM => ['us-minor-outlying-islands']
		}
	}, {
		cc		=> 'CA',
		regions	=> {
			AB => ['alberta', 'alta', 'alb'],
			BC => ['british-columbia', 'colombie-britannique', 'b-c', 'c-b'],
			MB => ['manitoba', 'man'],
			NB => ['new-brunswick', 'nouveau-brunswick'],
			NL => ['newfoundland-and-labrador', 'newfoundland', 'labrador', 'terre-neuve-et-labrador', 'lb', 'nfld', 'nf', 't-n'],
			NS => ['nova-scotia', 'nouvelle-ecosse', 'n-e'],
			NT => ['northwest-territories', 'territoires-du-nord-ouest', 'nwt', 'tno'],
			NU => ['nunavut', 'nvt'],
			ON => ['ontario', 'ont'],
			PE => ['prince-edward-island', 'ile-du-prince-edouard', 'pei', 'ipe'],
			QC => ['quebec', 'que', 'pq', 'qu', 'qb'],
			SK => ['saskatchewan', 'sask'],
			YT => ['yukon', 'yuk', 'yk']
		}
	}, {
		cc		=> 'GB',
		regions	=> {
			# Two-tier counties
			BKM => ['buckinghamshire', 'bux'],
			CAM => ['cambridgeshire', 'cbe'],
			CMA => ['cumbria', 'cba'],
			DBY => ['derbyshire', 'dys'],
			DEV => ['devon', 'devonshire', 'dvn'],
			DOR => ['dorset', 'dorse'],
			ESX => ['east-sussex', 'sxe'],
			ESS => ['essex'],
			GLS => ['gloucestershire', 'gloucester', 'glr'],
			HAM => ['hampshire', 'hph'],
			HRT => ['hertfordshire', 'hfd'],
			KEN => ['kent', 'knt'],
			LAN => ['lancashire', 'lnh'],
			LEC => ['leicestershire', 'lei'],
			LIN => ['lincolnshire', 'lcn'],
			NFK => ['norfolk', 'nor'],
			NYK => ['north-yorkshire', 'ysn'],
			NTH => ['northamptonshire', 'nhm'],
			NTT => ['nottinghamshire', 'nottingham', 'ngm', 'not'],
			OXF => ['oxfordshire', 'ofe'],
			SOM => ['somerset'],
			STS => ['staffordshire', 'sfd'],
			SFK => ['suffolk'],
			SRY => ['surrey'],
			WAR => ['warwickshire', 'wks'],
			WSX => ['west-sussex', 'sxw'],
			WOR => ['worcestershire'],
			
			# London boroughs
			LND => ['london', 'greater-london', 'ldn'],
			BDG => ['barking-and-dagenham', 'barking', 'dagenham'],
			BNE => ['barnet'],
			BEX => ['bexley'],
			BEN => ['brent'],
			BRY => ['bromley'],
			CMD => ['camden'],
			CRY => ['croydon'],
			EAL => ['ealing'],
			ENF => ['enfield'],
			GRE => ['greenwich'],
			HCK => ['hackney'],
			HMF => ['hammersmith-and-fulham', 'hammersmith', 'fulham'],
			HRY => ['haringey'],
			HRW => ['harrow'],
			HAV => ['havering'],
			HIL => ['hillingdon'],
			HNS => ['hounslow'],
			ISL => ['islington'],
			KEC => ['kensington-and-chelsea', 'kensington', 'chelsea'],
			KTT => ['kingston-upon-thames'],
			LBH => ['lambeth'],
			LEW => ['lewisham'],
			MRT => ['merton'],
			NWM => ['newham'],
			RDB => ['redbridge'],
			RIC => ['richmond-upon-thames'],
			SWK => ['southwark'],
			STN => ['sutton'],
			TWH => ['tower-hamlets'],
			WFT => ['waltham-forest'],
			WND => ['wandsworth'],
			WSM => ['westminster'],
			
			# Metropolitan districts
			BNS => ['barnsley'],
			BIR => ['birmingham'],
			BOL => ['bolton'],
			BRD => ['bradford'],
			BUR => ['bury'],
			CLD => ['calderdale'],
			COV => ['coventry'],
			DNC => ['doncaster'],
			DUD => ['dudley'],
			GAT => ['gateshead'],
			KIR => ['kirklees'],
			KWL => ['knowsley'],
			LDS => ['leeds'],
			LIV => ['liverpool'],
			MAN => ['manchester', 'greater-manchester', 'gtm', 'greater-manchester', 'mch', 'west-manchester'],
			NET => ['newcastle-upon-tyne'],
			NTY => ['north-tyneside'],
			OLD => ['oldham'],
			RCH => ['rochdale'],
			ROT => ['rotherham'],
			SHN => ['st-helens'],
			SLF => ['salford'],
			SAW => ['sandwell'],
			SFT => ['sefton'],
			SHF => ['sheffield'],
			SOL => ['solihull'],
			STY => ['south-tyneside'],
			SKP => ['stockport'],
			SND => ['sunderland'],
			TAM => ['tameside'],
			TRF => ['trafford'],
			WKF => ['wakefield'],
			WLL => ['walsall'],
			WGN => ['wigan'],
			WRL => ['wirral'],
			WLV => ['wolverhampton'],
			
			# Unitary authorities
			BAS => ['bath-and-north-east-somerset', 'bath-and-northeast-somerset', 'bath', 'north-east-somerset', 'northeast-somerset'],
			BBD => ['blackburn-with-darwen'],
			BDF => ['bedford', 'bedfordshire', 'bfd'],
			BPL => ['blackpool'],
			BMH => ['bournemouth'],
			BRC => ['bracknell-forest'],
			BNH => ['brighton-and-hove', 'brighton', 'hove'],
			BST => ['bristol', 'city-of-bristol'],
			CBF => ['central-bedfordshire'],
			CHE => ['cheshire-east'],
			CHW => ['cheshire-west-and-chester', 'cheshire-west', 'chester'],
			CON => ['cornwall', 'cnl'],
			DAL => ['darlington'],
			DER	=> ['derby'],
			DUR => ['durham-county', 'durham', 'county-durham', 'dhm'],
			ERY => ['east-riding-of-yorkshire', 'yorkshire-east-riding'],
			HAL => ['halton'],
			HPL => ['hartlepool'],
			HEF => ['herefordshire'],
			IOW => ['isle-of-wight'],
			KHL => ['kingston-upon-hull'],
			LCE	=> ['leicester'],
			LUT => ['luton'],
			MDW => ['medway'],
			MDB => ['middlesbrough'],
			MIK => ['milton-keynes'],
			NEL => ['north-east-lincolnshire', 'northeast-lincolnshire'],
			NLN => ['north-lincolnshire'],
			NSM => ['north-somerset'],
			NBL => ['northumberland', 'nld'],
			PTE => ['peterborough'],
			PLY => ['plymouth'],
			POL => ['poole'],
			POR => ['portsmouth'],
			RDG => ['reading'],
			RCC => ['redcar-and-cleveland', 'redcar', 'cleveland', 'clv', 'cve'],
			RUT => ['rutland'],
			SHR => ['shropshire', 'sal', 'spe'],
			SLG => ['slough'],
			SGC => ['south-gloucestershire'],
			STH => ['southampton'],
			SOS => ['southend-on-sea'],
			STT => ['stockton-on-tees'],
			STE => ['stoke-on-trent'],
			SWD => ['swindon'],
			TFW => ['telford-and-wrekin', 'telford', 'wrekin'],
			THR => ['thurrock'],
			TOB => ['torbay'],
			WRT => ['warrington'],
			WBK => ['west-berkshire'],
			WIL => ['wiltshire', 'wlt'],
			WNM => ['windsor-and-maidenhead', 'windsor', 'maidenhead'],
			WOK => ['wokingham'],
			YOR => ['york'],
			
			# Historic counties
			BRK => ['berkshire'],
			CHS => ['cheshire'],
			CUL => ['cumberland'],
			HUN => ['huntingdonshire'],
			MDX => ['middlesex'],
			SSX => ['sussex'],
			WES => ['westmorland'],
			YKS => ['yorkshire'],
			NRY => ['yorkshire-north-riding'],
			WRY => ['yorkshire-west-riding'],
			AVN => ['avon'],
			HWR => ['hereford-and-worcester'],
			HUM => ['humberside', 'hbs'],
			MSY => ['merseyside'],
			WMD => ['west-midlands', 'sal'],
			SYK => ['south-yorkshire', 'yss'],
			TWR => ['tyne-and-wear'],
			WYK => ['west-yorkshire', 'ysw'],
			IOS	=> ['isles-of-scilly'],
			
			# Scotland
			ABE => ['aberdeen-city'],
			ABD => ['aberdeenshire'],
			ANS => ['angus', 'forfarshire'],
			AGB => ['argyll-and-bute', 'argyll', 'argyllshire', 'arl', 'bute', 'buteshire', 'but'],
			CLK => ['clackmannanshire'],
			DGY => ['dumfries-and-galloway', 'dumfries', 'galloway', 'dumfriesshire', 'dfs', 'dgl'],
			DND => ['dundee-city'],
			EAY => ['east-ayrshire'],
			EDU => ['east-dunbartonshire'],
			ELN => ['east-lothian', 'haddingtonshire'],
			ERW => ['east-renfrewshire'],
			EDH => ['edinburgh', 'city-of-edinburgh'],
			ELS => ['eilean-siar'],
			FAL => ['falkirk'],
			FIF => ['fife', 'ffe'],
			GLG => ['glasgow-city'],
			HLD => ['highland', 'highlands'],
			IVC => ['inverclyde'],
			MLN => ['midlothian', 'edinburghshire'],
			MRY => ['moray', 'elginshire'],
			NAY => ['north-ayrshire'],
			NLK => ['north-lanarkshire'],
			ORK => ['orkney-islands', 'orkney-isles', 'orkney', 'oki'],
			PKN => ['perth-and-kinross', 'perth', 'perthshire', 'per', 'kinross', 'kinross-shire', 'krs'],
			RFW => ['renfrewshire'],
			SCB => ['scottish-borders', 'bor', 'bds'],
			ZET => ['shetland-islands', 'shetland-isles', 'shetland', 'shi', 'sld'],
			SAY => ['south-ayrshire'],
			SLK => ['south-lanarkshire'],
			STG => ['stirling', 'stirlingshire', 'sti'],
			WDU => ['west-dunbartonshire'],
			WLN => ['west-lothian', 'linlithgowshire'],
			# Historic counties
			AYR => ['ayrshire'],
			BAN => ['banffshire'],
			BEW => ['berwickshire'],
			CAI => ['caithness'],
			CEN => ['central', 'ctr'],
			DNB => ['dunbartonshire'],
			GMP => ['grampian', 'grn'],
			INV => ['inverness-shire'],
			KCD => ['kincardineshire'],
			KKD => ['kirkcudbrightshire'],
			LKS => ['lanarkshire'],
			LTH	=> ['lothian', 'ltn'],
			NAI => ['nairnshire'],
			PEE => ['peeblesshire'],
			ROC => ['ross-and-cromarty'],
			ROX => ['roxburghshire'],
			SEL => ['selkirkshire'],
			STD => ['strathclyde', 'scd'],
			SUT => ['sutherland'],
			TAY => ['tayside', 'tys'],
			WIG => ['wigtownshire'],
			WIS => ['western-isles', 'wil'],
			
			# Wales
			BGW => ['blaenau-gwent'],
			BGE => ['bridgend', 'pen-y-bont-ar-ogwr', 'pog'],
			CAY => ['caerphilly', 'caerffili', 'caf'],
			CRF => ['cardiff', 'caerdydd', 'crd'],
			CMN => ['carmarthenshire', 'sir-gaerfyrddin', 'gfy'],
			CGN => ['ceredigion', 'sir-ceredigion'],
			CWY => ['conwy'],
			DEN => ['denbighshire', 'sir-ddinbych', 'ddb'],
			FLN => ['flintshire', 'sir-y-fflint', 'ffl'],
			GWN => ['gwynedd', 'gdd'],
			AGY => ['isle-of-anglesey', 'anglesey', 'sir-ynys-mon', 'sir-yny-mon', 'ynm'],
			MTY => ['merthyr-tydfil', 'merthyr-tudful', 'mtu'],
			MON => ['monmouthshire', 'sir-fynwy', 'fyn'],
			NTL => ['neath-port-talbot', 'castell-nedd-port-talbot', 'ctl'],
			NWP => ['newport', 'cnw', 'casnewydd'],
			PEM => ['pembrokeshire', 'sir-benfro', 'bnf'],
			POW => ['powys', 'pws'],
			RCT => ['rhondda', 'cynon', 'taff', 'taf'],
			SWA => ['swansea', 'abertawe', 'ata'],
			TOF => ['torfaen', 'tor-faen'],
			VGL => ['vale-of-glamorgan', 'bro-morgannwg', 'bmg'],
			WRX => ['wrexham', 'wrecsam', 'wrc'],
			# Historic counties
			BRE	=> ['brecknockshire'],
			CAE	=> ['caernarfonshire'],
			CGN	=> ['cardiganshire'],
			CLD	=> ['clwyd'],
			DFD	=> ['dyfed'],
			GLA	=> ['glamorgan'],
			GNM	=> ['mid-glamorgan', 'mgm'],
			GNS	=> ['south-glamorgan', 'sgm'],
			GNW	=> ['west-glamorgan', 'wgm'],
			GWT	=> ['gwent', 'gnt'],
			MER	=> ['merionethshire'],
			MGY	=> ['montgomeryshire'],
			RAD	=> ['radnorshire'],
			
			# Northern ireland
			ANT => ['antrim', 'county-antrim', 'atm'],
			ARD => ['ards'],
			ARM => ['armagh', 'county-armagh'],
			BLA => ['ballymena'],
			BLY => ['ballymoney'],
			BNB => ['banbridge'],
			BFS => ['belfast'],
			CKF => ['carrickfergus'],
			CSR => ['castlereagh'],
			CLR => ['coleraine'],
			CKT => ['cookstown'],
			CGV => ['craigavon'],
			DRY => ['derry', 'county-londonderry', 'ldr'],
			DOW => ['down', 'county-down', 'dwn'],
			DGN => ['dungannon-and-south-tyrone', 'dungannon', 'south-tyrone'],
			FER => ['fermanagh', 'county-fermanagh', 'fmh'],
			LRN => ['larne'],
			LMV => ['limavady'],
			LSB => ['lisburn'],
			MFT => ['magherafelt'],
			MYL => ['moyle'],
			NYM => ['newry-and-mourne-district', 'newry', 'mourne-district'],
			NTA => ['newtownabbey'],
			NDN => ['north-down'],
			OMH => ['omagh'],
			STB => ['strabane'],
			# Historic counties
			LEX	=> ['leix', 'queens'],
			TYR	=> ['tyrone', 'county-tyrone']
		}
	}, {
		cc		=> 'IE',
		notes	=> [
			'C on vehicles refers to Cork instead of Connacht',
			'L on vehicles refers to Limerick instead of Leinster',
		],
		regions	=> {
			# Provinces
			C	=> ['connaught', 'connacht'],
			L	=> ['leinster', 'laighin'],
			M	=> ['munster', 'an-mhumhain'],
			U	=> ['ulster', 'ulaidh'],
			# Counties
			CW	=> ['carlow', 'ceatharlach', 'car'],
			CN	=> ['cavan', 'an-cabhan', 'cav'],
			CE	=> ['clare', 'an-clar', 'cla'],
			CO	=> ['cork', 'corcaigh', 'cor'],
			DL	=> ['donegal', 'dun-na-ngall', 'don'],
			D	=> ['dublin', 'baile-atha-cliath', 'dub'],
			G	=> ['galway', 'gaillimh', 'gal'],
			KY	=> ['kerry', 'ciarrai', 'ker'],
			KE	=> ['kildare', 'cill-dara', 'kid'],
			KK	=> ['kilkenny', 'cill-chainnigh', 'kik'],
			LS	=> ['laois'],
			LM	=> ['leitrim', 'liatroim', 'let'],
			LK	=> ['limerick', 'luimneach', 'lim'],
			LD	=> ['longford', 'an-longfort', 'log'],
			LH	=> ['louth', 'lu', 'lou'],
			MO	=> ['mayo', 'maigh-eo', 'may'],
			MH	=> ['meath', 'an-mhi', 'mra'],
			MN	=> ['monaghan', 'muineachan', 'mog'],
			OY	=> ['offaly', 'uibh-fhaili', 'off'],
			RN	=> ['roscommon', 'ros-comain', 'ros'],
			SO	=> ['sligo', 'sligeach', 'sli'],
			TA	=> ['tipperary', 'tiobraid-arann', 'tip', 'tn', 'ts', 't'],
			WD	=> ['waterford', 'port-lairge', 'wat', 'w'],
			WH	=> ['westmeath', 'an-iarmhi', 'wem'],
			WX	=> ['wexford', 'loch-garman', 'wex'],
			WW	=> ['wicklow', 'cill-mhantain', 'wik']
		}
	}, {
		cc		=> 'BE',
		regions	=> {
			BRU	=> ['bruxelles-capitale', 'region-de-bruxelles-capitale', 'brussels-hoofdstedelijk-gewest'],
			VLG	=> ['vlaamse-gewest'],
			WAL	=> ['wallonne', 'region-wallonne'],
			VAN	=> ['antwerpen'],
			WBR	=> ['brabant-wallon'],
			WHT	=> ['hainaut'],
			WLG	=> ['liege'],
			VLI	=> ['limburg'],
			WLX	=> ['luxembourg'],
			WNA	=> ['namur'],
			VOV	=> ['oost-vlaanderen'],
			VBR	=> ['vlaams-brabant'],
			VWV	=> ['west-vlaanderen']
		}
	}, {
		cc		=> 'SE',
		regions	=> {
			BLE => ['blekinge-lan', 'karlskrona', 'karlshamn', 'ronneby'],
			DAL => ['dalarnas-lan', 'falun', 'avesta', 'borlange', 'ludvika', 'mora'],
			GAV => ['gavleborgs-lan', 'gavle', 'bollnas', 'hudiksvall', 'ljusdal', 'sandviken', 'soderhamn'],
			GOT => ['gotlands-lan', 'visby', 'gotlands-kommun'],
			HAL => ['hallands-lan', 'halmstad', 'falkenberg', 'kungsbacka', 'laholm', 'varberg'],
			JAM => ['jamtlands-lan', 'ostersund'],
			JON => ['jonkopings-lan', 'jonkoping', 'gislaved', 'nassjo', 'varnamo', 'vetlanda'],
			KAL => ['kalmar-lan', 'kalmar', 'nybro', 'oskarshamn', 'vastervik'],
			KRO => ['kronobergs-lan', 'vaxjo', 'ljungby'],
			NOR => ['norrbottens-lan', 'lulea', 'boden', 'gallivare', 'kiruna', 'pitea'],
			ORE => ['orebro-lan', 'orebro', 'karlskoga', 'kumla', 'lindesberg'],
			OST => ['ostergotlands-lan', 'linkoping', 'finspang', 'mjolby', 'motala', 'norrkoping'],
			SKA => ['skane-lan', 'malmo', 'angelholm', 'eslov', 'hassleholm', 'helsingborg', 'hoganas', 'kavlinge', 'kristianstad', 'landskrona', 'lomma', 'lund', 'simrishamn', 'staffanstorp', 'svedala', 'trelleborg', 'vellinge', 'ystad'],
			SOD => ['sodermanlands-lan', 'nykoping', 'eskilstuna', 'katrineholm', 'strangnas'],
			STO => ['stockholms-lan', 'stockholm', 'akersberga', 'osteraker-kommun', 'botkyrka', 'danderyd', 'ekero', 'gustavsberg', 'varmdo-kommun', 'haninge', 'huddinge', 'jarfalla', 'lidingo', 'nacka', 'norrtalje', 'nynashamn', 'sigtuna', 'sodertalje', 'sollentuna', 'solna', 'sundbyberg', 'taby', 'tyreso', 'upplands-bro', 'upplands-vasby', 'vallentuna'],
			UPP => ['uppsala-lan', 'uppsala', 'enkoping', 'habo', 'osthammar', 'tierp'],
			VAR => ['varmlands-lan', 'karlstad', 'arvika', 'kristinehamn'],
			VAS => ['vasterbottens-lan', 'umea', 'skelleftea'],
			VGO => ['vastra-gotalands-lan', 'goteborg', 'alingsas', 'boras', 'falkoping', 'gothenburg', 'kinna', 'mark-kommun', 'kungalv', 'lerum', 'lidkoping', 'mariestad', 'molndal', 'molnlycke', 'harryda-kommun', 'nodinge-nol', 'ale-kommun', 'partille', 'skovde', 'stenungsund', 'trollhattan', 'uddevalla', 'ulricehamn', 'vanersborg'],
			VML => ['vastmanlands-lan', 'vasteras', 'koping', 'sala'],
			VNL => ['vasternorrlands-lan', 'harnosand', 'kramfors', 'ornskoldsvik', 'solleftea', 'sundsvall'],
			
# 			K	=> ['blekinge', 'blekinge-lan'],
# 			W	=> ['dalarnas', 'dalarnas-lan'],
# 			I	=> ['gotlands', 'gotlands-lan'],
# 			X	=> ['gavleborgs', 'gavleborgs-lan'],
# 			N	=> ['hallands', 'hallands-lan'],
# 			Z	=> ['jamtlands', 'jamtlands-lan'],
# 			F	=> ['jonkopings', 'jonkopings-lan'],
# 			H	=> ['kalmar', 'kalmar-lan'],
# 			G	=> ['kronobergs', 'kronobergs-lan'],
# 			BD	=> ['norrbottens', 'norrbottens-lan'],
# 			M	=> ['skane', 'skane-lan'],
# 			AB	=> ['stockholms', 'stockholms-lan', 'stockholm', 'sto'],
# 			D	=> ['sodermanlands', 'sodermanlands-lan'],
# 			C	=> ['uppsala', 'uppsala-lan'],
# 			S	=> ['varmlands', 'varmlands-lan'],
# 			AC	=> ['vasterbottens', 'vasterbottens-lan'],
# 			Y	=> ['vasternorrlands', 'vasternorrlands-lan'],
# 			U	=> ['vastmanlands', 'vastmanlands-lan'],
# 			O	=> ['vastra-gotalands', 'vastra-gotalands-lan', 'vgi'],
# 			T	=> ['orebro', 'orebro-lan'],
# 			E	=> ['ostergotlands', 'ostergotlands-lan'],
		}
	}, {
		cc		=> 'AU',
		regions	=> {
			ACT	=> ['australian-capital-territory', 'canberra'],
			CHR	=> ['christmas-island', 'the-settlement'],
			COC	=> ['cocos-islands', 'west-island'],
			NSW	=> ['albury', 'armidale', 'ballina', 'batemans-bay', 'bathurst', 'bowral-mittagong', 'broken-hill', 'camden-haven', 'central-coast', 'gosford', 'cessnock', 'coffs-harbour', 'sawtell', 'dubbo', 'forster-tuncurry', 'goulburn', 'grafton', 'griffith', 'kurri-kurri-weston', 'lismore', 'lithgow', 'morisset-cooranbong', 'muswellbrook', 'nelson-bay-corlette', 'newcastle', 'nowra-bomaderry', 'orange', 'parkes', 'port-macquarie', 'singleton', 'st-georges-basin-sanctuary-point', 'sydney', 'tamworth', 'taree', 'ulladulla', 'wagga-wagga', 'wollongong', 'queanbeyan', 'moama', 'tweed-heads', 'buronga'],
			NT	=> ['northern-territory', 'darwin', 'alice-springs'],
			QLD	=> ['brisbane', 'bundaberg', 'cairns', 'northern-beaches', 'emerald', 'gladstone', 'gold-coast', 'southport', 'gympie', 'hervey-bay', 'highfields', 'mackay', 'maryborough', 'mount-isa', 'rockhampton', 'sunshine-coast', 'caloundra-buderim-noosa', 'toowoomba', 'townsville', 'thuringowa', 'warwick', 'yeppoon'],
			SA	=> ['adelaide', 'mount-gambier', 'murray-bridge', 'port-augusta', 'port-lincoln', 'port-pirie', 'victor-harbor-goolwa', 'whyalla'],
			TAS	=> ['burnie', 'devonport', 'hobart', 'launceston', 'ulverstone'],
			VIC	=> ['bacchus-marsh', 'bairnsdale', 'ballarat', 'bendigo', 'colac', 'drysdale-clifton-springs', 'echuca', 'geelong', 'gisborne-macedon', 'horsham', 'melbourne', 'melton', 'mildura', 'moe-newborough', 'ocean-grove', 'sale', 'shepparton-mooroopna', 'torquay', 'jan-juc', 'traralgon', 'wangaratta', 'warragul', 'warrnambool', 'wodonga'],
			WA	=> ['wau', 'albany', 'broome', 'bunbury', 'busselton', 'ellenbrook', 'geraldton', 'kalgoorlie-boulder', 'karratha', 'perth', 'port-hedland'],
			
# 			NSW	=> ['new-south-wales'],
# 			QLD	=> ['queensland'],
# 			SA	=> ['south-australia'],
# 			TAS	=> ['tasmania'],
# 			VIC	=> ['victoria'],
# 			WA	=> ['western-australia', 'wau'],
# 			ACT	=> ['australian-capital'],
# 			NT	=> ['northern-territory']
		}
	}, {
		cc		=> 'ES',
		regions	=> {
			AND => ['andalucia', 'andalusia', 'sevilla', 'algeciras', 'almeria', 'cadiz', 'cordoba', 'dos-hermanas', 'el-puerto-de-santa-maria', 'granada', 'huelva', 'jaen', 'jerez-de-la-frontera', 'malaga', 'marbella', 'roquetas-de-mar', 'san-fernando'],
			ARA => ['aragon', 'zaragoza'],
			AST => ['asturias', 'oviedo', 'gijon'],
			BAL => ['illes-balears', 'islas-baleares', 'balearic-islands', 'palma-de-mallorca'],
			CAN => ['canarias', 'canary-islands', 'santa-cruz-de-tenerife', 'la-laguna', 'san-cristobal-de-la-laguna', 'las-palmas-de-gran-canaria', 'telde'],
			CAR => ['cantabria', 'santander'],
			CAT => ['cataluna', 'catalonia', 'barcelona', 'badalona', 'cornella-de-llobregat', 'girona', 'gerona', 'lhospitalet-de-llobregat', 'lleida', 'lerida', 'mataro', 'reus', 'sabadell', 'santa-coloma-de-gramanet', 'sant-cugat-del-valles', 'tarragona', 'terrassa', 'tarrasa'],
			CEU => ['ceuta'],
			CLE => ['castilla-y-leon', 'valladolid', 'burgos', 'leon', 'salamanca'],
			CLM => ['castilla-la-mancha', 'toledo', 'albacete', 'talavera-de-la-reina'],
			EXT => ['extremadura', 'merida', 'badajoz', 'caceres'],
			GAL => ['galicia', 'santiago-de-compostela', 'a-coruna', 'la-coruna', 'lugo', 'ourense', 'orense', 'vigo'],
			LAR => ['la-rioja', 'logrono'],
			MAD => ['madrid', 'alcala-de-henares', 'alcobendas', 'alcorcon', 'coslada', 'fuenlabrada', 'getafe', 'las-rozas-de-madrid', 'leganes', 'mostoles', 'parla', 'torrejon-de-ardoz'],
			MEL => ['melilla'],
			MUR => ['murcia', 'cartagena', 'lorca'],
			NAV => ['navarra', 'navarre', 'pamplona', 'iruna'],
			PAI => ['pais-vasco', 'euskal-herriko', 'basque-country', 'vitoria-gasteiz', 'barakaldo', 'san-vicente-de-baracaldo', 'bilbao', 'donostia-san-sebastian'],
			VAL => ['comunitat-valenciana', 'comunidad-valenciana', 'valencia', 'alicante', 'alacant', 'castellon-de-la-plana', 'castello-de-la-plana', 'elche', 'elx', 'torrevieja'],
			
# 			AN	=> ['andalucia', 'and'],
# 			AR	=> ['aragon'],
# 			AS	=> ['asturias', 'principado-de-asturias'],
# 			CN	=> ['canarias'],
# 			CB	=> ['cantabria'],
# 			CM	=> ['castilla-la-mancha'],
# 			CL	=> ['castilla-y-leon', 'cle'],
# 			CT	=> ['catalunya', 'catalonia', 'catalonha', 'cataluna', 'cat'],
# 			EX	=> ['extremadura'],
# 			GA	=> ['galicia', 'gal'],
# 			IB	=> ['illes-balears', 'islas-baleares'],
# 			RI	=> ['la-rioja'],
# 			MD	=> ['madrid', 'comunidad-de-madrid', 'mad'],
# 			MC	=> ['murcia', 'region-de-murcia'],
# 			NC	=> ['navarra', 'comunidad-foral-de-navarra', 'nav'],
# 			PV	=> ['pais-vasco-euskadi'],
# 			VC	=> ['valenciana', 'comunidad-valenciana', 'comunitat-valenciana'],
# 			CE	=> ['ceuta'],
# 			ML	=> ['melilla'],
# 			C	=> ['a-coruna', 'la-coruna'],
# 			VI	=> ['alava', 'araba'],
# 			AB	=> ['albacete'],
# 			A	=> ['alicante', 'alacant'],
# 			AL	=> ['almeria'],
# 			O	=> ['asturias'],
# 			AV	=> ['avila'],
# 			BA	=> ['badajoz'],
# 			PM	=> ['balears', 'baleares'],
# 			B	=> ['barcelona'],
# 			BU	=> ['burgos'],
# 			CC	=> ['caceres'],
# 			CA	=> ['cadiz'],
# 			S	=> ['cantabria'],
# 			CS	=> ['castellon', 'castello'],
# 			CR	=> ['ciudad real'],
# 			CO	=> ['cordoba'],
# 			CU	=> ['cuenca'],
# 			GI	=> ['girona', 'gerona'],
# 			GR	=> ['granada'],
# 			GU	=> ['guadalajara'],
# 			SS	=> ['guipuzcoa', 'gipuzkoa'],
# 			H	=> ['huelva'],
# 			HU	=> ['huesca'],
# 			J	=> ['jaen'],
# 			LO	=> ['la rioja'],
# 			GC	=> ['las palmas'],
# 			LE	=> ['leon'],
# 			L	=> ['lleida', 'lerida'],
# 			LU	=> ['lugo'],
# 			M	=> ['madrid'],
# 			MA	=> ['malaga'],
# 			MU	=> ['murcia'],
# 			NA	=> ['navarra', 'nafarroa'],
# 			OR	=> ['ourense', 'orense'],
# 			P	=> ['palencia'],
# 			PO	=> ['pontevedra', 'pontevedra'],
# 			SA	=> ['salamanca'],
# 			TF	=> ['santa cruz de tenerife'],
# 			SG	=> ['segovia'],
# 			SE	=> ['sevilla'],
# 			SO	=> ['soria'],
# 			T	=> ['tarragona', 'tarragona'],
# 			TE	=> ['teruel'],
# 			TO	=> ['toledo'],
# 			V	=> ['valencia', 'valencia', 'val'],
# 			VA	=> ['valladolid'],
# 			BI	=> ['vizcaya', 'bizkaia'],
# 			ZA	=> ['zamora'],
# 			Z	=> ['zaragoza']
		}
	}, {
		cc		=> 'IT',
		regions	=> {
			ABR => [65, 'abruzzo', 'laquila', 'chieti', 'montesilvano', 'pescara', 'teramo'],
			BAS => [77, 'basilicata', 'potenza', 'matera'],
			CAL => [78, 'calabria', 'catanzaro', 'cosenza', 'crotone', 'lamezia-terme', 'nicastro', 'reggio-di-calabria', 'reggio-calabria', 'vibo-valentia'],
			CAM => [72, 'campania', 'napoli', 'acerra', 'afragola', 'avellino', 'aversa', 'battipaglia', 'benevento', 'casalnuovo-di-napoli', 'caserta', 'casoria', 'castellammare-di-stabia', 'cava-de-tirreni', 'ercolano', 'resina', 'giugliano-in-campania', 'marano-di-napoli', 'naples', 'portici', 'pozzuoli', 'salerno', 'scafati', 'torre-del-greco'],
			EMI => ['emilia-romagna', 'bologna', 'carpi', 'cesena', 'faenza', 'ferrara', 'forli', 'imola', 'modena', 'parma', 'piacenza', 'ravenna', 'reggio-nellemilia', 'rimini', 'forli-cesena', 'reggio-emilia'],
			FRI => [36, 'friuli-venezia-giulia', 'trieste', 'pordenone', 'udine', 'gorizia'],
			LAZ => ['lazio', 'latium', 'roma', 'anzio', 'aprilia', 'civitavecchia', 'fiumicino', 'guidonia-montecelio', 'latina', 'pomezia', 'rome', 'tivoli', 'velletri', 'viterbo', 'frosinone', 'rieti'],
			LIG => [42, 'liguria', 'genova', 'genoa', 'la-spezia', 'sanremo', 'san-remo', 'savona', 'imperia'],
			LOM => ['lombardia', 'lombardy', 'milano', 'bergamo', 'brescia', 'busto-arsizio', 'cinisello-balsamo', 'como', 'cremona', 'gallarate', 'legnano', 'milan', 'monza', 'pavia', 'rho', 'sesto-san-giovanni', 'varese', 'vigevano', 'lecco', 'lodi', 'mantua', 'monza-and-brianza', 'sondrio'],
			MAR => [57, 'marche', 'ancona', 'ascoli-piceno', 'fano', 'pesaro', 'fermo', 'macerata', 'pesaro-and-urbino'],
			MOL => [67, 'molise', 'campobasso', 'isernia'],
			PIE => ['piemonte', 'piedmont', 'torino', 'alessandria', 'asti', 'collegno', 'cuneo', 'moncalieri', 'novara', 'turin', 'biella', 'verbano-cusio-ossola', 'vercelli'],
			PUG => [75, 'puglia', 'apulia', 'bari', 'altamura', 'andria', 'barletta', 'bisceglie', 'bitonto', 'brindisi', 'cerignola', 'foggia', 'lecce', 'manfredonia', 'molfetta', 'san-severo', 'taranto', 'trani', 'barletta-andria-trani'],
			SAR => [88, 'sardegna', 'sardinia', 'cagliari', 'olbia', 'quartu-santelena', 'sassari', 'carbonia-iglesias', 'medio-campidano', 'nuoro', 'ogliastra', 'olbia-tempio', 'oristano'],
			SIC => ['sicilia', 'sicily', 'palermo', 'acireale', 'agrigento', 'bagheria', 'caltanissetta', 'catania', 'gela', 'marsala', 'mazara-del-vallo', 'messina', 'modica', 'ragusa', 'siracusa', 'syracuse', 'trapani', 'vittoria', 'enna'],
			TOS => [52, 'toscana', 'tuscany', 'firenze', 'arezzo', 'carrara', 'florence', 'grosseto', 'livorno', 'lucca', 'massa', 'pisa', 'pistoia', 'prato', 'scandicci', 'siena', 'viareggio', 'massa-and-carrara'],
			TRE => [32, 'trentino-alto-adige', 'trentino-sudtirol', 'trento', 'bolzano', 'bozen'],
			UMB => [55, 'umbria', 'perugia', 'foligno', 'terni'],
			VDA => [23, 'valle-daosta', 'vallee-daoste', 'aosta-valley', 'aosta'],
			VEN => [34, 'veneto', 'venetia', 'venezia', 'padova', 'padua', 'rovigo', 'treviso', 'venice', 'verona', 'vicenza', 'belluno'],
		}
	}, {
		cc		=> 'BR',
		regions	=> {
			DF	=> ['distrito-federal'],
			AC	=> ['acre'],
			AL	=> ['alagoas'],
			AP	=> ['amapa'],
			AM	=> ['amazonas'],
			BA	=> ['bahia'],
			CE	=> ['ceara'],
			ES	=> ['espirito-santo'],
			GO	=> ['goias'],
			MA	=> ['maranhao'],
			MT	=> ['mato-grosso'],
			MS	=> ['mato-grosso-do-sul'],
			MG	=> ['minas-gerais'],
			PA	=> ['para'],
			PB	=> ['paraiba'],
			PR	=> ['parana'],
			PE	=> ['pernambuco'],
			PI	=> ['piaui'],
			RJ	=> ['rio-de-janeiro'],
			RN	=> ['rio-grande-do-norte'],
			RS	=> ['rio-grande-do-sul'],
			RO	=> ['rondonia'],
			RR	=> ['roraima'],
			SC	=> ['santa-catarina'],
			SP	=> ['sao-paulo'],
			SE	=> ['sergipe'],
			TO	=> ['tocantins'],
		}
	}, {
		cc		=> 'FR',
		regions	=> {
			ALS	=> ['alsace', '67', 'bas-rhin', 'strasbourg', '68', 'haut-rhin', 'colmar', 'mulhouse'],
			AQU	=> ['aquitaine', '24', 'dordogne', 'perigueux', '33', 'gironde', 'bordeaux', '40', 'landes', 'mont-de-marsan', '47', 'lot-et-garonne', 'agen', '64', 'pyrenees-atlantiques', 'pau'],
			AUV	=> ['auvergne', '03', 'allier', 'moulins', '15', 'cantal', 'aurillac', '43', 'haute-loire', 'le-puy-en-velay', '63', 'puy-de-dome', 'clermont-ferrand'],
			BRE	=> ['brittany', 'bretagne', '22', 'cotes-darmor', 'saint-brieuc', '29', 'finistere', 'quimper', '35', 'ille-et-vilaine', 'rennes', '56', 'morbihan', 'vannes', 'brest'],
			BOU	=> ['burgundy', 'bourgogne', '21', 'cote-dor', 'dijon', '58', 'nievre', 'nevers', '71', 'saone-et-loire', 'macon', '89', 'yonne', 'auxerre'],
			CEN	=> ['centre', 'center-val-de-loire', '18', 'cher', 'bourges', '28', 'eure-et-loir', 'chartres', '36', 'indre', 'chateauroux', '37', 'indre-et-loire', 'tours', '41', 'loir-et-cher', 'blois', '45', 'loiret', 'orleans'],
			CHA	=> ['champagne-ardenne', 'chalons-en-champagne', 'champagne', '08', 'ardennes', 'charleville-mezieres', '10', 'aube', 'troyes', '51', 'marne', 'chalons-en-champagne', '52', 'haute-marne', 'chaumont', 'reims'],
			FRA	=> ['franche-comte', '25', 'doubs', 'besancon', '39', 'jura', 'lons-le-saunier', '70', 'haute-saone', 'vesoul', '90', 'territoire-de-belfort', 'belfort'],
			ILE	=> ['ile-de-france', 'idf', '75', 'paris', '77', 'seine-et-marne', 'melun', '78', 'yvelines', 'versailles', '91', 'essonne', 'evry', '92', 'hauts-de-seine', 'nanterre', '93', 'seine-saint-denis', 'bobigny', '94', 'val-de-marne', 'creteil', '95', 'val-doise', 'pontoise', 'argenteuil', 'boulogne-billancourt', 'montreuil', 'saint-denis'],
			LAN	=> ['languedoc-roussillon', 'languedoc', 'roussillon', '11', 'aude', 'carcassonne', '30', 'gard', 'nimes', '34', 'herault', 'montpellier', '48', 'lozere', 'mende', '66', 'pyrenees-orientales', 'perpignan'],
			LIM	=> ['limousin', '19', 'correze', 'tulle', '23', 'creuse', 'gueret', '87', 'haute-vienne', 'limoges'],
			LOR	=> ['lorraine', '54', 'meurthe-et-moselle', 'nancy', '55', 'meuse', 'bar-le-duc', '57', 'moselle', 'metz', '88', 'vosges', 'epinal'],
			BAS	=> ['lower-normandy', 'basse-normandie', '14', 'calvados', 'caen', '50', 'manche', 'saint-lo', '61', 'orne', 'alencon'],
			MID	=> ['midi-pyrenees', '09', 'ariege', 'foix', '12', 'aveyron', 'rodez', '31', 'haute-garonne', 'toulouse', '32', 'gers', 'auch', '46', 'lot', 'cahors', '65', 'hautes-pyrenees', 'tarbes', '81', 'tarn', 'albi', '82', 'tarn-et-garonne', 'montauban'],
			NOR	=> ['nord-pas-de-calais', '59', 'nord', 'lille', '62', 'pas-de-calais', 'arras'],
			PAY	=> ['pays-de-la-loire', '44', 'loire-atlantique', 'nantes', '49', 'maine-et-loire', 'angers', '53', 'mayenne', 'laval', '72', 'sarthe', 'le-mans', '85', 'vendee', 'la-roche-sur-yon'],
			PIC	=> ['picardy', 'picardie', '02', 'aisne', 'laon', '60', 'oise', 'beauvais', '80', 'somme', 'amiens'],
			POI	=> ['poitou-charentes', '16', 'charente', 'angouleme', '17', 'charente-maritime', 'la-rochelle', '79', 'deux-sevres', 'niort', '86', 'vienne', 'poitiers'],
			PRO	=> ['provence-alpes-cote-dazur', 'paca', 'provence-alpes', 'cote-dazur', '04', 'alpes-de-haute-provence', 'digne-les-bains', '05', 'hautes-alpes', 'gap', '06', 'alpes-maritimes', 'nice', '13', 'bouches-du-rhone', 'marseille', '83', 'var', 'toulon', '84', 'vaucluse', 'avignon', 'aix-en-provence'],
			RHO	=> ['rhone-alpes', 'ra', '01', 'ain', 'bourg-en-bresse', '07', 'ardeche', 'privas', '26', 'drome', 'valence', '38', 'isere', 'grenoble', '42', 'loire', 'saint-etienne', '69', 'rhone', 'lyon', '73', 'savoie', 'chambery', '74', 'haute-savoie', 'annecy', 'villeurbanne'],
			HAU	=> ['haute-normandie', 'upper-normandy', '27', 'eure', 'evreux', '76', 'seine-maritime', 'rouen', 'le-havre'],
			COR	=> ['corse', 'corsica', '2a', 'corse-du-sud', 'ajaccio', '2b', 'haute-corse', 'bastia']
		}
	}, {
		cc		=> 'JP',
		regions	=> {
			Aichi		=> ['aichi'],
			Akita		=> ['akita'],
			Aomori		=> ['aomori'],
			Chiba		=> ['chiba'],
			Ehime		=> ['ehime'],
			Fukui		=> ['fukui'],
			Fukuoka		=> ['fukuoka'],
			Fukushima	=> ['fukushima'],
			Gifu		=> ['gifu'],
			Gunma		=> ['gunma'],
			Hiroshima	=> ['hiroshima'],
			Hokkaido	=> ['hokkaido'],
			Hyogo		=> ['hyogo'],
			Ibaraki		=> ['ibaraki'],
			Ishikawa	=> ['ishikawa'],
			Iwate		=> ['iwate'],
			Kagawa		=> ['kagawa'],
			Kagoshima	=> ['kagoshima'],
			Kanagawa	=> ['kanagawa'],
			Kochi		=> ['kochi'],
			Kumamoto	=> ['kumamoto'],
			Kyoto		=> ['kyoto'],
			Mie			=> ['mie'],
			Miyagi		=> ['miyagi'],
			Miyazaki	=> ['miyazaki'],
			Nagano		=> ['nagano'],
			Nagasaki	=> ['nagasaki'],
			Nara		=> ['nara'],
			Niigata		=> ['niigata'],
			Oita		=> ['oita'],
			Okayama		=> ['okayama'],
			Okinawa		=> ['okinawa'],
			Osaka		=> ['osaka'],
			Saga		=> ['saga'],
			Saitama		=> ['saitama'],
			Shiga		=> ['shiga'],
			Shimane		=> ['shimane'],
			Shizuoka	=> ['shizuoka'],
			Tochigi		=> ['tochigi'],
			Tokushima	=> ['tokushima'],
			Tokyo		=> ['tokyo'],
			Tottori		=> ['tottori'],
			Toyama		=> ['toyama'],
			Wakayama	=> ['wakayama'],
			Yamagata	=> ['yamagata'],
			Yamaguchi	=> ['yamaguchi'],
			Yamanashi	=> ['yamanashi']
		}
	}, {
		cc		=> 'MX',
		regions	=> {
			DIF	=> ['distrito-federal'],
			AGU	=> ['aguascalientes'],
			BCN	=> ['baja-california'],
			BCS	=> ['baja-california-sur'],
			CAM	=> ['campeche'],
			COA	=> ['coahuila'],
			COL	=> ['colima'],
			CHP	=> ['chiapas'],
			CHH	=> ['chihuahua'],
			DUR	=> ['durango'],
			GUA	=> ['guanajuato'],
			GRO	=> ['guerrero'],
			HID	=> ['hidalgo'],
			JAL	=> ['jalisco'],
			MEX	=> ['mexico'],
			MIC	=> ['michoacan'],
			MOR	=> ['morelos'],
			NAY	=> ['nayarit'],
			NLE	=> ['nuevo-leon'],
			OAX	=> ['oaxaca'],
			PUE	=> ['puebla'],
			QUE	=> ['queretaro'],
			ROO	=> ['quintana-roo'],
			SLP	=> ['san-luis-potosi'],
			SIN	=> ['sinaloa'],
			SON	=> ['sonora'],
			TAB	=> ['tabasco'],
			TAM	=> ['tamaulipas'],
			TLA	=> ['tlaxcala'],
			VER	=> ['veracruz'],
			YUC	=> ['yucatan'],
			ZAC	=> ['zacatecas']
		}
	}, {
		cc		=> 'CH',
		regions	=> {
			AG	=> ['aargau'],
			AR	=> ['appenzell-ausserrhoden'],
			AI	=> ['appenzell-innerrhoden'],
			BL	=> ['basel-landschaft'],
			BS	=> ['basel-stadt'],
			BE	=> ['bern', 'berne'],
			FR	=> ['fribourg, freiburg'],
			GE	=> ['geneve'],
			GL	=> ['glarus'],
			GR	=> ['graubunden', 'grigioni'],
			JU	=> ['jura'],
			LU	=> ['luzern'],
			NE	=> ['neuchatel'],
			NW	=> ['nidwalden'],
			OW	=> ['obwalden'],
			SG	=> ['sankt-gallen'],
			SH	=> ['schaffhausen'],
			SZ	=> ['schwyz'],
			SO	=> ['solothurn'],
			TG	=> ['thurgau'],
			TI	=> ['ticino'],
			UR	=> ['uri'],
			VS	=> ['valais', 'wallis'],
			VD	=> ['vaud'],
			ZG	=> ['zug'],
			ZH	=> ['zurich']
		}
	}, {
		cc		=> 'DE',
		regions	=> {
			BW	=> ['baden-wurttemberg'],
			BY	=> ['bayern', 'bavaria'],
			BE	=> ['berlin'],
			BB	=> ['brandenburg'],
			HB	=> ['bremen'],
			HH	=> ['hamburg'],
			HE	=> ['hessen'],
			MV	=> ['mecklenburg-vorpommern'],
			NI	=> ['niedersachsen', 'lower-saxony'],
			NW	=> ['nordrhein-westfalen'],
			RP	=> ['rheinland-pfalz'],
			SL	=> ['saarland'],
			SN	=> ['sachsen'],
			ST	=> ['sachsen-anhalt'],
			SH	=> ['schleswig-holstein'],
			TH	=> ['thuringen'],
		}
	}, {
		cc		=> 'NL',
		regions	=> {
			DR	=> ['drenthe'],
			FL	=> ['flevoland'],
			FR	=> ['fryslan'],
			GE	=> ['gelderland', 'gel'],
			GR	=> ['groningen'],
			LI	=> ['limburg', 'lim'],
			NB	=> ['noord-brabant'],
			NH	=> ['noord-holland', 'nhl'],
			OV	=> ['overijssel'],
			UT	=> ['utrecht', 'utr'],
			ZE	=> ['zeeland'],
			ZH	=> ['zuid-holland', 'zho'],
			AW	=> ['aruba'],
			CW	=> ['curacao'],
			SX	=> ['sint-maarten'],
			BQ1	=> ['bonaire'],
			BQ2	=> ['saba'],
			BQ3	=> ['sint-eustatius']
		}
	}, {
		cc		=> 'IM',
		regions	=> {
			IOM	=> ['isle-of-man', 'imn']
		}
	} ];
}


#=====================================================

=head2 B<getRegionCode>

Given a string, returns a region code and country code or give it a string and country code and it will only return a region code for that country.

 my ($code, @cc) = getRegionCode($string);
 my $code = getRegionCode($string, $cc);

=cut
#=====================================================
sub getRegionCode {
	my $string = shift || return;
	my $cc = shift;
	
	my $regionsByCC = _getRegions;
	
	$string = normalize($string, TRUE);
	my $foundCode;
	my @foundCC;
	foreach my $countryDB (@{$regionsByCC}) {
		if ($cc && (uc($cc) ne $countryDB->{cc})) { next; }
		while (my($code, $values) = each(%{$countryDB->{regions}})) {
			# Keep looking for another matching code
			if ($foundCode) {
				if ($foundCode eq $code) {
					push(@foundCC, $countryDB->{cc});
					last;
				}
				next;
			}
			# Match on code
			if ($string eq lc($code)) {
				if ($cc) { return $code; }
				$foundCode = $code;
				push(@foundCC, $countryDB->{cc});
				last;
			}
			# Match on abbreviations
			foreach my $value (@{$values}) {
				if ($string eq $value) {
					if ($cc) { return $code; }
					return ($code, $countryDB->{cc});
				}
			}
		}
	}
	if ($foundCode) {
		unshift(@foundCC, $foundCode);
		return (@foundCC);
	}
}

#=====================================================

=head2 B<getRegionAliases>

 my $aliasList = getRegionAliases($cc, $region);

=cut
#=====================================================
sub getRegionAliases {
	my $cc = uc(shift) || return;
	my $region = uc(shift) || return;
	
	my $aliases;
	my $regionsByCC = _getRegions;
	foreach my $country (@{$regionsByCC}) {
		if ($country->{cc} eq $cc) {
			if ($country->{regions}->{$region}) {
				$aliases = $country->{regions}->{$region};
				last;
			}
			last;
		}
	}
	if (is_array($aliases)) {
		foreach my $alias (@{$aliases}) {
			$alias =~ s/-(.)/ \u$1/;
			$alias = ucfirst($alias);
		}
		unshift(@{$aliases}, uc($region));
		return $aliases;
	}
}

#=====================================================

=head2 B<getPostalCode>

Given a string, returns a postal code and country code.
  http://en.wikipedia.org/wiki/List_of_postal_codes

 my ($code, @cc) = getPostalCode($string);

 (\d{2,5}[- ]?\d{2,4}|[a-z][a-z0-9]{1,3}[- ]?[0-9][a-z0-9]{0,3}|[a-z][a-z0-9]{1,3})

=cut
#=====================================================
sub getPostalCode {
	my $string = shift || return;
	$string = normalize($string, TRUE);
	
	my $code;
	my @cc;
	# numeric
	if ($string =~ /^(\d{5})\-?(\d{4})$/) { $code = "$1-$2"; @cc = ('US'); }	# 9 or 5-4
	elsif ($string =~ /^(\d{5})\-?(\d{3})$/) { $code = "$1-$2"; @cc = ('BR'); }	# 8 or 5-3
	elsif ($string =~ /^(\d{3})\-?(\d{4})$/) { $code = "$1-$2"; @cc = ('JP'); }	# 7 or 3-4
	elsif ($string =~ /^(\d{3})\-(\d{2})$/) { $code = "$1-$2"; @cc = ('SE'); }	# 3-2
	elsif (($string =~ /^(\d{2})(\d{3})$/) && ($1 < 53)) { $code = "$1$2"; @cc = qw(US SE ES IT BR FR MX); }	# ES < 53000
	elsif ($string =~ /^(\d{5})$/) { $code = $1; @cc = qw(US SE IT BR FR MX); }	# 5
	elsif ($string =~ /^(\d{4})$/) { $code = $1; @cc = qw(AU BE CH NL); }		# 4
	elsif (($string =~ /^(\d{1,2}w?)$/) && ($string < 25)) { $code = $1; @cc = qw(IE); }
	# alpha
	elsif ($string =~ /^([abceghjklmnprstvxy]\d[abceghjklmnprstvwxyz])\-?(\d[abceghjklmnprstvwxyz]\d)$/) { $code = "$1-$2"; @cc = ('CA'); }
	elsif ($string =~ /^(im\d)\-?(\d[a-z][a-z])$/) { $code = "$1-$2"; @cc = ('IM'); }
	elsif ($string =~ /^([a-z][a-z]?\d\d?[a-z]?)\-?(\d[a-z][a-z])$/) { $code = "$1-$2"; @cc = ('GB'); }
	elsif ($string =~ /^([a-z][a-z]?\d\d?[a-z]?)$/) { $code = $1; @cc = ('GB'); }
	elsif ($string =~ /^(bfpo)\-?(\d{1,4})$/) { $code = "$1-$2"; @cc = ('GB'); }
	elsif ($string =~ /^(ai)\-?(2640)$/) { $code = "$1-$2"; @cc = ('AI'); }
	elsif ($string =~ /^(?:nl\-?)?(\d{4})\-?([a-z][a-z])$/) { $code = "NL-$1 $2"; @cc = ('NL'); }
	elsif ($string =~ /^(ascn)\-?(1zz)$/) { $code = "$1-$2"; @cc = ('SH-AC'); }
	elsif ($string =~ /^(sthl)\-?(1zz)$/) { $code = "$1-$2"; @cc = ('SH-SH'); }
	elsif ($string =~ /^(tdcu)\-?(1zz)$/) { $code = "$1-$2"; @cc = ('SH-TA'); }
	elsif ($string =~ /^(bbnd)\-?(1zz)$/) { $code = "$1-$2"; @cc = ('IO'); }
	elsif ($string =~ /^(biqq)\-?(1zz)$/) { $code = "$1-$2"; @cc = ('GB'); }
	elsif ($string =~ /^(fiqq)\-?(1zz)$/) { $code = "$1-$2"; @cc = ('FK'); }
	elsif ($string =~ /^(gx11)\-?(1aa)$/) { $code = "$1-$2"; @cc = ('GI'); }
	elsif ($string =~ /^(pcrn)\-?(1zz)$/) { $code = "$1-$2"; @cc = ('PN'); }
	elsif ($string =~ /^(siqq)\-?(1zz)$/) { $code = "$1-$2"; @cc = ('GS'); }
	elsif ($string =~ /^(tkca)\-?(1zz)$/) { $code = "$1-$2"; @cc = ('TC'); }
	else { return; }
	return (uc($code), @cc);
}

#=====================================================

=head2 B<getCountryCode>

Given a string, returns a country code.
  http://en.wikipedia.org/wiki/ISO_3166
  http://en.wikipedia.org/wiki/ISO_3166-1_alpha-2

 my $code = getCountryCode($string);

=cut
#=====================================================
sub getCountryCode {
	my $string = shift || return;
	my $countries = {
		AD => ['andorra', 'and'],
		AE => ['united-arab-emirates', 'are'],
		AF => ['afghanistan', 'afg'],
		AG => ['antigua-and-barbuda', 'antigua', 'barbuda', 'atg'],
		AI => ['anguilla', 'aia'],
		AL => ['albania', 'alb'],
		AM => ['armenia', 'arm'],
		AO => ['angola', 'ago'],
		AQ => ['antarctica', 'antarctique', 'ata'],
		AR => ['argentina', 'arg'],
		AS => ['american-samoa', 'asm'],
		AT => ['austria', 'aut'],
		AU => ['australia', 'ashmore-and-cartier-islands', 'coral-sea-islands', 'aus'],
		AW => ['aruba', 'abw'],
		AZ => ['azerbaijan', 'aze'],
		BA => ['bosnia-and-herzegovina', 'bosnia', 'herzegovina', 'bih'],
		BB => ['barbados', 'brb'],
		BD => ['bangladesh', 'bgd'],
		BE => ['belgium', 'bel'],
		BF => ['burkina-faso', 'upper-volta', 'bfa'],
		BG => ['bulgaria', 'bgr'],
		BH => ['bahrain', 'bhr'],
		BI => ['burundi', 'bdi'],
		BJ => ['benin', 'dahomey', 'ben'],
		BL => ['saint-barthelemy', 'blm'],
		BM => ['bermuda', 'bmu'],
		BN => ['brunei-darussalam', 'brunei', 'brn'],
		BO => ['bolivia', 'plurinational-state-of-bolivia', 'bol'],
		BQ => ['bonaire-sint-eustatius-and-saba', 'bonaire-saint-eustatius-and-saba', 'bonaire', 'sint-eustatius', 'saint-eustatius', 'saba', 'bes'],
		BR => ['brazil', 'bra'],
		BS => ['bahamas', 'bhs'],
		BT => ['bhutan', 'btn'],
		BV => ['bouvet-island', 'bvt'],
		BW => ['botswana', 'bwa'],
		BY => ['belarus', 'byelorussian-ssr', 'blr'],
		BZ => ['belize', 'blz'],
		CA => ['canada', 'can'],
		CC => ['cocos-keeling-islands', 'cocos-islands', 'keeling-islands', 'cck'],
		CD => ['congo', 'the-democratic-republic-of-the-congo', 'zaire', 'cog', 'cod'],
		CF => ['central-african-republic', 'caf'],
		CG => ['congo'],
		CH => ['switzerland', 'confoederatio-helvetica', 'helvetica', 'che'],
		CI => ['cote-divoire', 'civ'],
		CK => ['cook-islands', 'cok'],
		CL => ['chile', 'chl'],
		CM => ['cameroon', 'cmr'],
		CN => ['china', 'chn'],
		CO => ['colombia', 'col'],
		CR => ['costa-rica', 'cri'],
		CU => ['cuba', 'cub'],
		CV => ['cabo-verde', 'cpv'],
		CW => ['curacao', 'cuw'],
		CX => ['christmas-island', 'cxr'],
		CY => ['cyprus', 'cyp'],
		CZ => ['czech-republic', 'bohemia', 'cze'],
		DE => ['germany', 'deutschland', 'federal-republic-of-germany', 'west-germany', 'deu'],
		DJ => ['djibouti', 'french-afar-and-issas', 'french-territory-of-the-afars-and-the-issas', 'dji'],
		DK => ['denmark', 'dnk'],
		DM => ['dominica', 'dma'],
		DO => ['dominican-republic', 'dom'],
		DZ => ['algeria', 'dzayer', 'dza'],
		EC => ['ecuador', 'ecu'],
		EE => ['estonia', 'eesti', 'est'],
		EG => ['egypt', 'egy'],
		EH => ['western-sahara', 'spanish-sahara', 'sahara-espanol', 'esh'],
		ER => ['eritrea', 'eri'],
		ES => ['spain', 'espana', 'esp'],
		ET => ['ethiopia', 'eth'],
		FI => ['finland', 'fin'],
		FJ => ['fiji', 'fji'],
		FK => ['falkland-islands-malvinas', 'falkland-islands', 'malvinas', 'flk'],
		FM => ['micronesia', 'federated-states-of-micronesia', 'fsm'],
		FO => ['faroe-islands', 'fro'],
		FR => ['france', 'clipperton-island', 'fra'],
		GA => ['gabon', 'gab'],
		GB => ['united-kingdom', 'great-britain', 'northern-ireland', 'gbr', 'gbn', 'ukm', 'eaw', 'eng', 'nir', 'sct', 'wls'],
		GD => ['grenada', 'grd'],
		GE => ['georgia', 'geo'],
		GF => ['french-guiana', 'guyane-francaise', 'guf'],
		GG => ['guernsey', 'ggy', 'gsy', 'gur', 'sark', 'srk', 'alderney', 'ald'],
		GH => ['ghana', 'gha'],
		GI => ['gibraltar', 'gib'],
		GL => ['greenland', 'grl'],
		GM => ['gambia', 'gmb'],
		GN => ['guinea', 'gin'],
		GP => ['guadeloupe', 'glp'],
		GQ => ['equatorial-guinea', 'guinee-equatoriale', 'gnq'],
		GR => ['greece', 'grc'],
		GS => ['south-georgia-and-the-south-sandwich-islands', 'south-georgia', 'the-south-sandwich-islands', 'sgs'],
		GT => ['guatemala', 'gtm'],
		GU => ['guam', 'gum'],
		GW => ['guinea-bissau', 'gnb'],
		GY => ['guyana', 'guy'],
		HK => ['hong-kong', 'hkg'],
		HM => ['heard-island-and-mcdonald-islands', 'heard-island', 'mcdonald-islands', 'hmd'],
		HN => ['honduras', 'hnd'],
		HR => ['croatia', 'hrvatska', 'hrv'],
		HT => ['haiti', 'hti'],
		HU => ['hungary', 'hun'],
		ID => ['indonesia', 'idn'],
		IE => ['ireland', 'irl'],
		IL => ['israel', 'isr'],
		IM => ['isle-of-man', 'imn', 'iom'],
		IN => ['india', 'ind'],
		IO => ['british-indian-ocean-territory', 'iot'],
		IQ => ['iraq', 'irq'],
		IR => ['iran', 'islamic-republic-of-iran', 'irn'],
		IS => ['iceland', 'island', 'isl'],
		IT => ['italy', 'ita'],
		JE => ['jersey', 'jey', 'chi', 'jsy', 'jer'],
		JM => ['jamaica', 'jam'],
		JO => ['jordan', 'jor'],
		JP => ['japan', 'jpn'],
		KE => ['kenya', 'ken'],
		KG => ['kyrgyzstan', 'kgz'],
		KH => ['cambodia', 'khmer-republic', 'kampuchea', 'khm'],
		KI => ['kiribati', 'kir'],
		KM => ['comoros', 'komori', 'com'],
		KN => ['saint-kitts-and-nevis', 'saint-kitts-nevis-anguilla', 'saint-kitts', 'nevis', 'kna'],
		KP => ['democratic-peoples-republic-of-korea', 'north-korea', 'prk'],
		KR => ['korea', 'republic-of-korea', 'south-korea', 'kor'],
		KW => ['kuwait', 'kwt'],
		KY => ['cayman-islands', 'cym'],
		KZ => ['kazakhstan', 'kazakstan', 'kaz'],
		LA => ['lao-peoples-democratic-republic', 'laos', 'lao'],
		LB => ['lebanon', 'lbn'],
		LC => ['saint-lucia', 'lca'],
		LI => ['liechtenstein', 'lie'],
		LK => ['sri-lanka', 'lka'],
		LR => ['liberia', 'lbr'],
		LS => ['lesotho', 'lso'],
		LT => ['lithuania', 'ltu'],
		LU => ['luxembourg', 'lux'],
		LV => ['latvia', 'lva'],
		LY => ['libya', 'libyan-arab-jamahiriya', 'lby'],
		MA => ['morocco', 'maroc', 'mar'],
		MC => ['monaco', 'mco'],
		MD => ['moldova', 'republic-of-moldova', 'prk'],
		ME => ['montenegro', 'mne'],
		MF => ['french-saint-martin', 'saint-martin', 'sxm'],
		MG => ['madagascar', 'mdg'],
		MH => ['marshall-islands', 'mhl'],
		MK => ['macedonia', 'former-yugoslav-republic-of-macedonia', 'republic-of-macedonia', 'makedonija', 'mkd'],
		ML => ['mali', 'mli'],
		MM => ['myanmar', 'burma', 'mmr'],
		MN => ['mongolia', 'mng'],
		MO => ['macao', 'macau', 'mac'],
		MP => ['northern-mariana-islands', 'mnp'],
		MQ => ['martinique', 'mtq'],
		MR => ['mauritania', 'mrt'],
		MS => ['montserrat', 'msr'],
		MT => ['malta', 'mlt'],
		MU => ['mauritius', 'mus'],
		MV => ['maldives', 'mdv'],
		MW => ['malawi', 'mwi'],
		MX => ['mexico', 'mex'],
		MY => ['malaysia', 'mys'],
		MZ => ['mozambique', 'moz'],
		NA => ['namibia', 'nam'],
		NC => ['new-caledonia', 'ncl'],
		NE => ['niger', 'ner'],
		NF => ['norfolk-island', 'nfk'],
		NG => ['nigeria', 'nga'],
		NI => ['nicaragua', 'nic'],
		NL => ['netherlands', 'nld'],
		NO => ['norway', 'nor'],
		NP => ['nepal', 'npl'],
		NR => ['nauru', 'nru'],
		NU => ['niue', 'niu'],
		NZ => ['new-zealand', 'nzl'],
		OM => ['oman', 'omn'],
		PA => ['panama', 'pan'],
		PE => ['peru', 'per'],
		PF => ['french-polynesia', 'polynesie-francaise', 'pyf'],
		PG => ['papua-new-guinea', 'png'],
		PH => ['philippines', 'phl'],
		PK => ['pakistan', 'pak'],
		PL => ['poland', 'pol'],
		PM => ['saint-pierre-and-miquelon', 'saint-pierre', 'miquelon', 'spm'],
		PN => ['pitcairn', 'pcn'],
		PS => ['palestine', 'state-of-palestine', 'palestinian-territory', 'west-bank', 'gaza-strip', 'pse'],
		PT => ['portugal', 'prt'],
		PW => ['palau', 'plw'],
		PY => ['paraguay', 'pry'],
		QA => ['qatar', 'qat'],
		RE => ['reunion', 'reu'],
		RO => ['romania', 'rou'],
		RS => ['serbia', 'republic-of-serbia', 'srb'],
		RU => ['russian-federation', 'russia', 'rus'],
		RW => ['rwanda', 'rwa'],
		SA => ['saudi-arabia', 'sau'],
		SB => ['solomon-islands', 'british-solomon-islands', 'slb'],
		SC => ['seychelles', 'syc'],
		SD => ['sudan', 'sdn'],
		SE => ['sweden', 'swe'],
		SG => ['singapore', 'sgp'],
		SH => ['saint-helena-ascension-and-tristan-da-cunha', 'saint-helena', 'ascension', 'tristan-da-cunha', 'shn'],
		SI => ['slovenia', 'svn'],
		SJ => ['svalbard-and-jan-mayen', 'svalbard', 'jan-mayen', 'sjm'],
		SK => ['slovakia', 'svk'],
		SL => ['sierra-leone', 'sle'],
		SM => ['san-marino', 'smr'],
		SN => ['senegal', 'sen'],
		SO => ['somalia', 'som'],
		SR => ['suriname', 'sur'],
		SS => ['south-sudan', 'ssd'],
		ST => ['sao-tome-and-principe', 'sao-tome', 'principe', 'stp'],
		SV => ['el-salvador', 'slv'],
		SX => ['dutch-sint-maarten', 'sint-maarten', 'sxm'],
		SY => ['syrian-arab-republic', 'syria', 'syr'],
		SZ => ['swaziland', 'swz'],
		TC => ['turks-and-caicos-islands', 'caicos-islands', 'turks', 'turks-islands', 'tca'],
		TD => ['chad', 'tchad', 'tcd'],
		TF => ['french-southern-territories', 'terres-australes-francaises', 'atf'],
		TG => ['togo', 'tgo'],
		TH => ['thailand', 'tha'],
		TJ => ['tajikistan', 'tjk'],
		TK => ['tokelau', 'tkl'],
		TL => ['timor-leste', 'east-timor', 'tls'],
		TM => ['turkmenistan', 'tkm'],
		TN => ['tunisia', 'tun'],
		TO => ['tonga', 'ton'],
		TR => ['turkey', 'tur'],
		TT => ['trinidad-and-tobago', 'trinidad', 'tobago', 'tto'],
		TV => ['tuvalu', 'tuv'],
		TW => ['taiwan-province-of-china', 'taiwan', 'republic-of-china', 'twn'],
		TZ => ['tanzania', 'united-republic-of-tanzania', 'tza'],
		UA => ['ukraine', 'ukrainian-ssr', 'ukr'],
		UG => ['uganda', 'uga'],
		UM => ['united-states-minor-outlying-islands', 'baker-island', 'howland-island', 'jarvis-island', 'johnston-atoll', 'kingman-reef', 'midway-islands', 'midway-atoll', 'navassa-island', 'palmyra-atoll', 'wake-island', 'umi'],
		US => ['united-states', 'united-states-of-america', 'usa', 'puerto-rico', 'pri', 'pr'],
		UY => ['uruguay', 'ury'],
		UZ => ['uzbekistan', 'uzb'],
		VA => ['holy-see', 'vatican-city-state', 'vatican-city', 'vat'],
		VC => ['saint-vincent-and-the-grenadines', 'saint-vincent', 'grenadines', 'vct'],
		VE => ['venezuela', 'bolivarian-republic-of-venezuela', 'ven'],
		VG => ['british-virgin-islands', 'vgb'],
		VI => ['us-virgin-islands', 'virgin-islands', 'vir'],
		VN => ['viet-nam', 'vietnam', 'vnm'],
		VU => ['vanuatu', 'new-hebrides', 'vut'],
		WF => ['wallis-and-futuna', 'wallis', 'futuna', 'wlf'],
		WS => ['samoa', 'western-samoa', 'wsm'],
		YE => ['yemen', 'republic-of-yemen', 'north-yemen', 'yem'],
		YT => ['mayotte', 'myt'],
		ZA => ['south-africa', 'zuid-afrika', 'zaf'],
		ZM => ['zambia', 'zmb'],
		ZW => ['zimbabwe', 'southern-rhodesia', 'zwe']
	};
	$string = normalize($string, TRUE);
	while (my($code, $values) = each(%{$countries})) {
		if ($string eq lc($code)) { return $code; }
		foreach my $value (@{$values}) {
			if ($string eq $value) { return $code; }
		}
	}
}

#=====================================================

=head2 B<getMonth>

Given a month number, abbreviation, or name, returns the month as the format in the second argument. Defaults to the month number (1-12). It is case-insensitive.

 my $num = getMonth('October');
 my $abbr = getMonth('oct', 'abbr');
 my $name = getMonth(10, 'name');

=cut
#=====================================================
sub getMonth {
	my $name = lc(shift) || return;
	my $format = shift;
	my @months = qw(January February March April May June July August September October November December);
	my $num = 1;
	foreach my $month (@months) {
		if ($name eq lc($month)) { last; }
		elsif (is_pos_int($name)) { if ($name == $num) { last; } }
		else {
			my $abbr = substr($month, 0, 3);
			if ($name eq lc($abbr)) { last; }
		}
		$num++;
	}
	my $month = $months[$num-1];
	if (($num > 12) || !$month) { return; }
	if ($format =~ /^abbr/) { return substr($month, 0, 3); }
	if ($format eq 'name') { return $month; }
	return $num;
}


#=====================================================

=head2 B<round>

 my $roundedNumber = round($number);
 my $roundedNumber = round($number, $precision);

=cut
#=====================================================
sub round {
	my $number = shift || return 0;
	my $precision = shift;
	if ($precision) { $number = $number * (10**$precision); }
	my $rounded = int($number + $number/abs($number*2));
	if ($precision) { $rounded = $rounded / (10**$precision); }
	return $rounded;
}

#=====================================================

=head2 B<significant>

 my $roundedNumber = significant($number);
 my $roundedNumber = significant($number, $precision);

 significant(12.73, 2); # Returns 12
 significant(12.73, 3); # Returns 12.7
 significant(12.73, 4); # Returns 12.73

=cut
#=====================================================
sub significant {
	my $number = shift || return 0;
	my $precision = shift;
	my $count = length(int($number));
	if ($count < $precision) {
		return round($number, $precision - $count);
	} else {
		return round($number);
	}
}

#=====================================================

=head2 B<percent>

Like round, but multiplied by 100.

=cut
#=====================================================
sub percent {
	my $number = shift || return 0;
	my $precision = shift;
	return round($number * 100, $precision);
}


#=====================================================

=head2 B<max>

 my $max = max($number, $number, ...);
 my $max = max($arrayOfNumbers);
 my $max = max($hash, $key);
 my $max = max($arrayHash, $key);

=cut
#=====================================================
sub max {
	my @input = @_;
	my $numbers = \@input;
	if (ref($input[0])) { $numbers = to_array(@input); }
	@{$numbers} || return;
	
	my $max = shift(@{$numbers});
	foreach my $number (@{$numbers}) {
		if ($number > $max) { $max = $number; }
	}
	return $max;
}


#=====================================================

=head2 B<min>

 my $min = min($number, $number, ...);
 my $min = min($arrayOfNumbers);
 my $min = min($hash, $key);
 my $min = min($arrayHash, $key);

=cut
#=====================================================
sub min {
	my @input = @_;
	my $numbers = \@input;
	if (ref($input[0])) { $numbers = to_array(@input); }
	@{$numbers} || return;
	
	my $min = shift(@{$numbers});
	foreach my $number (@{$numbers}) {
		if ($number < $min) { $min = $number; }
	}
	return $min;
}


#=====================================================

=head2 B<isClose>

 if (isClose($numberA, $numberB, $distance))

=cut
#=====================================================
sub isClose {
	my $a = shift || return;
	my $b = shift || return;
	my $distance = shift || 0;
	if (($a >= ($b - $distance)) && ($a <= ($b + $distance))) { return TRUE; }
}

#=====================================================

=head2 B<summarizeNumber>

 my $summarizedBytes = summarizeNumber($number);
 my $summarizedBytes = summarizeNumber($number, $precision);

 summarizeNumber(16384, 3); # Returns "16.4 K"

=cut
#=====================================================
sub summarizeNumber {
	my $number = shift || return 0;
	my $precision = shift;
	my $base = 1000;
	my @labels = ('', ' k', ' M', ' G', ' T', ' P', ' E', ' Z', ' Y');
	my $label = $number;
	for (my $i = 8; $i >= 0; $i--) {
		if ($number >= ($base**$i)) {
			$label = significant($number / ($base**$i), $precision);
			$label .= $labels[$i];
			last;
		}
	}
	return $label;
}

#=====================================================

=head2 B<summarizeBytes>

 my $summarizedBytes = summarizeBytes($number);
 my $summarizedBytes = summarizeBytes($number, $precision);

=cut
#=====================================================
sub summarizeBytes {
	my $number = shift || return 0;
	my $precision = shift;
	my $base = 1024;
	my @labels = ('', ' kB', ' MB', ' GB', ' TB', ' PB', ' EB', ' ZB', ' YB');
	my $label = $number;
	for (my $i = 8; $i >= 0; $i--) {
		if ($number >= ($base**$i)) {
			$label = significant($number / ($base**$i), $precision);
			$label .= $labels[$i];
			last;
		}
	}
	return $label;
}

#=====================================================

=head2 B<makeOrdinal>

 my $ordinal = makeOrdinal($number);

=cut
#=====================================================
sub makeOrdinal {
	my $number = shift || return;
	is_pos_int($number) || return $number;
	if ($number =~ /1$/) { return $number . 'st'; }
	if ($number =~ /2$/) { return $number . 'nd'; }
	if ($number =~ /3$/) { return $number . 'rd'; }
	else { return $number . 'th'; }
}


#=====================================================

=head2 B<pluralize>

 my $plural = pluralize($singular);
 my $singularOrPlural = pluralize($singular, $number);

=cut
#=====================================================
sub pluralize {
	my $text = shift || return;
	my $number = shift;
	if (defined($number) && ($number == 1)) { return $text; }
	
	if ($text =~ /[e]$/) { return $text . 's'; }
	if ($text =~ s/ase$/ases/) { }
	elsif ($text =~ s/esis$/eses/) { }
	elsif ($text =~ s/ouse$/ouses/) { }
	elsif ($text =~ s/us$/uses/) { }
	elsif ($text =~ s/ma$/mata/) { }
	elsif ($text =~ s/([ae])ndum$/${1}nda/) { }
	elsif ($text =~ s/(s|x|ch|sh)$/${1}es/) { }
	elsif ($text =~ s/y$/ies/) { }
	elsif ($text =~ s/rae$/rae/) { }
	elsif ($text =~ s/([^aeiouy])a$/${1}ae/) { }
	elsif ($text =~ s/([ei])fe$/${1}ves/) { }
	elsif ($text =~ s/([ei])af$/${1}aves/) { }
	elsif ($text =~ s/f$/ves/) { }
	elsif ($text =~ s/brother$/brethren/) { }
	elsif ($text =~ s/child$/children/) { }
	elsif ($text =~ s/ox$/oxen/) { }
	elsif ($text =~ s/([^aeiouy])ex$/${1}ices/) { }
	elsif ($text =~ s/x$/xes/) { }
	elsif ($text =~ s/eau$/eaus/) { }
	elsif ($text =~ /(?:[isux]|ch|sh|[aeiu]o)s$/) { }
	else { $text =~ s/$/s/; }
	return $text;
}


sub join_text {
#=====================================================

=head2 B<join_text>

=cut
#=====================================================
	my $list = shift || return;
	is_array_with_content($list) || return;
	if (@{$list} < 2) { return $list->[0]; }
	if (@{$list} == 2) { return "$list->[0] and $list->[1]"; }
	my $string = $list->[0];
	for (my $i = 1; $i < @{$list}; $i++) {
		if ($i == @{$list} - 1) { $string .= ", and $list->[$i]"; }
		else { $string .= ", $list->[$i]"; }
	}
	return $string;
}


#=====================================================

=head2 B<arrayLength>

Returns the number of elements in an array ref.

=cut
#=====================================================
sub arrayLength {
	my $array = shift || return;
	if ((ref($array) eq 'ARRAY')) {
		my $size = @{$array};
		return $size;
	}
	return;
}

#=====================================================

=head2 B<first>

Returns the first element of an array or if a string is given, it returns a string.
It used to return a null, if not an array. That was probably for using it with if statements. I removed it from all ifs.
Be careful using in if statements as a first element of 0 will return a negative.
See is_array, is_array_with_content, or arrayLength.

=cut
#=====================================================
sub first {
	my $array = shift || return;
	if (is_array_with_content($array)) {
		return $array->[0];
	} elsif (ref($array) eq 'SCALAR') {
		return ${$array};
	} elsif (!ref($array)) {
		return $array;
	}
	return;
}

#=====================================================

=head2 B<value>

Returns a single scalar value from a scalar, array, hash, or arrayHash.
A hash or arrayHash requires a key to be specified as the second argument.

 my $value = value($ref);
 my $value = value($hash, $key);
 my $value = value($arrayHash, $key);

=cut
#=====================================================
sub value {
	my $ref = shift || return;
	my $key = shift;
	if (ref($ref) eq 'SCALAR') {
		return ${$ref};
	} elsif (is_array_hash($ref)) {
		if ($key && $ref->[0]->{$key}) { return $ref->[0]->{$key}; }
	} elsif (ref($ref) eq 'ARRAY') {
		if ($ref->[0]) { return $ref->[0]; }
	} elsif (is_hash($ref)) {
		if ($key) { return $ref->{$key}; }
	} else {
		return $ref;
	}
}


#=====================================================

=head2 B<refToScalar>

 my $text = refToScalar($ref, $delimiter);

=cut
#=====================================================
sub ref_to_scalar { return refToScalar(@_); }
sub refToScalar {
	my $reference = shift || return;
	my $delimiter = shift || ',';
	
	my $answer;
	if (!ref($reference)) { $answer = $reference; }
	elsif (ref($reference) eq 'SCALAR') { $answer = $$reference; }
	elsif (ref($reference) eq 'ARRAY') { $answer = join($delimiter, @{$reference}); }
	elsif (ref($reference) eq 'HASH') { $answer = join($delimiter, keys(%{$reference})); }
	return $answer;
}


#=====================================================

=head2 B<arrayToList>

This will return a comma-delimited string of unique values from the given array ref. An optional second argument can be passed for the delimiter.

 $string = arrayToList($array);
 $string = arrayToList($array, $delimiter);

=cut
#=====================================================
sub array_to_list { return arrayToList(@_); }
sub arrayToList {
	my $array = shift || return;
	my $delimiter = shift || ',';
	
	my $new_array = uniqueArray($array);
	if ($new_array && @{$new_array}) {
		return join($delimiter, @{$new_array});
	}
	return;
}


#=====================================================

=head2 B<listToArray>

This will return an array ref of unique values from the given comma-delimited string. An optional second argument can be passed for the delimiter.

 $array = listToArray($string);
 $array = listToArray($string, $delimiter);

=cut
#=====================================================
sub list_to_array { return listToArray(@_); }
sub listToArray {
	my $list = shift || return [];
	my $delimiter = shift || ',';
	
	my @new_array = split(/\s*$delimiter\s*/, $list);
	if (@new_array) {
		my $clean_array = uniqueArray(\@new_array);
		return $clean_array;
	}
	return [];
}


#=====================================================

=head2 B<list_to_array_auto>

Given a string, list_to_array_auto guesses at a list delimiter, then returns an array of the list items with details about the parsing.

 my ($array, $delimiter, $firstLine, $lastLine, $leadingSpace) = list_to_array_auto($string);

=cut
#=====================================================
sub list_to_array_auto {
	my $string = shift;
	
	my @list;
	my $delimiter = "\n";
	my $firstChomp;
	my $lastChomp = chomp($string);
	my $leadingSpace;
	my $cnt;
	
	my @lines = split(/\n/, $string);
	foreach my $line (@lines) {
		if (!$cnt) { ($leadingSpace) = $line =~ /^(\s+)/; }
		$line =~ s/(?:^\s+|\s+$)//g;
		if (length($line)) { push(@list, $line); }
		elsif (!$cnt) { $firstChomp = $lastChomp; }
		$cnt++;
	}
	my $array = [];
	if (@list == 1) {
		my $test = $list[0];
		my $tabCnt = $test =~ s/(\t)/$1/g;
		my $pipeSpaceCnt = $test =~ s/(\s+\|\s+)/$1/g;
		my $pipeCnt = $test =~ s/(\|)/$1/g;
		my $commaCnt = $test =~ s/(\s*,\s*)/,/g;
		my $spaceCnt = $test =~ /(\s+)/;
		my $liCnt = $test =~ /^(<li)/;
		my $detector = '\s+';
		if ($test =~ /^<li/) { $detector = '\s*</li>\s*<li.*?>\s*'; $delimiter = 'li'; }
		elsif ($tabCnt) { $detector = '\t+'; $delimiter = "\t"; }
		elsif ($pipeSpaceCnt > 1) { $detector = '(?:\s*\|\s*)+'; $delimiter = " | "; }
		elsif ($pipeCnt > $commaCnt) { $detector = '(?:\s*\|\s*)+'; $delimiter = "|"; }
		elsif ($commaCnt > $spaceCnt) { $detector = '(?:\s*,\s*)+'; $delimiter = ", "; }
		else { $delimiter = " "; }
		my @tmpList = split($detector, $list[0]);
		foreach (@tmpList) {
			s/(^<li.*?>\s*|\s*<\/li>$)//ig;
			if (length($_)) { push(@{$array}, $_); }
		}
		return ($array, $delimiter, $firstChomp, $lastChomp, $leadingSpace);
	} else {
		$array = \@list;
		$delimiter = "\n" . $leadingSpace;
		foreach (@{$array}) {
			if (/^<li/) { $delimiter = 'li'; }
			s/(^<li.*?>\s*|\s*<\/li>$)//ig;
		}
		return ($array, $delimiter, $firstChomp, $lastChomp, $leadingSpace);
	}
}


#=====================================================

=head2 B<add_to_list>

=cut
#=====================================================
sub add_to_list {
	my $list = shift;
	my $delimiter = shift;
	my $array = to_array($list);
	foreach my $item (@_) {
		if (!contains($array, $item)) { push(@{$array}, $item); }
	}
	return arrayToList($array, $delimiter);
}


#=====================================================

=head2 B<remove_from_array>

Remove a list of items from the specified list.

 my $newList = remove_from_array($bigList, $item, [$item, ...]);

=cut
#=====================================================
sub remove_from_array {
	my $list = shift || return;
	my @remove = @_;
	
	if (ref($list) eq 'ARRAY') {
		my $remove = to_hash(\@remove);
		my $newArray = [];
		foreach my $item (@{$list}) {
			unless ($remove->{$item}) { push(@{$newArray}, $item); }
		}
		return $newArray;
	} else {
		return $list;
	}
}


#=====================================================

=head2 B<to_array>

Given an array of hashes and a key, this will return an array of the values of that key from all the hashes.

 $array = to_array($arrayhash, $key);
 $array = to_array($hashhash, $key);
 $array = to_array($arrayarray);
 $array = to_array($hasharray);
 $array = to_array($array);
 $array = to_array($hash);
 $array = to_array($scalar);

=cut
#=====================================================
sub to_array {
	my $list = shift || return [];
	my $key = shift;
	
	my $newList = [];
	if (is_hash($list)) {
		while(my($name, $item) = each(%{$list})) {
			if (is_hash($item)) {
				if ($key && $item->{$key}) {
					push(@{$newList}, $item->{$key});
				}
			} elsif (ref($item) eq 'ARRAY') {
				push(@{$newList}, @{$item});
			} elsif (ref($item) eq 'SCALAR') {
				if (${$item}) {
					push(@{$newList}, ${$item});
				}
			} elsif ($item) {
				push(@{$newList}, $item);
			}
		}
	} elsif (ref($list) eq 'ARRAY') {
		foreach my $item (@{$list}) {
			if (is_hash($item)) {
				if ($key && $item->{$key}) {
					push(@{$newList}, $item->{$key});
				}
			} elsif (ref($item) eq 'ARRAY') {
				push(@{$newList}, @{$item});
			} elsif (ref($item) eq 'SCALAR') {
				if (${$item}) {
					push(@{$newList}, ${$item});
				}
			} elsif ($item) {
				push(@{$newList}, $item);
			}
		}
	} elsif (ref($list) eq 'SCALAR') {
		if (${$list}) {
			push(@{$newList}, ${$list});
		}
	} else {
		if ($list) {
			push(@{$newList}, $list);
		}
	}
	
	return uniqueArray($newList);
}


#=====================================================

=head2 B<to_list>

Should do better at distinguishing delimiter vs. key.

Wrapper for to_array to make a delimited list based on output from to_array.

 $array = to_list($arrayhash, $key, $delimiter);
 $array = to_list($hashhash, $key, $delimiter);
 $array = to_list($arrayarray, $delimiter);
 $array = to_list($hasharray, $delimiter);
 $array = to_list($array, $delimiter);
 $array = to_list($hash, $delimiter);
 $array = to_list($scalar, $delimiter);

=cut
#=====================================================
sub to_list {
	my $list = shift || return '';
	my $key = shift;
	my $delimiter = shift;
	
	if (is_array_hash($list)) { }
	elsif (!$delimiter && ($key !~ /[a-zA-Z0-9]/)) { $delimiter = $key; undef $key; }
	my $array = to_array($list, $key);
	return arrayToList($array, $delimiter);
	
}


#=====================================================

=head2 B<to_hash>

 $hash = to_hash($hash, $keyName, $valueName);
 $hash = to_hash($arrayhash, $keyName, $valueName);
 $hash = to_hash($arrayarray, undef, $value);
 $hash = to_hash($array, undef, $value);
 $hash = to_hash($scalar, undef, $value);

=cut
#=====================================================
sub to_hash {
	my $list = shift || return;
	my $key = shift;
	my $value = shift;
	
	my $hash;
	if (is_hash($list)) {
		if ($key && $list->{$key}) {
			if ($value && $list->{$value}) { $hash->{$list->{$key}} = $list->{$value}; }
			else { $hash->{$list->{$key}} = 1; }
		}
	} elsif (ref($list) eq 'ARRAY') {
		foreach my $item (@{$list}) {
			if (is_hash($item)) {
				if ($key && $item->{$key}) {
					if ($value && $item->{$value}) { $hash->{$item->{$key}} = $item->{$value}; }
					else { $hash->{$item->{$key}} = 1; }
				}
			} elsif (ref($item) eq 'ARRAY') {
				foreach my $item2 (@{$item}) {
					if ((ref($item2) eq 'SCALAR') && ((${$item2} == '0') || ${$item2})) {
						if ($value) { $hash->{${$item2}} = $value; }
						else { $hash->{${$item2}} = 1; }
					} elsif (!ref($item2) && (($item2 == '0') || $item2)) {
						if ($value) { $hash->{$item2} = $value; }
						else { $hash->{$item2} = 1; }
					}
				}
			} elsif ((ref($item) eq 'SCALAR') && ((${$item} == '0') || ${$item})) {
				if ($value) { $hash->{${$item}} = $value; }
				else { $hash->{${$item}} = 1; }
			} elsif (!ref($item) && (($item == '0') || $item)) {
				if ($value) { $hash->{$item} = $value; }
				else { $hash->{$item} = 1; }
			}
		}
	} elsif ((ref($list) eq 'SCALAR') && ((${$list} == '0') || ${$list})) {
		if ($value) { $hash->{${$list}} = $value; }
		else { $hash->{${$list}} = 1; }
	} elsif (!ref($list) && (($list == '0') || $list)) {
		if ($value) { $hash->{$list} = $value; }
		else { $hash->{$list} = 1; }
	}
	return $hash;
}


#=====================================================

=head2 B<to_hash_hash>

Given an array of hashes, this will return a hash of hashes using the value of the specified key as the key.

 $hash = to_hash_hash($arrayhash, $key);

=cut
#=====================================================
sub arrayhash_to_hashhash { return to_hash_hash(@_); }
sub to_hash_hash {
	my $list = shift || return;
	my $key = shift || return;
	
	my $hash;
	foreach my $item (@{$list}) {
		if ($item->{$key}) {
			$hash->{$item->{$key}} = $item;
		}
	}
	return $hash;
}


#=====================================================

=head2 B<arrayToHash>

Given an array ref, this will return a hash with the array items as keys and 1 as the value. The value can be specified with the second argument.

 $hash = arrayToHash($arrayref);
 $hash = arrayToHash($arrayref, $value);

=cut
#=====================================================
sub array_to_hash { return arrayToHash(@_); }
sub arrayToHash {
	my $array = shift || return;
	my $value = shift || 1;
	
	return to_hash($array, undef, $value);
}


#=====================================================

=head2 B<uniqueArray>

This will return an array of unique values from the given array. Alternately, passing it an array of hashes with a key will return an array of unique values from the value of the specified key from all the hashes.

 $array = uniqueArray($arrayhash, $key);
 $array = uniqueArray($array);

=cut
#=====================================================
sub unique_array { return uniqueArray(@_); }
sub uniqueArray {
	my $list = shift || return;
	my $key = shift;
	is_array_with_content($list) || return [];
	
	my $new = [];
	my $itemHash;
	foreach my $item (@{$list}) {
		my $value;
		if ($key && is_hash($item)) {
			if (defined($item->{$key})) { $value = $item->{$key}; }
			else { next; }
		}
		elsif (defined($item)) { $value = $item; }
		else { next; }
		
		my $found;
		foreach my $newItem (@{$new}) {
			if (($value == $newItem) && ($value eq $newItem)) { $found = TRUE; }
		}
		$found && next;
		push(@{$new}, $value);
	}
	return $new;
}


#=====================================================

=head2 B<contains>

Accepts scalar, array, or hash refs and counts the number of occurrences of the match in them. For hash refs, it looks at the values. The match as a literal will only count an exact match. The match with surrounding slashes will be treated as a partial regular expression match.

 if (contains($array, $match))
 my $total = contains($array, $match);
 if (contains($array, '/^bob/'))		# Everything that starts with bob
 if (contains($array, 'bob'))			# Everything that is exactly bob

=cut
#=====================================================
sub contains {
	my $input = shift || return;
	my $match = shift || return;
	
	my $cnt = 0;
	if ($match =~ m#^/.*?/$#) {
		$match = strip($match, '/');
		if (!ref($input)) {
			if ($input =~ /$match/) { $cnt++; }
		} elsif (ref($input) eq 'SCALAR') {
			if (${$input} =~ /$match/) { $cnt++; }
		} elsif (is_array($input)) {
			foreach my $value (@{$input}) {
				if (!ref($value) && ($value =~ /$match/)) { $cnt++; }
			}
		} elsif (is_hash($input)) {
			while (my($name, $value) = each(%{$input})) {
				if (!ref($value) && ($value =~ /$match/)) { $cnt++; }
			}
		}
	} else {
		if (!ref($input)) {
			if ($input eq $match) { $cnt++; }
		} elsif (ref($input) eq 'SCALAR') {
			if (${$input} eq $match) { $cnt++; }
		} elsif (is_array($input)) {
			foreach my $value (@{$input}) {
				if (!ref($value) && ($value eq $match)) { $cnt++; }
			}
		} elsif (is_hash($input)) {
			while (my($name, $value) = each(%{$input})) {
				if (!ref($value) && ($value eq $match)) { $cnt++; }
			}
		}
	}
	return $cnt;
}


sub by_any {
#=====================================================

=head2 B<by_any>

Sorts on one or more fields in an array of arrays, hashes, or values.

 my @sortedArray = sort { by_any($a,$b,$options) } @unsortedArray;
 my @sortedArray = sort { by_any($a,$b,$columnToSort,$options) } @unsortedArray;
 my @sortedArray = sort { by_any($a,$b,$listOfColumnsToSort,$options) } @unsortedArray;

 $columnToSort is the field name (for hashes) or element number (for arrays) on which to sort. It defaults to 0.
 $listOfColumnsToSort is an array ref of the field names (for hashes) or element numbers (for arrays) in order of which such take precedence in sorting. It defaults to [0].
 $options can include the following. The default is for numbers and undefined/blanks to sort first. The sort columns can be included here instead of as the third argument.
 {
 	numbersLast		=> TRUE,
 	nullsLast		=> TRUE,
 	sortList		=> $listOfColumnsToSort
 }

 my @unsortedArray = ('eggplant', '', undef, '.5', 2.5, 'egg', '½', 'aardvark', '0', 'umbrella', '.eggs', 'e.ggs', 'éek', 'eggs', '2', 'zebra', '10', 'éggplant');
 my @sortedArray = sort { by_any($a,$b) } @unsortedArray;
 foreach my $item (@sortedArray) { print "  $item\n"; }

=cut
#=====================================================
	my $a = shift;
	my $b = shift;
	my $options = shift;
	my $fieldList = [0];
	if (is_array($options) || is_text($options)) {
		$fieldList = $options;
		$options = shift;
	}
	if (!is_hash($options)) { $options = {}; }
	
	if ($options->{sortList}) { $fieldList = $options->{sortList}; }
	if (is_text($fieldList)) { $fieldList = [$fieldList]; }
	if (!is_array($fieldList)) { $fieldList = [0]; }
	
	sub isNothing {
		my $input = shift;
		if (!is_number($input) && !$input) { return TRUE; }
	}
	
	my $collator = Unicode::Collate->new();
	
	for (my $i = 0; $i < @{$fieldList}; $i++) {
		my ($a1, $b1);
		if (is_array($a)) {
			$a1 = $a->[$fieldList->[$i]];
			$b1 = $b->[$fieldList->[$i]];
		} elsif (is_hash($a)) {
			$a1 = $a->{$fieldList->[$i]};
			$b1 = $b->{$fieldList->[$i]};
		} else {
			$a1 = $a;
			$b1 = $b;
		}
		
		# Handle undefined or blank vs. something
		if ($options->{nullsLast}) {
			if (isNothing($a1) && !isNothing($b1)) { return 1; }
			elsif (!isNothing($a1) && isNothing($b1)) { return -1; }
		} else {
			if (isNothing($a1) && !isNothing($b1)) { return -1; }
			elsif (!isNothing($a1) && isNothing($b1)) { return 1; }
		}
		# Handle numbers vs. non-numbers
		if ($options->{numbersLast}) {
			if (is_number($a1) && !is_number($b1)) { return 1; }
			elsif (!is_number($a1) && is_number($b1)) { return -1; }
		} else {
			if (is_number($a1) && !is_number($b1)) { return -1; }
			elsif (!is_number($a1) && is_number($b1)) { return 1; }
		}
		# Handle numbers
		no warnings 'numeric';
		if ($a1 <=> $b1) { return $a1 <=> $b1; }
		use warnings 'numeric';
		# Handle undefineds and blanks
		my $comp = $a1 cmp $b1;
		# Handle all others in a Unicode friendly way
		if ($a1 && $b1) { $comp = $collator->cmp($a1, $b1); }
		if ($comp) { return $comp; }
	}
	return 0;
}

sub max_length {
	my $object = shift || return;
	my $limit = shift || 8192;
	my $array = [];
	if (is_hash($object)) {
		@{$array} = values(%{$object});
	} elsif (is_array($object)) {
		$array = $object;
	} elsif (!ref($object)) {
		return length($object);
	} else { return; }
	my $max = 0;
	foreach my $item (@{$array}) {
		if ((length($item) > $max) && (length($item) <= $limit)) { $max = length($item); }
	}
	return $max;
}



#=====================================================

=head2 B<unique>

This will return an array of unique values from the given array. Values can be any combination of strings, arrays, or hashes.

 $array = unique($arrayhash);
 $array = unique($array);

=cut
#=====================================================
sub unique {
	my $array = shift || return;
	is_array($array) || return;
	
	my $map;
	foreach my $item (@{$array}) {
		my $value = makeDigest($item);
		$map->{$value} = $item;
	}
	my $newArray = [];
	@{$newArray} = values(%{$map});
	return $newArray;
}


#=====================================================

=head2 B<compare>

Compares two inputs to see if they are equivalent. Mostly useful for comparing hashes.

 if (compare($hashOrArrayOrString, $hashOrArrayOrString))

=cut
#=====================================================
sub compare {
	my $first = shift;
	my $second = shift;
	
	if ((is_hash($first) && is_hash($second)) || (is_array($first) && is_array($second))) {
		my $firstJSON = make_json($first, { compress => 1 });
		my $secondJSON = make_json($second, { compress => 1 });
		if ($firstJSON eq $secondJSON) { return TRUE; }
	}
	elsif ((is_number($first) && is_number($second)) && ($first == $second)) {
		return TRUE;
	}
	elsif ((is_text($first) && is_text($second)) && ($first eq $second)) {
		return TRUE;
	}
}

#=====================================================

=head2 B<compressRef>

Removes undefined and empty entries in variables. Should accept one or more scalars, arrays, and references to scalars, arrays, and hashes and navigate through all references.

 my $var = compressRef($var);

=cut
#=====================================================
sub compress_var { return compressRef(@_); }
sub compressRef {
	my @input = @_;
	my @output;
	foreach my $input (@input) {
		if (!ref($input)) {
			if ($input) { push(@output, $input); }
		} elsif (ref($input) eq 'SCALAR') {
			if ($$input) { push(@output, $input); }
		} elsif (ref($input) eq 'ARRAY') {
			if ($input && @{$input}) {
				my $outArray;
				foreach my $value (@{$input}) {
					if ($value) {
						my $subOut = compressArray($value);
						push(@{$outArray}, $subOut);
					}
				}
				if ($outArray && @{$outArray}) { push(@output, $outArray); }
			}
		} elsif (is_hash($input)) {
			my $subOut;
			my $cnt;
			while (my($name, $value) = each(%{$input})) {
				if ($value) {
					my $out = compressArray($value);
					if ($out) {
						$cnt++;
						$subOut->{$name} = $out;
					}
				}
			}
			if ($cnt) { push(@output, $subOut); }
		}
	}
	if (@output) { return @output; }
	else { return; }
}


#=====================================================

=head2 B<mergeHashes>

Merge any number of hashes into one hash. The first argument should be a reference to the hash that will get everything.
Any number of source hash references can be passed as additional arguments to be merged into the first one.
Later hash keys overwrite earlier ones.
Does not recurse.

 mergeHashes( $targetHashRef, $sourceHashRef, ... );
 my $targetHash = newHash($sourceHashRef, ...);

=cut
#=====================================================
sub merge_hashes { return mergeHashes(@_); }
sub mergeHashes {
	my $targetHash = shift;
	is_hash($targetHash) || return;
	
	foreach my $src (@_) {
		is_hash($src) || next;
		while (my ($key, $value) = each(%{$src})) {
			if ($key =~ /^(?:can|is|does|has|should)(?:_|[A-Z])/) {
				$targetHash->{$key} = $value;
			} elsif (defined($value)) {
				$targetHash->{$key} = $value;
			}
		}
	}
}
sub newHash {
	my $targetHash = {};
	mergeHashes($targetHash, @_);
	return $targetHash;
}


#=====================================================

=head2 B<copyRef>

Returns a copy of the given scalar, array, or hash. Recurses through arrays and hashes.

=cut
#=====================================================
sub copyRef {
	my $input = shift;
	my $limit = shift;
	if ($limit >= 20) { return $input; }
	
	if (ref($input) eq 'HASH') {
		my $newHash;
		while (my($name, $value) = each(%{$input})) {
			$newHash->{$name} = copyRef($value, $limit + 1);
		}
		return $newHash;
	} elsif (ref($input) eq 'ARRAY') {
		my $newArray = [];
		foreach my $value (@{$input}) {
			push(@{$newArray}, copyRef($value, $limit + 1));
		}
		return $newArray;
	} elsif (ref($input) eq 'SCALAR') {
		my $newScalar = ${$input};
		return \$newScalar;
	} else {
		return $input;
	}
}


#=====================================================

=head2 B<joinRef>

Joins array values and hash keys.
Joins arrayHash values with the given key.
Returns scalars and scalar refs as their value.

 my $text = joinRef($ref, $delimiter);
 my $text = joinRef($arrayHash, $key, $delimiter);

=cut
#=====================================================
sub joinRef {
	my $reference = shift || return;
	my $delimiter = shift || ',';
	my $delimiter2 = shift || ',';
	
	my $answer;
	if (!ref($reference)) { $answer = $reference; }
	elsif (ref($reference) eq 'SCALAR') { $answer = $$reference; }
	elsif (is_array_hash($reference)) {
		my $tempArray = to_array($reference, $delimiter);
		$answer = join($delimiter2, @{$tempArray});
	}
	elsif (ref($reference) eq 'ARRAY') { $answer = join($delimiter, @{$reference}); }
	elsif (ref($reference) eq 'HASH') { $answer = join($delimiter, keys(%{$reference})); }
	return $answer;
}


#=====================================================

=head2 B<diff>

Returns a hash with the key value pairs from the second hash.

 my $diff = diff($hash1, $hash2);

=cut
#=====================================================
sub diff {
	my $old = shift || {};
	my $new = shift || {};
	if (!is_hash($old) || !is_hash($new)) { return; }
	
	my @keys = (keys(%{$old}), keys(%{$new}));
	my $keys = uniqueArray(\@keys);
	my $diff = {};
	foreach my $key (@{$keys}) {
		if ((!exists($old->{$key}) || !defined($old->{$key})) && (!exists($new->{$key}) || !defined($new->{$key}))) { next; }
		elsif ((exists($old->{$key}) && defined($old->{$key})) && (!exists($new->{$key}) || !defined($new->{$key}))) { $diff->{$key} = undef; }
		elsif ((!exists($old->{$key}) || !defined($old->{$key})) && (exists($new->{$key}) && defined($new->{$key}))) { $diff->{$key} = $new->{$key}; }
		elsif (is_hash($old->{$key}) && is_hash($new->{$key}) && compare($old->{$key}, $new->{$key})) { next; }
		elsif (is_array($old->{$key}) && is_array($new->{$key}) && compare($old->{$key}, $new->{$key})) { next; }
		elsif (($old->{$key} == $new->{$key}) && ($old->{$key} eq $new->{$key})) {}
		else { $diff->{$key} = $new->{$key}; }
	}
	return $diff;
}


#=====================================================

=head2 B<checkId>

Filters out bogus input for ids. Pass it any input and it will return a number only if the input is a valid number or can be decoded.

 my $id = checkId($encId || $id);
 checkId($id) || return;

=cut
#=====================================================
sub check_id { return checkId(@_); }
sub checkId {
	my $identifier = shift || return;
	
	my $id;
	if ($identifier =~ /^[02-9a-km-z]{7}$/) {
		$id = decodeId($identifier);
	} elsif ($identifier =~ /^[0-9a-zA-Z]{6}$/) {
		$id = decodeId($identifier);
	} elsif ($identifier =~ /^\d+$/) {
		if ($id < 2147483647) { $id = $identifier; }
	}
	
	return $id;
}


#=====================================================

=head2 B<encodeId>

Encode a seven character base-36 id.

 $idEnc = encodeId($id);

=cut
#=====================================================
sub encode_id { return encodeId(@_); }
sub encodeId {
    my $num = shift;
	# pad with zeros and reverse
	$num = reverse(sprintf("%010d1",$num));
	# convert to base 34
	my @digit = (0,2..9,'a'..'k','m'..'z');
	my $dignum = @digit;
	my $result = '';
	while ($num>0) {
		substr($result,0,0) = $digit[ $num % $dignum ];
		$num = int($num / $dignum);
	}
	return length $result ? $result : $digit[0];
}


#=====================================================

=head2 B<encode6Id>

Encode a six character base-62 id.

 $idEnc = encode6Id($id);

=cut
#=====================================================
sub encode6_id { return encode6Id(@_); }
sub encode6Id {
    my $num = shift;
	# pad with zeros and reverse
	$num = reverse(sprintf("%010d1",$num));
	# convert to base 62
	my @digit = (0..9,'a'..'z','A'..'Z');
	my $dignum = @digit;
	my $result = '';
	while ($num>0) {
		substr($result,0,0) = $digit[ $num % $dignum ];
		$num = int($num / $dignum);
	}
	return length $result ? $result : $digit[0];
}


#=====================================================

=head2 B<decodeId>

Decode a seven character base-36 id or the older six character base-62 id.

 $id = decodeId($idEnc);
 
=cut
#=====================================================
sub decode_id { return decodeId(@_); }
sub decodeId {
    my $str = reverse shift;
    my $output;
    
	if ($str =~ /\b([0a-z2-9]{7})\b/) {
		my @digit = (0,2..9,'a'..'k','m'..'z');
		my $dignum = @digit;
		my %trans;
		@trans{@digit} = 0..$#digit;
		my $result = 0;
		while (length $str) {
			$result *= $dignum;
			$result += $trans{chop $str};
		}
		my $ret = reverse($result);
		chop($ret);
		$output = int($ret);
	} elsif ($str =~ /\b([a-zA-Z0-9]{6})\b/) {
		if (my ($alpha) = $str =~ /([n-z])$/) {
			$alpha =~ tr/a-z/n-za-m/;
			$str =~ s/.$/$alpha/;
		}
		my @digit = (0..9,'a'..'z','A'..'Z');
		my $dignum = @digit;
		my %trans;
		@trans{@digit} = 0..$#digit;
		my $result = 0;
		while (length $str) {
			$result *= $dignum;
			$result += $trans{chop $str};
		}
		my $ret = reverse($result);
		chop($ret);
		$output = int($ret);
	}
    
    return $output;
}


#=====================================================

=head2 B<uniqueKey>

=cut
#=====================================================
sub unique_key { return uniqueKey(@_); }
sub uniqueKey {
	my $time = time;
	my $num = sprintf("%s%04d", substr($time, -5), int(rand(10000)));
	my $ascii = $num % 52 + 65;
	if ($ascii > 90) { $ascii += 6; }
	my $key = chr($ascii);
	$num = int($num / 52);
	while ($num > 0) {
		my $ascii = $num % 62 + 48;
		if ($ascii > 57) { $ascii += 7; }
		if ($ascii > 90) { $ascii += 6; }
		$key .= chr($ascii);
		$num = int($num / 62);
	}
	return $key;
}


#=====================================================

=head2 B<generateKey>

=cut
#=====================================================
sub generateKey {
	my $time = time;
	my $source = sprintf("%s%06d", substr($time, -5), int(rand(1000000)));
	my $type = shift || 'b64';
	
	my $ctx = Digest::MD5->new;
	$ctx->add($source);
	
	my $digest = $ctx->b64digest;
	$digest =~ s/\+/-/g;
	return $digest;
}


#=====================================================

=head2 B<smmd5_2008>

Encrypt text as smmd5 2008.

 $encrypted = smmd5_2008($password, $salt1, $salt2);

=cut
#=====================================================
sub smmd5_2008 {
	my $key = shift || return;
	my $salt1 = shift;
	my $salt2 = shift;
	
	my $ctx = Digest::MD5->new;
	my $cnt = 32768;
	while ($cnt) {
		$ctx->add($key . $salt1);
		$key = $ctx->hexdigest;
		$ctx->reset;
		$ctx->add($key . $salt2);
		$key = $ctx->b64digest;
		$ctx->reset;
		$cnt--;
	}
	
	return $key;
}


#=====================================================

=head2 B<smsha2012>

Encrypt text as sha.

 $encrypted = smsha2012($password, $salt1, $salt2);

=cut
#=====================================================
sub smsha2012 {
	my $pass = shift || return;
	my $salt1 = shift;
	my $salt2 = shift;
	
	my $key = $pass . $salt1 . $salt2;
	
	my $sha = Digest::SHA->new(256);
	$sha->add($key);
	my $hash = $sha->b64digest;
	
	return $hash;
}


#=====================================================

=head2 B<makeDigest>

Make a B64 digest out of a string, array, or hash.

=cut
#=====================================================
sub makeDigest {
	my $input = shift || return;
	if (is_hash($input) || is_array($input)) {
		$input = make_json($input, { compress => 1 });
	}
	elsif (!is_text($input)) { return; }
	
	my $sha = Digest::MD5->new();
	$sha->add($input);
	return $sha->b64digest;
}


#=====================================================
#=====================================================
# Array Functions
#=====================================================
#=====================================================

# sub add_to_array(_array, _item) {
# 	_array.push(_item);
# 	var newArray = uniqueArray(_array);
# 	return newArray;
# }
# 
# sub remove_from_array(_array, _item) {
# 	var newArray = new Array();
# 	for (var i = 0; i < _array.length; i++) {
# 		if (_array[i] != _item) { newArray.push(_array[i]); }
# 	}
# 	return newArray;
# }
# 
# sub arrayToList(_array) {
# 	var newArray = uniqueArray(_array);
# 	var list = newArray.join(', ');
# 	return list;
# }
# 
# sub listToArray(_list) {
# 	var newArray = new Array();
# 	if (_list) {
# 		var _array = _list.split(/\s*,\s*/);
# 		if (_array) {
# 			newArray = uniqueArray(_array);
# 		}
# 	}
# 	return newArray;
# }
# 
# sub arrayContains(_array, _string) {
# 	if (_array && _string) {
# 		for (var i = 0; i < _array.length; i++) {
# 			if (_array[i] == _string) { return true; }
# 		}
# 	}
# 	return false;
# }
# 
# sub combineArrays(_array1, _array2) {
# 	if (_array1 && _array2) {
# 		for (var i = 0; i < _array2.length; i++) {
# 			_array1.push(_array2[i]);
# 		}
# 	}
# }


#=====================================================

=head2 B<normalize>

Removes extra white space and reduce to lowercase letters, numbers, and spaces in scalars, arrays, and hashes.

 $ref = normalize($ref, $shouldStripPeriods);

=cut
#=====================================================
sub normalize {
	my $input = shift;
	defined($input) || return;
	my $isMinimal = shift;
	my $output;
	
	if (!ref($input)) { $output = _normalize($input, $isMinimal); }
	elsif (ref($input) eq 'SCALAR') { $output = _normalize(${$input}, $isMinimal); }
	elsif (ref($input) eq 'ARRAY') {
		$output = [];
		foreach my $value (@{$input}) {
			push(@{$output}, _normalize($value, $isMinimal));
		}
	} elsif (ref($input) eq 'HASH') {
		while (my($name, $value) = each(%{$input})) {
			$output->{$name} = _normalize($value, $isMinimal);
		}
	}
	
	return $output;
}

sub _normalize {
	my $input = lc(shift);
	defined($input) || return;
	my $isMinimal = shift;
	$input = unidecode($input);
	$input =~ s/[^a-z0-9.\s_-]//g;
	if ($isMinimal) { $input =~ s/[\s\._-]+/-/g; }
	else { $input =~ s/[\s_-]+/-/g; }
	$input =~ s/(?:^-+|-+$)//g;
	return $input;
}

#=====================================================

=head2 B<strip>

Removes leading and trailing characters from scalars, arrays, and hashes. Defaults to stripping whitespace.

 $ref = strip($ref, $charToStrip);

=cut
#=====================================================
sub strip {
	my $input = shift || return;
	my $char = shift || '\s';
	$char .= '+';
	
	if (!ref($input)) {
		$input =~ s/(?:^$char|$char$)//g;
	} elsif (ref($input) eq 'SCALAR') {
		${$input} =~ s/(?:^$char|$char$)//g;
	} elsif (ref($input) eq 'ARRAY') {
		foreach my $value (@{$input}) {
			if (!ref($value)) { $value =~ s/(?:^$char|$char$)//g; }
		}
	} elsif (is_hash($input)) {
		while (my($name, $value) = each(%{$input})) {
			if (!ref($value)) {
				$value =~ s/(?:^$char|$char$)//g;
				$input->{$name} = $value;
			}
		}
	}
	
	return $input;
}

#=====================================================

=head2 B<stripExtraWhiteSpace>

Removes leading and trailing white space and reduces contiguous white space characters to a single space in scalars, arrays, and hashes.

 $ref = stripExtraWhiteSpace($ref);

=cut
#=====================================================
sub strip_extra_white_space { return stripExtraWhiteSpace(@_); }
sub stripExtraWhiteSpace {
	my $input = shift || return;
	
	if (!ref($input)) {
		$input =~ s/(?:^\s+|\s+$)//g;
		$input =~ s/\s+/ /g;
	} elsif (ref($input) eq 'SCALAR') {
		${$input} =~ s/(?:^\s+|\s+$)//g;
		${$input} =~ s/\s+/ /g;
	} elsif (ref($input) eq 'ARRAY') {
		foreach my $value (@{$input}) {
			if (!ref($value)) {
				$value =~ s/(?:^\s+|\s+$)//g;
				$value =~ s/\s+/ /g;
			}
		}
	} elsif (is_hash($input)) {
		while (my($name, $value) = each(%{$input})) {
			if (!ref($value)) {
				$value =~ s/(?:^\s+|\s+$)//g;
				$value =~ s/\s+/ /g;
				$input->{$name} = $value;
			}
		}
	}
	
	return $input;
}


#=====================================================

=head2 B<stripControlCharacters>

Removes control characters except for Tab, LF, and CR. Pass a second argument to strip all control characters, even Tab, LF, and CR.

=cut
#=====================================================
sub stripControlCharacters {
	my $input = shift || return;
	my $all = shift;
	
	if (!ref($input)) {
		$input = _stripControlCharacters($input, $all);
	} elsif (ref($input) eq 'SCALAR') {
		${$input} = _stripControlCharacters(${$input}, $all);
	} elsif (ref($input) eq 'ARRAY') {
		foreach my $value (@{$input}) {
			if (!ref($value)) {
				$value = _stripControlCharacters($value, $all);
			}
		}
	} elsif (is_hash($input)) {
		while (my($name, $value) = each(%{$input})) {
			if (!ref($value)) {
				$input->{$name} = _stripControlCharacters($value, $all);
			}
		}
	}
	
	return $input;
}

sub _stripControlCharacters {
	my $input = shift || return;
	my $all = shift;
	if ($all) {
		$input =~ s/[\x00-\x1f\x7f]//g;
	} else {
		$input =~ s/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]//g;
	}
	return $input;
}

#=====================================================

=head2 B<cleanFilename>

 $ref = cleanFilename($ref);

=cut
#=====================================================
sub clean_filename { return cleanFilename(@_); }
sub cleanFilename {
	my $input = shift || return;
	
	if (!ref($input)) {
		$input = _cleanFilename($input);
	} elsif (ref($input) eq 'SCALAR') {
		${$input} = _cleanFilename(${$input});
	} elsif (ref($input) eq 'ARRAY') {
		foreach my $value (@{$input}) {
			if (!ref($value)) {
				$value = _cleanFilename($value);
			}
		}
	} elsif (is_hash($input)) {
		while (my($name, $value) = each(%{$input})) {
			if (!ref($value)) {
				$input->{$name} = _cleanFilename($value);
			}
		}
	}
	
	return $input;
}

sub _cleanFilename {
	my $input = shift || return;
	$input =~ s/(?:^[.-_ ]+|[^\w.-_ ]| +$)//ig;
	$input =~ s/[ _]+/_/g;
	return $input;
}

#=====================================================

=head2 B<stripHTML>

 my $text = stripHTML($html, {
	useNewlines			=> 1,
	convertLinks		=> 1,
	preserveLinks		=> 1,
	convertEntities		=> 1,
	escapeForJS			=> 1,
	preserveNewlines	=> 1
 });

=cut
#=====================================================
sub strip_html { return stripHTML(@_); }
sub stripHTML {
	my $html = shift || return;
	my $settings = shift;
	
	my $break = ' ';
	if (!$settings->{preserveNewlines}) {
		# strip newlines
		$html =~ s/[\r\n]+//g;
	}
	# strip blocks of html content that shouldn't be here
	$html =~ s/<style.*?<\/\s*style\s*>//sig;
	$html =~ s/<script.*?<\/\s*script\s*>//sig;
	$html =~ s/<\!\[CDATA\[.*?\]\]>//sig;
	$html =~ s/<\!--.*?-->//sig;
	
	if ($settings->{useNewlines} || $settings->{use_newlines}) {
		$break = "\n";
		# Replace lists
		$html =~ s/<\/li>\s*<li\b.*?>/\n  * /sig;
		$html =~ s/<li\b.*?>/\n  * /ig;
		$html =~ s/<\/li>/\n/ig;
	} else {
		# Replace lists
		$html =~ s/<\/li>\s*<li\b.*?>/, /sig;
		$html =~ s/(?:<\/li>|<li\b.*?>)/ /ig;
	}
	
	if ($settings->{convertLinks} || $settings->{convert_links}) {
		$html =~ s/<a .*?href="(.+?)".*?>(.*?)<\/a>/stripHTMLLink($1, $2)/eig;
	}
	if ($settings->{preserveLinks}) {
		$html =~ s/<a .*?href="((?:https?:\/\/|mailto:).+?)".*?>(.*?)<\/a>/\[stripHTML::preservedTag\]a href="$1">$2\[stripHTML::preservedTag\]\/a>/ig;
	}
	
	$html =~ s/(?:<br\b.*?\/?>|<\/div>|<\/p>)/$break/ig;
	$html =~ s/<.*?>//g;
	$html =~ s/\[stripHTML::preservedTag\]/</g;
	
	if ($settings->{convertEntities} || $settings->{convert_entities}) {
		$html = html_entities_to_text($html);
	}
	
	if ($settings->{escapeForJS} || $settings->{escape_for_js}) {
		$html =~ s/'/\\'/g;
	}
	
	return $html;
}
sub stripHTMLLink {
	my $url = shift;
	my $title = shift;
	if ($url && !$title) { return $url; }
	elsif (!$url && $title) { return $title; }
	
	# Mail links
	if ($url =~ /^mailto:(.*?)(?:\?|$)/) {
		my $email = $1;
		if (lc($email) eq lc($title)) { return $email; }
		else { return "$title [ $email ]"; }
	}
	# Valid links
	elsif ($url =~ /^(https?|file|ftp|feed|mms|news|rtsp|webcal):/i) {
		# Only return URL if title is similar to URL
		my $temp = $title;
		$temp =~ s/^(https?|file|ftp|feed|mms|news|rtsp|webcal):\/+//i;
		$temp =~ s/\/.*//;
		if (($url =~ /$title/i) && isHostname($temp)) { return $url; }
		else { return "$title [ $url ]"; }
	}
	# Unknown link - Could be Javascript or something else
	return $title;
}

#=====================================================

=head2 B<stripOutside>

 * Converts and strips HTML
 * Converts HTML entities
 * Strips control characters
 * Strips content in parentheses, brackets, and braces
 * Strips outside punctuation and whitespace

 my $field = stripOutside($field);
 my $field = stripOutside($field, 'title');	# Leaves starting # $. Leaves trailing ! % . ?
 my $field = stripOutside($field, 'period');	# Leaves trailing .
 my $field = stripOutside($field, 'colon');	# Leaves leading or trailing :

=cut
#=====================================================
sub stripOutside {
	my $string = shift || return;
	my $mode = shift;
	
	$string = stripHTML($string);
	$string = from_html_entities($string);
	$string = stripControlCharacters($string);
	$string =~ s/\(.*?\)//g;
	$string =~ s/\[.*?\]//g;
	$string =~ s/\{.*?\}//g;
	# All punctuation: [-!"#\$\%\&'()*+,.\/:;<=>?\@[\\\]^_`{|}~]
	# All punctuation: [-!"#\$\%\&'*+,.\/:;<=>?\@\\^_`|~]
	if ($mode eq 'title') {
		# Strip backslashes, any punctuation from the start, and most punctuation from the end
		$string =~ s/(?:\\|^[-!\%\&*+,.\/:;<=>?\@\\^_`|~\s]+|[-#\$\&*+,\/:;<=>\@\\^_`|~\s]+$)//g;
	} elsif ($mode eq 'period') {
		# Strip backslashes, any punctuation from the start, and any punctuation except . from the end
		$string =~ s/(?:\\|^[\W_]+|[-!"#\$\%\&'*+,\/:;<=>?\@\\^_`|~\s]+$)//g;
	} elsif ($mode eq 'colon') {
		# Strip backslashes, any punctuation from the start except colon,
		#    and any punctuation except : and . from the end
		$string =~ s/(?:\\|^[-!"#\$\%\&'*+,\.\/;<=>?\@\\^_`|~]+|[-!"#\$\%\&'*+,\/;<=>?\@\\^_`|~]+$)//g;
	} else {
		# Strip backslashes and any punctuation from the start or end
		$string =~ s/(?:\\|^[\W_]+|[\W_]+$)//g;
	}
	return $string;
}


#=====================================================

=head2 B<insertData>

Recursively replaces ${key} variables in any string in a complex object with the supplied hash of key/values.

 my $text = insertData("The ${adjective} brown ${noun}", {
	adjective	=> 'quick',
	noun		=> 'fox'
 } );

=cut
#=====================================================
sub insertData {
	my $template = shift;
	my $data = shift;
	my $depth = shift;
	if ($depth > 20) { return; }
	is_hash($data) || return $template;
	
	if (ref($template) eq 'SCALAR') {
		my $value = _insertDataIntoString(${$template}, $data);
		return ${$value};
	}
	elsif (is_array($template)) {
		my $newTemplate = [];
		foreach my $value (@{$template}) {
			push(@{$newTemplate}, insertData($value, $data, $depth+1));
		}
		return $newTemplate;
	}
	elsif (is_hash($template)) {
		my $newTemplate = {};
		while (my($key, $value) = each(%{$template})) {
			$newTemplate->{$key} = insertData($value, $data, $depth+1);
		}
		return $newTemplate;
	}
	elsif (!ref($template)) { return _insertDataIntoString($template, $data); }
	return $template;
}
sub _insertDataIntoString {
	my $template = shift;
	my $data = shift;
	$template =~ s/\$\{(\w+)\}/$data->{$1}/eg;
	return $template;
}

#=====================================================

=head2 B<summarize>

 my $summary = summarize($html, $limit, $type);

=cut
#=====================================================
sub summarize {
	my $html = shift || return;
	my $limit = shift || return;
	my $type = shift || 'word';
	my $oneLine = shift;
	my $useNewlines = 1;
	if ($oneLine) { undef($useNewlines); }
	
	my $text = stripHTML($html, { useNewlines => 1 });
	
	my $answer;
	my $cnt = 0;
	while ($text && ($cnt < $limit)) {
		my $part;
		if ($type eq 'paragraph') {
			if (($part) = $text =~ /^(.+?\n+)/) { $text = $'; }
		} elsif ($type eq 'sentence') {
			if (($part) = $text =~ /^(.+?[\.!\?]+(?:\s+|&\w+;))/) { $text = $'; }
		} elsif ($type eq 'word') {
			if (($part) = $text =~ /^(.+?\s+)/) { $text = $'; }
		}
		unless ($part) { $answer .= $text; last; }
		$answer .= $part;
		$cnt++;
	}
	
	if ($type eq 'paragraph') { $answer =~ s/\n/<br \/>\n/g; }
	elsif (($type eq 'word') && ($answer !~ /[\.!\?]\s*$/)) { $answer .= '...'; }
	
	return $answer;
}


#=====================================================

=head2 B<context>

Returns text of the length specified surrounding the given search term. An optional third argument of size lets you specify the length of the summary.

 my $summary = context($text, $search);
 my $summary = context($text, $search, $size);

=cut
#=====================================================
sub context {
	my $text = shift || return;
	my $search = shift;
	my $length = shift || 256;
	
	my ($first) = split(/\s*\|/, $text);
	my $summary = $first;
	
	if (length($first) > $length) {
		if ($search && ($first =~ /$search/ig)) {
			my $pos = pos($first);
			my $offset = int(($length - length($search)) / 2) - 2;
			if ($pos < $offset) {
				$summary = substr($first, 0, ($length-4));
				$summary =~ s/\s+(\S+)?$/ .../;
			} elsif (($pos+$offset+length($search)) > length($first)) {
				$summary = substr($first, ($pos - $offset), ($length-4));
				$summary =~ s/^(\S+)?\s+/... /;
			} else {
				$summary = substr($first, ($pos - $offset), ($length-8));
				$summary =~ s/^(\S+)?\s+/... /;
				$summary =~ s/\s+(\S+)?$/ .../;
			}
		} else {
			$summary = substr($first, 0, ($length-4));
			$summary =~ s/\s+\S+$/ .../;
		}
	}
	
	return $summary;
}


#=====================================================

=head2 B<to_camel_case>

Recurses through objects converting hash keys. Only converts array and scalar values at the top level.

 $camelCaseHash = to_camel_case($hash);		# Converts hash keys to camel case
 $camelCaseArray = to_camel_case($array);		# Converts array values to camel case
 $camelCaseScalar = to_camel_case($scalar);	# Converts scalar to camel case

=cut
#=====================================================
sub to_camel_case {
	my $input = shift;
	my $limit = shift;
	if ($limit >= 20) { return $input; }
	
	if (ref($input) eq 'HASH') {
		# Always do hash keys and recurse to find more hash keys
		my $newHash = {};
		while (my($name, $value) = each(%{$input})) {
			my $newName = _to_camel_case_scalar($name);
			$newHash->{$newName} = to_camel_case($value, $limit + 1);
		}
		return $newHash;
	} elsif ($limit) {
		# If farther in, search arrays for more hashes. Otherwise, return.
		if (ref($input) eq 'ARRAY') {
			my $newArray = [];
			foreach my $value (@{$input}) {
				my $newValue = to_camel_case($value, $limit + 1);
				push(@{$newArray}, $newValue);
			}
			return $newArray;
		} else {
			return $input;
		}
	} else {
		# First level, process scalars, array values, and hash keys
		if (ref($input) eq 'ARRAY') {
			my $newArray = [];
			foreach my $value (@{$input}) {
				my $newValue = $value;
				if ((ref($value) eq 'SCALAR') || !ref($value)) {
					$newValue = _to_camel_case_scalar($value);
				} else {
					$newValue = to_camel_case($value, $limit + 1);
				}
				push(@{$newArray}, $newValue);
			}
			return $newArray;
		} elsif ((ref($input) eq 'SCALAR') || !ref($input)) {
			return _to_camel_case_scalar($input);
		} else {
			return $input;
		}
	}
}

sub _to_camel_case_scalar {
	my $input = shift || '';
	my $scalar = $input;
	if (ref($input) eq 'SCALAR') { $scalar = ${$input}; }
	$scalar =~ s/user_oid$/userId/g;
	$scalar =~ s/_(css|html|ics|ip|json|oid|php|rss|smtp|smv|sql|ssl|url|utf|xml|xslt?)(_|$)/\U$1$2/g;
	$scalar =~ s/([a-z0-9])_([a-z0-9])/$1\u$2/g;
	if (ref($input) eq 'SCALAR') { return \$scalar; }
	return $scalar;
}

sub from_camel_case {
#=====================================================

=head2 B<from_camel_case>

Recurses through objects converting hash keys. Only converts array and scalar values at the top level.

=cut
#=====================================================
	my $input = shift;
	my $limit = shift;
	if ($limit >= 20) { return $input; }
	
	if (ref($input) eq 'HASH') {
		# Always do hash keys and recurse to find more hash keys
		my $newHash = {};
		while (my($name, $value) = each(%{$input})) {
			my $newName = _from_camel_case_scalar($name);
			$newHash->{$newName} = from_camel_case($value, $limit + 1);
		}
		return $newHash;
	} elsif ($limit) {
		# If farther in, search arrays for more hashes. Otherwise, return.
		if (ref($input) eq 'ARRAY') {
			my $newArray = [];
			foreach my $value (@{$input}) {
				my $newValue = from_camel_case($value, $limit + 1);
				push(@{$newArray}, $newValue);
			}
			return $newArray;
		} else {
			return $input;
		}
	} else {
		# First level, process scalars, array values, and hash keys
		if (ref($input) eq 'ARRAY') {
			my $newArray = [];
			foreach my $value (@{$input}) {
				my $newValue = $value;
				if ((ref($value) eq 'SCALAR') || !ref($value)) {
					$newValue = _from_camel_case_scalar($value);
				} else {
					$newValue = from_camel_case($value, $limit + 1);
				}
				push(@{$newArray}, $newValue);
			}
			return $newArray;
		} elsif ((ref($input) eq 'SCALAR') || !ref($input)) {
			return _from_camel_case_scalar($input);
		} else {
			return $input;
		}
	}
}

sub _from_camel_case_scalar {
	my $input = shift || '';
	my $scalar = $input;
	if (ref($input) eq 'SCALAR') { $scalar = ${$input}; }
	$scalar =~ s/userId$/user_oid/g;
	$scalar =~ s/(CSS|HTML|IP|ICS|JSON|OID|PHP|RSS|SMTP|SMV|SQL|SSL|URL|UTF|XML|XSLT?)/_\L$1/g;
	$scalar =~ s/([a-z])([A-Z0-9])/$1_\l$2/g;
	if (ref($input) eq 'SCALAR') { return \$scalar; }
	return $scalar;
}

sub is_camel_case {
	my $text = shift;
	if ($text =~ /^[a-z]+[A-Z][a-zA-Z0-9]+$/) { return TRUE; }
}

sub camel_case {
	my $text = lc(shift);
	$text =~ s/[^a-z0-9]+([a-z])/\u$a/g;
	$text =~ s/[^a-z0-9]+//g;
	return $text;
}

sub kebab_case {
	my $text = lc(shift);
	if (is_camel_case($text)) {
		$text =~ s/([A-Z]+)/-\L$1/g;
	} else {
		$text = lc($text);
		$text =~ s/[^a-z0-9]+/-/g;
		$text =~ s/--+/-/g;
	}
	return $text;
}

sub snake_case {
	my $text = shift;
	if (is_camel_case($text)) {
		$text =~ s/([A-Z]+)/_\L$1/g;
	} else {
		$text = lc($text);
		$text =~ s/[^a-z0-9]+/_/g;
		$text =~ s/__+/_/g;
	}
	return $text;
}


#=====================================================

=head2 B<toLatLong>

 my ($lat, $long) = toLatLong( 36.1443, -86.8144 );
 my ($lat, $long) = toLatLong( '36.1443, -86.8144' );
 my ($lat, $long) = toLatLong( '(-86.8144,36.1443)' );	# PostgreSQL point
 my ($lat, $long) = toLatLong( [36.1443, -86.8144] );
 my ($lat, $long) = toLatLong( { lat => 36.1443, long => -86.8144 } );
 my ($lat, $long) = toLatLong( { latitude => 36.1443, longitude => -86.8144 } );
 my ($lat, $long) = toLatLong( { coordinates => '(-86.8144,36.1443)' } );

=cut
#=====================================================
sub toLatLong {
	my $coords = shift || return;
	my $long = shift;
	my $latitude;
	my $longitude;
	if (is_number($coords) && is_number($long)) {
		$latitude = $coords;
		$longitude = $long;
	} elsif (is_text($coords)) {
		if ($coords =~ /\(/) { # PostgreSQL point is x, y - long, lat
			$coords =~ s/^\(|\)$//g;
			my ($long, $lat) = split(/\s*,\s*/, $coords);
			$latitude = $lat;
			$longitude = $long;
		} else {
			my ($lat, $long) = split(/\s*,\s*/, $coords);
			$latitude = $lat;
			$longitude = $long;
		}
	} elsif (is_hash_key($coords, 'lat')) {
		$latitude = $coords->{lat};
		$longitude = $coords->{long} || $coords->{lng};
	} elsif (is_hash_key($coords, 'latitude')) {
		$latitude = $coords->{latitude};
		$longitude = $coords->{longitude};
	} elsif (is_hash_key($coords, 'coordinates')) {
		($latitude, $longitude) = toLatLong($coords->{coordinates});
	} elsif (is_array($coords) && is_number($coords->[0]) && is_number($coords->[1])) {
		$latitude = $coords->[0];
		$longitude =  $coords->[1];
	}
	
	if (!is_number($latitude) || !is_number($longitude)) { return; }
	if (($latitude < -90) || ($latitude > 90)) { return; }
	if (($longitude < -180) || ($longitude > 180)) { return; }
	
	return ($latitude, $longitude);
}

#=====================================================

=head2 B<toLatLongHash>

 my $latLongHash = toLatLongHash(36.1443, -86.8144);
 my $latLongHash = toLatLongHash('36.1443,-86.8144');
 my $latLongHash = toLatLongHash('(36.1443,-86.8144)');	# PostgreSQL point
 my $latLongHash = toLatLongHash( [36.1443, -86.8144] );
 my $latLongHash = toLatLongHash( { lat => 36.1443, long => -86.8144 } );
 my $latLongHash = toLatLongHash( { latitude => 36.1443, longitude => -86.8144 } );	# Preserves hash

Returns:
 { latitude => 36.1443, longitude => -86.8144 }

 my $latLongArrayHash = toLatLongHash( ['36.1443,-86.8144', '(36.137,-86.8307)'] );
 my $latLongArrayHash = toLatLongHash( [ { lat => 36.1443, long => -86.8144 }, { lat => 36.137, long => -86.8307 } ] );
 my $latLongArrayHash = toLatLongHash( [ { latitude => 36.1443, longitude => -86.8144 }, ... ] );	# Preserves hash

Returns:
 [ { latitude => 36.1443, longitude => -86.8144 }, { latitude => 36.137, longitude => -86.8307 } ]

=cut
#=====================================================
sub toLatLongHash {
	my $coords = shift || return;
	my $long = shift;
	if (is_number($coords) && is_number($long)) {
		return {
			latitude	=> $coords,
			longitude	=> $long
		};
	} elsif (is_text($coords)) {
		my ($lat, $long) = toLatLong($coords);
		return {
			latitude	=> $lat,
			longitude	=> $long
		};
	} elsif (is_array($coords) && is_number($coords->[0])) {
		return {
			latitude	=> $coords->[0],
			longitude	=> $coords->[1]
		};
	} elsif (is_array($coords) && is_text($coords->[0])) {
		my $newCoords = [];
		foreach my $coord (@{$coords}) {
			my ($lat, $long) = toLatLong($coord);
			push(@{$newCoords}, {
				latitude	=> $lat,
				longitude	=> $long
			});
		}
		return $newCoords;
	} elsif (is_hash_key($coords, 'lat')) {
		return {
			latitude	=> $coords->{lat},
			longitude	=> $coords->{long} || $coords->{lng}
		};
	} elsif (is_hash_key($coords, 'latitude')) {
		return $coords;
	} elsif (is_array_hash($coords) && is_hash_key($coords->[0], 'lat')) {
		my $newCoords = [];
		foreach my $coord (@{$coords}) {
			push(@{$newCoords}, {
				latitude	=> $coords->{lat},
				longitude	=> $coords->{long} || $coords->{lng}
			});
		}
		return $newCoords;
	} elsif (is_array_hash($coords) && is_hash_key($coords->[0], 'latitude')) {
		return $coords;
	}
	
}

#=====================================================

=head2 B<toCoordinates>

Takes the same input as toLatLong but returns the lat/long as a PostgreSQL point.

=cut
#=====================================================
sub toCoordinates {
	my ($lat, $long) = toLatLong(@_);
	if (is_number($lat) && is_number($long)) {
		return '(' . $long . ',' . $lat . ')';
	}
}

#=====================================================

=head2 B<distanceInMiles>

 my $miles = distanceInMiles($coordinates1, $coordinates2);
 my $miles = distanceInMiles($lat1, $long1, $lat2, $long2);

=cut
#=====================================================
sub distanceInMiles {
	my ($coord1, $coord2, $coord3, $coord4) = @_;
	if (is_number($coord1) && is_number($coord2) && is_number($coord3) && is_number($coord4)) {
		return _distanceInMiles($coord1, $coord2, $coord3, $coord4);
	} elsif (is_text($coord1) && is_text($coord2)) {
		my ($lat1, $long1) = toLatLong($coord1);
		my ($lat2, $long2) = toLatLong($coord2);
		return _distanceInMiles($lat1, $long1, $lat2, $long2);
	}
}
sub _distanceInMiles {
	my ($lat1, $long1, $lat2, $long2) = @_;
	my $r = 3956;
	
	my $dlong = deg2rad($long1) - deg2rad($long2);
	my $dlat  = deg2rad($lat1) - deg2rad($lat2);
	my $a = sin($dlat/2)**2 + cos(deg2rad($lat1)) * cos(deg2rad($lat2))	* sin($dlong/2)**2;
	my $c = 2 * (asin(sqrt($a)));
	my $dist = $r * $c;
	return $dist;
}


#=====================================================

=head2 B<lookUpIP>

=cut
#=====================================================
sub lookUpIP {
	my $ip = shift || return;
	isIPv4($ip) || return;
# 	my $apiKey = 'b6e5cd50ec721a27aac617c5f3742ddb45acf1c9db5625e7a7dc5c5b592904d7';
# 	my $url = 'http://api.ipinfodb.com/v3/ip-city/?format=json&key=' . $apiKey . '&ip=' . $ip;
# 	my $jsonText = get_url($url);
# 	my $json = parse_json($jsonText);
# 	$json->{NIC} = identifyNIC($ip);
# 	sleep 1;
# 	return $json;
	
	my $apiKey = 'JE562K-H58HG85G77';
	my $url = 'http://api.wolframalpha.com/v2/query?input=' . $ip . '&appid=' . $apiKey;
	my $xml = get_url($url);
	sleep 1;
	my $xml_ref = read_xml($xml, [qw(pod subpod info state)]);
	if ($xml_ref->{queryresult} && $xml_ref->{queryresult}->{pod} && @{$xml_ref->{queryresult}->{pod}}) {
		my ($name, $location);
		foreach my $pod (@{$xml_ref->{queryresult}->{pod}}) {
			if ($pod->{sub_attribute}->{id} eq 'HostInformationPodIP:InternetData') {
#				$self->{debug}->print_object($pod, '$pod');
				my $geo = {};
				($geo->{name}, $geo->{location}) = $pod->{subpod}->[0]->{plaintext} =~ /name \| (.*?)location \| (.*?)$/;
				($geo->{cityName}, $geo->{regionName}, $geo->{countryName}) = split(/\s*,\s*/, $geo->{location});
				if (!$geo->{countryName} && $geo->{regionName}) { $geo->{countryName} = $geo->{regionName}; delete $geo->{regionName}; }
				else {
					my $regionCode = getStateCode($geo->{regionName});
					if ($regionCode) { $geo->{regionCode} = $regionCode; }
				}
				$geo->{url} = $pod->{infos}->{info}->[0]->{link_attr}->{url};
#				($geo->{lat}, $geo->{long}) = $pod->{infos}->{info}->[0]->{link_attr}->{url} =~ /cp=([\d\.\-]+)~([\d\.\-]+)&/;
				($geo->{latitude}, $geo->{longitude}) = $geo->{url} =~ /ll=([\d\.\-]+)%2C([\d\.\-]+)&/;
				$geo->{latitude} += 0; $geo->{longitude} += 0;
				return $geo;
			}
		}
	}
	return {};
}


#=====================================================

=head2 B<identifyNIC>

=cut
#=====================================================
sub identifyNIC {
	my $ip = shift || return;
	my ($classA) = $ip =~ /^(\d+)/;
	$classA || return;
	
	# http://www.iana.org/assignments/ipv4-address-space/ipv4-address-space.txt
	# http://en.wikipedia.org/wiki/List_of_assigned_/8_IPv4_address_blocks
	my $nicDB = {
#		IANA	=> [qw(000 010 127)],
		IANA	=> [qw(000 127)],
		AFRINIC	=> [qw(041 102 105 197)],
		APNIC	=> [qw(001 014 027 036 039 042 043 049 058 059 060 061 101 103 106 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 175 180 182 183 202 203 210 211 218 219 220 221 222 223)],
		LACNIC	=> [qw(177 179 181 186 187 189 190 200 201)],
		RIPE	=> [qw(002 005 031 037 046 062 077 078 079 080 081 082 083 084 085 086 087 088 089 090 091 092 093 094 095 109 128 176 178 185 188 193 194 195 212 213 217)]
	};
	
	# Washington DC block in APNIC
	if ($ip =~ /^27\.0\.(\d+)\./) {
		if (($1 >= 16) && ($1 <= 31)) { return; }
	}
	# APNIC 169.208.0.0/12
	elsif ($ip =~ /^169\.208\./) { return 'APNIC'; }
	# RIPE 144.76.0.0/16
	elsif ($ip =~ /^144\.76\./) { return 'RIPE'; }
	# RIPE 192.113-118.0.0/16
	elsif ($ip =~ /^192\.11[3-8]\./) { return 'RIPE'; }
	# APNIC Peg Tech PT-82
	elsif ($ip =~ /^192\.74\.(\d+)\./) {
		if (($1 >= 139) && ($1 <= 208)) { return 'APNIC'; }
		elsif ($1 >= 230) { return 'APNIC'; }
	} elsif ($ip =~ /^199\.180\.(\d+)\./) {
		if (($1 >= 100) && ($1 <= 103)) { return 'APNIC'; }
	} elsif ($ip =~ /^199\.188\.(\d+)\./) {
		if (($1 >= 104) && ($1 <= 111)) { return 'APNIC'; }
	} elsif ($ip =~ /^142\.4\.(\d+)\./) {
		if (($1 >= 96) && ($1 <= 127)) { return 'APNIC'; }
	} elsif ($ip =~ /^142\.0\.(\d+)\./) {
		if (($1 >= 128) && ($1 <= 143)) { return 'APNIC'; }
	}
	
	while (my($nic, $blockList) = each(%{$nicDB})) {
		foreach my $block (@{$blockList}) {
			if ($block == $classA) {
				return $nic;
			}
		}
	}
}


#=====================================================

=head2 B<convertStringToDateTime>

Given a date/time as a string, returns a UTC DateTime object.

 my $dateTimeObject = convertStringToDateTime($timeAsString, [ $defaultTimeZone ]);

=cut
#=====================================================
sub convertStringToDateTime {
	my $timeString = shift || return;
	my $timeZone = shift || 'UTC';
	
	my ($year, $month, $day, $isDateOnly);
	my ($hour, $minute, $second, $meridian, $offset, $tz);
	my $format;
	
	# Named times
	if ($timeString =~ /^(?:now|current_time|current_timestamp)$/i) {
		my $dt = DateTime->now(
			time_zone	=> $timeZone
		);
		$dt->set_time_zone('UTC');
		return $dt;
	}
	if ($timeString =~ /^(?:today|current_date)$/i) {
		my $dt = DateTime->today(
			time_zone	=> $timeZone
		);
		$dt->set_time_zone('UTC');
		return $dt;
	}
	
	# Epoch (9 and 10 digit) - 1973-03-03 to 2286-11-20
	# 1406576237
	if ($timeString =~ /^\d{9,10}$/) {
		my $dt = DateTime->from_epoch(
			epoch		=> $timeString,
			time_zone	=> $timeZone
		);
		$dt->set_time_zone('UTC');
		return $dt;
	}
	
	# ISO 8601 - http://en.wikipedia.org/wiki/ISO_8601
	# 20140728
	if (($year, $month, $day) = $timeString =~ /^(\d{4})(\d\d)(\d\d)$/) {
		$isDateOnly = TRUE;
		$format = "iso 8601 date";
	}
	# 2014-07-28
	elsif (($year, $month, $day) = $timeString =~ /^(\d{4})\-(\d\d)\-(\d\d)$/) {
		$isDateOnly = TRUE;
		$format = "iso 8601 date dash";
	}
	# 20140728T134900Z
	elsif (($year, $month, $day, $hour, $minute, $second, $offset) = $timeString =~ /^(\d{4})(\d\d)(\d\d)T(\d\d)(?:(\d\d)(\d\d)?)?(Z|[\+\-]\d\d?(?:\d\d)?)?$/i) {
		$format = "iso 8601 datetime";
	}
	# 2014-07-28T13:49:00Z
	elsif (($year, $month, $day, $hour, $minute, $second, $offset) = $timeString =~ /^(\d{4})\-(\d\d)\-(\d\d)T(\d\d)(?::(\d\d)(?::(\d\d))?)?(Z|[\+\-]\d\d?(?::\d\d)?)?$/i) {
		$format = "iso 8601 datetime dash";
	}
	
	# RFC
	# Mon, 28 Jul 2014 13:49:00 GMT
	elsif (($day, $month, $year, $hour, $minute, $second, $tz) = $timeString =~ /^\w{3},\s+(\d\d?)\s+(\w{3})\s+(\d{4})\s+(\d\d)(?::(\d\d)(?::(\d\d))?)?(?:\s+([a-zA-Z][a-zA-Z0-9_\/\-\+]*[a-zA-Z0-9]))?$/) {
		$format = "rfc 822";
	}
	
	# Non-standard dates
	# Tue Sep 30 20:00:00 UTC 2014
	elsif (($month, $day, $hour, $minute, $second, $tz, $year) = $timeString
	=~ /^\w{3}\s+(\w{3})\s+(\d\d?)\s+(\d\d)(?::(\d\d)(?::(\d\d))?)?(?:\s+([a-zA-Z][a-zA-Z0-9_\/\-\+]*[a-zA-Z0-9]))\s+(\d{4})$/) {
		$format = "zvents";
	}
	
	# 2014-07-28 13:49:00
	elsif (($year, $month, $day, $hour, $minute, $second, $meridian, $offset, $tz) = $timeString =~ /^(\d{4})\-(\d\d?)\-(\d\d?)(?:\s+(\d\d?)(?::(\d\d)(?::(\d\d(?:\.\d+)?))?)?(?:\s*([ap]\.?m\.?))?)?([\+\-]\d[:\d]*)?(?:\s+([a-zA-Z][a-zA-Z0-9_\/\-\+]*[a-zA-Z0-9]))?$/i) {
		$format = "dash datetime";
	}
	# 07/28/2014
	elsif (($month, $day, $year) = $timeString =~ /^(\d\d)\/(\d\d)\/(\d{2,4})$/) {
		$isDateOnly = TRUE;
		$format = "slash date";
	}
	# 07/28/2014 13:49:00
	# 07/28/2014 1:49 pm
	elsif (($month, $day, $year, $hour, $minute, $second, $meridian, $tz) = $timeString =~ /^(\d\d?)\/(\d\d?)\/(\d{2,4})(?:\s+(\d\d?)(?::(\d\d)(?::(\d\d))?)?(?:\s*([ap]\.?m\.?))?)?(?:\s+([a-zA-Z][a-zA-Z0-9_\/\-\+]*[a-zA-Z0-9]))?$/i) {
		$format = "slash datetime";
	}
	# 28/Jul/2014:13:49:00 -0500
	elsif (($day, $month, $year, $hour, $minute, $second, $tz) = $timeString =~ /^(\d\d?)\/(\w{3})\/(\d{2,4}):(\d\d?):(\d\d):(\d\d)(?:\s+(Z|[\+\-]\d+))?$/) {
		$format = "apache";
	}
	# Jul. 28, 2014 1:49 p.m.
	# Dec. 3, 2014 9:30 a.m.
	elsif (($month, $day, $year, $hour, $minute, $second, $meridian) = $timeString =~ /^(\w{3})\.?\s*(\d\d?)(?:,\s*|\s+)(\d{2,4}),?\s+(\d\d?)(?::(\d\d)(?::(\d\d))?)?(?:\s*([ap]\.?m\.?))?$/i) {
		$format = "crap";
	}
	elsif (($month, $day, $year) = $timeString =~ /^(\w{3})\.?\s*(\d\d?)(?:,\s*|\s+)(\d{2,4})$/i) {
		$format = "crap";
	}
	else {
		return;
	}
	
	if (!defined($month) || !defined($year)) { return; }
	
	if ($year < 70) { $year += 2000; }
	elsif ($year < 100) { $year += 1900; }
	if ($month =~ /[A-Za-z]/) { $month = getMonth($month); }
	if ($meridian) {
		$meridian =~ s/\W+//g;
		if ((lc($meridian) eq 'pm') && ($hour < 12)) { $hour += 12; }
		elsif ((lc($meridian) eq 'am') && ($hour == 12)) { $hour = 0; }
	}
	
	if (lc($offset) eq 'z') { $timeZone = 'UTC'; }
	elsif ($offset) {
		$offset =~ s/^([\-\+])(\d):/${1}0$2/;
		$offset =~ s/^([\-\+])(\d)$/${1}0$2/;
		$offset =~ s/^([\-\+]\d{2})$/${1}00/;
		$offset =~ s/^([\-\+])(\d{3})$/${1}0$2/;
		$timeZone = $offset;
	}
	elsif (lc($tz) eq 'edt') { $timeZone = '-0400'; }
	elsif (lc($tz) eq 'cdt') { $timeZone = '-0500'; }
	elsif (lc($tz) eq 'cst') { $timeZone = '-0600'; }
	elsif (lc($tz) eq 'mdt') { $timeZone = '-0600'; }
	elsif (lc($tz) eq 'pdt') { $timeZone = '-0700'; }
	elsif (lc($tz) eq 'pst') { $timeZone = '-0800'; }
	elsif (DateTime::TimeZone->is_valid_name($tz)) { $timeZone = $tz; }
	
	$hour ||= 0;
	$minute ||= 0;
	$second ||= 0;
	if ($year || $month || $day) {
		my $dt;
		eval {
			$dt = DateTime->new(
				year		=> int($year),
				month		=> int($month),
				day			=> int($day),
				hour		=> int($hour),
				minute		=> int($minute),
				second		=> int($second),
				time_zone	=> $timeZone
			);
		};
		if ($@) { print STDERR "$@\n"; return; }
		$dt->set_time_zone('UTC');
		return $dt;
	}
}


#=====================================================

=head2 B<convertStringToEpoch>

=cut
#=====================================================
sub convertStringToEpoch {
	my $dt = convertStringToDateTime(@_);
	return $dt->epoch();
}


#=====================================================

=head2 B<convertDateTimeToString>

Given a DateTime object, returns the given format as a string. Formats: iso, ics, rfc, display. Defaults to readable ISO, good for PostgreSQL.

 my $dateString = convertDateTimeToString($dateTimeObject);
 my $dateString = convertDateTimeToString($dateTimeObject, $format, $timeZone);

=cut
#=====================================================
sub convertDateTimeToString {
	my $dt = shift || return;
	my $format = shift;
	my $timeZone = shift || 'UTC';
	my $dateOnly = shift;
	
	$dt->set_time_zone($timeZone);
	
	my $display;
	if ($dateOnly) {
		if ($format eq 'iso') {
			$display = $dt->strftime('%Y%m%d');
		# For use in iCalendar exports
		} elsif ($format eq 'ics') {
			$display = $dt->strftime("%Y%m%d");
		# For use in RSS feeds
		} elsif ($format eq 'rfc') {
			$display = $dt->strftime("%a, %d %b %Y 00:00:00 %Z");
		# For display
		} elsif ($format eq 'display') {
			my $m = $dt->month() + 0;
			my $d = $dt->day() + 0;
			$display = $dt->strftime("$m/$d/%Y");
		# For use in PostgreSQL
		} else {
			$display = $dt->strftime("%Y-%m-%d");
		}
	} else {
		if ($format eq 'iso') {
			my $offset = $dt->strftime('%z');
			if ($offset == 0) { $offset = 'Z'; }
			$display = $dt->strftime('%Y%m%dT%H%M%S');
			$display .= $offset;
		# For use in iCalendar exports
		} elsif ($format eq 'ics') {
			my $tz = $dt->time_zone_long_name();
			$tz =~ s/\//-/g;
			$display = $dt->strftime("TZID=$tz:%Y%m%dT%H%M%S");
		# For use in RSS feeds
		} elsif ($format eq 'rfc') {
			$display = $dt->strftime("%a, %d %b %Y %H:%M:%S %Z");
		# For display
		} elsif ($format eq 'display') {
			my $m = $dt->month() + 0;
			my $d = $dt->day() + 0;
			$display = $dt->strftime("$m/$d/%Y %l:%M:%S %P");
		# For use in PostgreSQL
		} else {
			$display = sprintf("%04d-%02d-%02d %02d:%02d:%02d", $dt->year, $dt->month, $dt->day, $dt->hour, $dt->minute, $dt->second);
			$display = $dt->strftime("%Y-%m-%d %H:%M:%S %Z");
		}
	}
	return $display;
}

#=====================================================

=head2 B<getDurationSummary>

Given a DateTime::Duration, returns a text output of the duration only including the two most significant units.

 my $output = getDurationSummary($duration);

=cut
#=====================================================
sub getDurationSummary {
	my $dur = shift || return;
	my @output;
	my $cnt;
	foreach my $level (qw(years months weeks days hours minutes seconds)) {
		my $amount = $dur->$level;
		if ($amount) {
			my $label = $level;
			if ($amount == 1) { $label =~ s/s$//; }
			push(@output, $amount . " $label");
			$cnt++;
		} elsif ($cnt) { last; }
		if ($cnt > 1) { last; }
	}
	return join(' ', @output);
}

#=====================================================

=head2 B<getEstimatedTimeRemaining>

 my $startDateTimeObject = convertStringToDateTime('now');
 my $output = getEstimatedTimeRemaining($startDateTimeObject, $fractionOfCompletion);

=cut
#=====================================================
sub getEstimatedTimeRemaining {
	my $startTime = shift || return;
	my $fraction = shift;
	my $currentTime = convertStringToDateTime('now');
	my $secondsElapsed = $currentTime->epoch - $startTime->epoch;
	if ($secondsElapsed < 5) { return 'Estimating...'; }
	my $secondsRemaining = int($secondsElapsed / $fraction) - $secondsElapsed;
	my $durEpoch = $secondsRemaining + $startTime->epoch;
	my $durTime = DateTime->from_epoch( epoch => $durEpoch );
	my $duration = $durTime->subtract_datetime($startTime);
	my $output = getDurationSummary($duration);
	return $output;
}



#=====================================================

=head2 B<Disabled functions>

=cut
#=====================================================


# sub parse_xml {
# #=====================================================
# 
# =head2 B<parse_xml>
# 
#  my $xmlRef = parse_xml($xml);
#  my $xmlRef = parse_xml($xml, [qw(item)]); # List contains tags to force as arrays
# 
# =cut
# #=====================================================
# 	my $xml = shift || return;
# 	my $arrayTagList = shift;
# 	my $parser = new XML::Parser::Expat;
# 	my $structure = {};
# 	$parser->{current} = $structure;
# 	$parser->setHandlers(
# 		'Start'	=> \&_parse_xml_start,
# 		'End'	=> \&_parse_xml_end,
# 		'Char'	=> \&_parse_xml_char
# 	);
# 	eval { $parser->parse($xml); };
# 	if ($@) { return; }
# 	my $arrayTagRef = arrayToHash($arrayTagList);
# 	my $xmlRef = _parse_xml_convert($structure, $arrayTagRef);
# 	
# 	return $xmlRef;
# }
# 
# sub _parse_xml_start {
# 	my ($parser, $tag, %atts) = @_;
# 	my $node = { _parent_node => $parser->{current} };
# 	
# 	while (my($name,$value) = each(%atts)) {
# 		if ($name && $value) { $node->{_attributes}->{$name} = $value; }
# 	}
# 	push(@{$parser->{current}->{$tag}}, $node);
# 	$parser->{current} = $node;
# }
# 
# sub _parse_xml_end {
# 	my ($parser, $tag) = @_;
# 	$parser->{current} = $parser->{current}->{_parent_node};
# }
# 
# sub _parse_xml_char {
# 	my ($parser, $char) = @_;
# 	if ($char =~ /\S/) { $parser->{current}->{_data} .= $char; }
# }
# 
# sub _parse_xml_convert {
# 	my $structure = shift || return;
# 	my $arrayTagRef = shift;
# 	my $xmlRef;
# 	
# 	while (my($tag, $ref) = each(%{$structure})) {
# 		if ($tag eq '_parent_node') { next; }
# 		if (ref($ref) eq 'ARRAY') {
# 			my $elementRef = [];
# 			my $arrayAttr;
# 			foreach my $element (@{$ref}) {
# 				if (ref($element) eq 'HASH') {
# 					my $endNode = 1;
# 					while (my($innerTag, $innerRef) = each(%{$element})) {
# 						if ($innerTag !~ /^(?:_attributes|_data|_parent_node)$/) { undef($endNode); }
# 					}
# 					my $response;
# 					if ($endNode) {
# 						$response = $element->{_data};
# 						$arrayAttr = $element->{_attributes};
# 					} else {
# 						$response = _parse_xml_convert($element, $arrayTagRef);
# 					}
# 					push(@{$elementRef}, $response);
# 				} else {
# 					print STDERR "Error: should be hash, found $element\n";
# 				}
# 			}
# 			if ((@{$elementRef} > 1) || $arrayTagRef->{$tag} || ($ref->[0]->{_attributes}->{type} eq 'array')) {
# 				my $cnt;
# 				foreach my $item (@{$elementRef}) {
# 					my $refitem = ref($item);
# 					if (ref($item) eq 'HASH') {
# 						$item->{sub_attribute} = $ref->[$cnt]->{_attributes};
# 						push(@{$xmlRef->{$tag}}, $item);
# 					} else {
# 						push(@{$xmlRef->{$tag}}, $item);
# 						push(@{$xmlRef->{"${tag}_attr"}}, $ref->[$cnt]->{_attributes});
# 					}
# 					$cnt++;
# 				}
# # 				if ($arrayAttr) {
# # 					if ($arrayAttr->{type} eq 'array') { delete($arrayAttr->{type}); }
# # 					$xmlRef->{"${tag}_attr"} = $arrayAttr;
# # 				}
# 			} else {
# 				if ((ref($elementRef->[0]) eq 'HASH') && $elementRef->[0]->{sub_attribute}) {
# 					if ($elementRef->[0]->{sub_attribute} eq 'array') { delete($elementRef->[0]->{sub_attribute}->{type}); }
# 					$xmlRef->{"${tag}_attr"} = $elementRef->[0]->{sub_attribute};
# 					delete($elementRef->[0]->{sub_attribute});
# 				} elsif ($arrayAttr) {
# 					if ($arrayAttr->{type} eq 'array') { delete($arrayAttr->{type}); }
# 					$xmlRef->{"${tag}_attr"} = $arrayAttr;
# 				}
# 				$xmlRef->{$tag} = $elementRef->[0];
# 			}
# 		} elsif (ref($ref) eq 'HASH') {
# 			my $attr = {}; mergeHashes($attr, $ref);
# 			if ($attr->{type} eq 'array') { delete($attr->{type}); }
# 			if (keys(%{$attr})) { $xmlRef->{sub_attribute} = $attr; }
# 		} elsif ($tag eq '_data') {
# 			$ref =~ s/(?:^<!\[CDATA\[|\]\]>$)//g;
# 			$xmlRef = $ref;
# 		} else {
# 			print STDERR "Error: found other $ref\n";
# 		}
# 	}
# 	return $xmlRef;
# }
# 
# 
# sub make_xml {
# #=====================================================
# 
# =head2 B<make_xml>
# 
#  my $xml = make_xml($xmlRef);
#  my $xmlToPrint = make_xml($xmlRef, {
#  	noHeader	=> 1,							# Used to suppress the outermost XML tags
#  	stylesheet	=> 'http://some.com/style.css',	# Specify a URL for a CSS stylesheet
#  	noArray	=> 1,							# Suppress the array attribute
#  	splitXML	=> 1,							# Split XML elements greater than 32k
#  	iePad		=> 1,							# Pad with elements because IE sucks
#  } );
# 
# =cut
# #=====================================================
# 	my $data = shift;
# 	my $options = shift;
# 	my $noHeader = $options->{noHeader} || $options->{no_header};
# 	my $stylesheet = $options->{stylesheet};
# 	my $noArray = $options->{noArray} || $options->{no_array};
# 	my $splitXML = $options->{splitXML} || $options->{split_xml};
# 	my $iePad = $options->{iePad} || $options->{ie_pad};
# 	my $depth = shift;
# 	my $tabs = "\t" x $depth;
# 	my $xml;
# 	my $subs;
# 	unless ($noHeader) {
# 		$xml .= <<"EOM";
# $tabs<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
# EOM
# 		if ($stylesheet) {
# 			$xml .= <<"EOM";
# $tabs<?xml-stylesheet type="text/css" href="$stylesheet" ?>
# EOM
# 		}
# 		$options->{noHeader} = 1;
# 	}
# 	if (ref($data) ne 'HASH') {
# 		$xml .= <<"EOM";
# $tabs<warning>!! Not a hash !!</warning>
# EOM
# 		return $xml;
# 	}
# 	my $cnt;
# 	foreach my $name (sort _by_hash_key (keys(%{$data}))) {
# 		if (($depth == 1) && ($name eq 'stylesheet')) { next; }
# 		if ($name !~ /^\w/i) { next; }
# 		my $value = $data->{$name};
# 		# Filter things that break XML
# 		$value =~ s/\f//;
# 		my $attributes;
# 		if ($data->{"${name}_attr"}) {
# 			my ($attr,$attrValue);
# 			while (($attr,$attrValue) = each(%{$data->{"${name}_attr"}})) {
# 				if ($attr && $attrValue) {
# 					xmlify($attrValue);
# 					$attributes .= " $attr=\"$attrValue\"";
# 				}
# 			}
# 		}
# 		if ($name eq 'sub_attribute') {
# 			my ($sub,$subValue);
# 			while (($sub,$subValue) = each(%{$data->{$name}})) {
# 				if ($sub && $subValue) {
# 					xmlify($subValue);
# 					$subs .= " $sub=\"$subValue\"";
# 				}
# 			}
# 		} elsif ($name =~ /_attr$/) {
# 		} elsif ($name =~ /_is_xml$/) {
# 		} elsif (ref($value) eq 'HASH') {
# 			my $subXML = make_xml($value,$options,$depth+1);
# 			$xml .= <<"EOM";
# $tabs<$name$attributes>
# $subXML$tabs</$name>
# EOM
# 			$cnt++;
# 		} elsif (ref($value) eq 'ARRAY') {
# 			my $typeArray;
# 			unless ($noArray) { $typeArray = ' type="array"'; }
# 			foreach (@{$value}) {
# 				if (ref($_) eq 'HASH') {
# 					my ($subXML, $subAttr) = make_xml($_,$options,$depth+1);
# 					$xml .= <<"EOM";
# $tabs<$name$attributes$subAttr$typeArray>
# $subXML$tabs</$name>
# EOM
# 				$cnt++;
# 				} elsif (!ref($_)) {
# 					my $subValue = $_;
# 					if ($splitXML && (length($subValue) > 32766)) {
# 						my $valueList = _split_xml_element($subValue);
# 						foreach (@{$valueList}) {
# 							my $subValue = $_;
# 							xmlify($subValue);
# 							$xml .= <<"EOM";
# $tabs<$name$attributes$typeArray>$subValue</$name>
# EOM
# 							$cnt++;
# 						}
# 					} else {
# 						xmlify($subValue);
# 						$xml .= <<"EOM";
# $tabs<$name$attributes$typeArray>$subValue</$name>
# EOM
# 						$cnt++;
# 					}
# 				}
# 			}
# 		} elsif ($value || (($name =~ /^(?:padding|margin|border)_/) && defined($value))) {
# 			if ($data->{"${name}_is_xml"}) {
# 				$xml .= <<"EOM";
# $tabs<$name$attributes>
# $value</$name>
# EOM
# 				$cnt++;
# 			} elsif ($value eq 'NULL') {
# 				$xml .= <<"EOM";
# $tabs<$name$attributes />
# EOM
# 				$cnt++;
# 			} else {
# 				if ($splitXML && (length($value) > 32766)) {
# 					my $valueList = _split_xml_element($value);
# 					foreach (@{$valueList}) {
# 						my $subValue = $_;
# 						xmlify($subValue);
# 						$xml .= <<"EOM";
# $tabs<$name>$subValue</$name>
# EOM
# 						$cnt++;
# 					}
# 				} else {
# 					xmlify($value);
# 					$xml .= <<"EOM";
# $tabs<$name$attributes>$value</$name>
# EOM
# 					$cnt++;
# 				}
# 			}
# 		} elsif ($attributes) {
# 			$xml .= <<"EOM";
# $tabs<$name$attributes/>
# EOM
# 			$cnt++;
# 		}
# 	}
# 	if ($iePad && $depth && ($cnt <= 1)) {
# 		$xml .= <<"EOM";
# $tabs<ie_sucks/>
# EOM
# 	}
# 	if ($subs) { return $xml, $subs; }
# 	else { return $xml; }
# }
# 
# sub _by_hash_key {
# 	if ($a =~ /^(?:item_id|modif(?:y|ied)_timestamp)$/) { return -1; }
# 	elsif ($b =~ /^(?:item_id|modif(?:y|ied)_timestamp)$/) { return 1; }
# 	elsif (($a eq 'item') || ($a eq 'entry') || ($a eq 'list')) { return 1; }
# 	elsif (($b eq 'item') || ($b eq 'entry') || ($b eq 'list')) { return -1; }
# 	else { return $a cmp $b; }
# }
# 
# sub _split_xml_element {
# 	my $value = shift || return;
# 	print STDERR "splitting xml value (" . length($value) . " bytes)...\n";
# 	my $valueList = [];
# 	my $cnt = 20;
# 	while ($cnt && $value) {
# 		my $temp = substr($value, 0, 32766);
# 		push(@{$valueList}, $temp);
# 		substr($value, 0, 32766) = '';
# 		$cnt--;
# 	}
# 	return $valueList;
# }

#=====================================================

=head2 B<New functions>

=cut
#=====================================================

sub _get_list_of_names {
	state $names = [
		{ short => 'Bilbo',			long => 'Bilbo Baggins',				tags => ['hobbit'],		source => 'The Hobbit' },
		{ short => 'Baggins',		long => 'Bilbo Baggins',				tags => ['hobbit'],		source => 'The Hobbit' },
		{ short => 'Baggins',		long => 'Bungo Baggins',				tags => ['hobbit'],		source => 'The Hobbit' },
		{ short => 'Belladonna',	long => 'Belladonna Took',				tags => ['hobbit'],		source => 'The Hobbit' },
		{ short => 'Took',			long => 'The Old Took',					tags => ['hobbit'],		source => 'The Hobbit' },
		{ short => 'Chubb',			long => 'Chubb, Chubb, and Burrowes',	tags => ['hobbit'],		source => 'The Hobbit' },
		{ short => 'Burrowes',		long => 'Chubb, Chubb, and Burrowes',	tags => ['hobbit'],		source => 'The Hobbit' },
		{ short => 'Bullroarer',	long => 'Bullroarer Took',				tags => ['hobbit'],		source => 'The Hobbit' },
		{ short => 'Gandalf',		long => 'Gandalf, the Grey',			tags => ['wizard'],		source => 'The Hobbit' },
		{ short => 'Radagast',		long => 'Radagast, the Brown',			tags => ['wizard'],		source => 'The Hobbit' },
		{ short => 'Dain',			long => 'Dain Ironfoot',				tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Náin',			long => 'Náin',							tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Thorin',		long => 'Thorin Oakenshield',			tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Thráin',		long => 'Thráin',						tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Thrór',			long => 'Thrór',						tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Fíli',			long => 'Fíli',							tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Kíli',			long => 'Kíli',							tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Balin',			long => 'Balin',						tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Dwalin',		long => 'Dwalin',						tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Óin',			long => 'Óin',							tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Glóin',			long => 'Glóin',						tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Dori',			long => 'Dori',							tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Nori',			long => 'Nori',							tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Ori',			long => 'Ori',							tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Bifur',			long => 'Bifur',						tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Bofur',			long => 'Bofur',						tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Bombur',		long => 'Bombur',						tags => ['dwarf'],		source => 'The Hobbit' },
		{ short => 'Elrond',		long => 'Elrond',						tags => ['elf'],		source => 'The Hobbit' },
		{ short => 'Thranduil',		long => 'Thranduil',					tags => ['elf'],		source => 'The Hobbit' },
		{ short => 'Galion',		long => 'Galion',						tags => ['elf'],		source => 'The Hobbit' },
		{ short => 'Bard',			long => 'Bard the Bowman',				tags => ['man'],		source => 'The Hobbit' },
		{ short => 'Beorn',			long => 'Beorn',						tags => ['man'],		source => 'The Hobbit' },
		{ short => 'Tom',			long => 'Tom',							tags => ['troll'],		source => 'The Hobbit' },
		{ short => 'Bert',			long => 'Bert',							tags => ['troll'],		source => 'The Hobbit' },
		{ short => 'William',		long => 'Bill Huggins',					tags => ['troll'],		source => 'The Hobbit' },
		{ short => 'Gollum',		long => 'Gollum',						tags => ['other'],		source => 'The Hobbit' },
		{ short => 'Sauron',		long => 'Sauron',						tags => ['other'],		source => 'The Hobbit' },
		{ short => 'Smaug',			long => 'Smaug',						tags => ['dragon'],		source => 'The Hobbit' },
		{ 							long => 'Lord of the Eagles',			tags => ['eagle,bird'],	source => 'The Hobbit' },
		{ short => 'Carc',			long => 'Carc',							tags => ['raven,bird'],	source => 'The Hobbit' },
		{ short => 'Roäc',			long => 'Roäc',							tags => ['raven,bird'],	source => 'The Hobbit' },
		{ 							long => 'Great Goblin',					tags => ['goblin,orc'],	source => 'The Hobbit' },
		{ short => 'Bolg',			long => 'Bolg',							tags => ['goblin,orc'],	source => 'The Hobbit' },
		{ short => 'Golfimbul',		long => 'Golfimbul',					tags => ['goblin,orc'],	source => 'The Hobbit' },
	];
	return $names;
}
sub get_unique_name {
	my $type = shift || 'short';
	if ($type !~ /^(short|long)$/) { $type = 'short'; }
	state $name_list = [];
	if (!is_array_with_content($name_list)) {
		my $names = _get_list_of_names;
		my $name_map = {};
		foreach my $name (@{$names}) {
			$name->{$type} || next;
			my $clean_name = kebab_case(normalize($name->{$type}, TRUE));
			$name_map->{$clean_name} = TRUE;
		}
		@{$name_list} = keys(%{$name_map});
	}
	return $name_list->[int(rand(@{$name_list}))];
}




=head1 CHANGES

  20070628 TJM - v1.0 copied from various places
  20120105 TJM - v6.0 mostly the same
  20120724 TJM - v5.5 copied in from Sitemason 6
  20140320 TJM - v7.0 merged 5.5 and 6
  20171109 TJM - v8.0 Moved to SitemasonPL open source project and merged with updates

=head1 AUTHOR

  Tim Moses <tim@moses.com>
  Sitemason Open Source <https://github.com/sitemason>

=cut

1;
