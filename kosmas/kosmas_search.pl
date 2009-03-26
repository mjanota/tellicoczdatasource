#!/usr/bin/perl -w

use strict;

use Getopt::Std;
use Data::Dumper;
use Cz::Cstocs;
sub win1250_utf8;
*win1250_utf8 = new Cz::Cstocs '1250', 'utf8';
sub utf8_ascii;
*utf8_ascii = new Cz::Cstocs 'utf8', 'ascii';

use XML::Writer;
use IO::File;

use Digest::MD5;
use MIME::Base64 qw(encode_base64);


my $ADDRESS = 'http://www.kosmas.cz';
my $TMPADDR = '/tmp/czech_book_search_' . $$;
my @BOOKS;
my @IMAGES;

mkdir $TMPADDR;
#####################################################
#                 ARGUMENTS                         #
#####################################################

my %option = ();

getopt("Hailprt", \%option);

if (defined $option{h}) {
    print <<EOF;
Usage: ./kosmas_search.pl
  -h,       help
  -a <author>   author of a book
  -i <isbn>
  -l <ilustrator>
  -o <original> Original title
  -p <publisher>
  -r <translator>
  -t <title>
EOF
    exit 0;
}

my %optw = (
    a => 'autor',
	i => 'isbn',
    l => 'ilustrace',
	o => 'original',
    p => 'vyrobce',
    r => 'preklad',
    t => 'titul',     
);

my $post_data = join "&", ('hled=Hledej...','pgCnt=100', 
    map  { 
	    $option{$_} =~ s/(\s+)/+/g;
	    $optw{$_} . "=" . lc( utf8_ascii($option{$_}) );
	 } grep( $option{$_}, keys %option ) );
#print "$post_data\n";

`wget -q -O $TMPADDR/vysledek.html  --post-data='$post_data' $ADDRESS/hledani_vysledek.asp`;
 
my @refs;
my $v = get_ref(\@refs);

exit 0 if $v == -1;

if ( $v == 1) {
	foreach (my $i = 0; $i < scalar(@refs); $i++) {
		`wget -q -O $TMPADDR/book_${i}.html $refs[$i]`;
		push @BOOKS, html2perl("$TMPADDR/book_${i}.html");
	}	
} else {
	push @BOOKS, html2perl("$TMPADDR/vysledek.html");
}

#print Dumper(\@BOOKS);
&perl2xml if scalar @BOOKS > 0;

`rm -r $TMPADDR`;

#####################################################################
#					Functions										#
#####################################################################


sub get_ref {
	my $refs = shift;
    my $txt = get_html("$TMPADDR/vysledek.html");
	$txt = win1250_utf8($txt);
	if ( $txt =~ /<!-- POPIS -->/ ) {
		return 0
	}
	if ( $txt =~ /nebyl nalezen žádný titul/) {
		return -1;
	} 
	@$refs =  $txt =~ /<a href="(http:\/\/www\.kosmas\.cz\/knihy\/\S+?)">/g;
	return 1
}

sub get_html {
    my $file = shift;
    my $txt;
    open (H, $file) or die "Couldn't open $file: $!\n";
    while (<H>) {
		chomp;
		$txt .= $_;
   	}
    close H;
    return $txt;
}

sub html2perl {
	my %h;
	my $html = get_html(shift);
	$html =  win1250_utf8($html);
	$html =~ /\<\!-- POPIS --\>(.*?)\<\!--/;
	get_data(\%h,$1);
	$html =~ /\<\!-- HLAVICKA --\>(.*?)\<\!-- HLAVICKA KONEC --\>/;
	get_titul(\%h,$1);
	$html =~ /<img src="(http:\/\/www\.kosmas\.cz\/obalky\/\S+?)"/;
	push @IMAGES, get_image(\%h,$1) if $1;
	return \%h; 
#	print Dumper(\%H);
}

sub get_data {
	my $h = shift;
	my $data = shift;
	$data =~ s/<br>|<\/h2>/\n/ig;
	$data =~ s/<.*?>|&nbsp;//g;
	my ($row);
	while ($data =~ s/(.*)\n// ) {
		$row = $1;
		$row =~ s/^\s+//;
		$row =~ s/\s+/ /g;
		next if $row =~ /^\s*$/;
		$row =~ /^(nakladatel|isbn|orig|form|rok)/i;
		my $fce = 'get_' . lc($1);
		eval {
			no strict;
			&{$fce}($h,$row) if defined &$fce;		
	
		};
		die $@ if ($@);
	}
}

sub get_titul {
	my $h = shift;
	my $data = shift;
	$data =~ /<td>(.*?)<hr/;
	$data = $1;
	$data =~ /<h1>(.*?)<\/h1>(.*)/i;
	$$h{title} = $1;
	if ($2) {
		@{ $$h{author} } = map {
			/<a.*?>(.*?)<\/a>/;
			get_name($1);
		} split ', ', $2;
	}
}

my $I = 0;
sub get_image {
	my $h = shift;
	my $src = shift;
	my %img;
	my $cover = $TMPADDR . "/obalka". $I++ .".gif";
	`wget -q -O $cover $src`;
	my $imgname = generate_imgname($cover) . ".gif";
	$$h{cover} = $imgname; 	
	$img{format} = 'GIF';
	$img{id} = $imgname;
	$img{width} = 100;
	$img{height} = 150;
#	$img{'link'} = 'true';
	$img{data} = file_encode64($cover); 
#	print "$src.\n";
	return { %img };
}

sub get_nakladatel {
	my ($h,$r) = @_;
	my ($p,$s) = $r =~ /^Nakladatel: (.*?)(?:, edice: (.*);)?$/;
	@{$$h{publisher}} = split ',', $p;
	$$h{series} = $s if $s;
}

sub get_isbn {
	my ($h,$r) = @_;
	$r =~ /^ISBN:\s*((?:\d|-)+)/i;
	$$h{isbn} = $1 if $1;
}

sub get_orig {
	my ($h,$r) = @_;
	my ($p,$s) = $r =~ /^Originál: (.*?)(?:, překlad: (.*))?$/;
	$$h{'název-originálu'} = $p if $p;
	@{ $$h{translator} } = map{ get_name($_) } (split ',', $s) if $s;
#	$$h{translator} =  get_name($s) if $s;
}

sub get_form {
	my ($h,$r) = @_;
	$r =~ /^Formát: (.*?)$/;
	my ($p, undef, $l, $b) = split ', ', $1;
	$p =~ /(\d+)\s*stran/;
	$$h{pages} = $1 if $1; 
	$$h{language} = $l if $l;
	if ($b) {
	    $b =~ /^(.*?)\s+vazba/;
	    $$h{binding} = $1 if $1;
	}
}

sub get_rok {
	my ($h,$r) = @_;
	my ($p,$s) = $r =~ /^Rok vydání:\s*(\d+)(?:[^\(]*\((\d+).*?vydání)?/;
	$$h{pub_year} = $p if $p;
	$$h{edition} = $s if $s;
}


sub get_name {
	my @a = split ' ', $_[0];
	return  pop(@a) . ", " . join " ", @a;
}

sub generate_imgname {
	my $file = shift;
	my $ctx = Digest::MD5->new();
	open (M,$file);
	$ctx->addfile(*M);
	return $ctx->hexdigest;
	close M;
#	print $ctx->hexdigest ."\n";
}

sub file_encode64 {
	my $file = shift;
	open (E,$file);
	my $txt;
	while(<E>) {
		$txt .= $_;	
	}
	return encode_base64($txt);
}

sub perl2xml {
	my $fh = new IO::File(*STDOUT);
	my $out = new XML::Writer(OUTPUT => $fh);
	print '<?xml version="1.0" encoding="UTF-8"?>';
	print '<!DOCTYPE tellico PUBLIC "-//Robby Stephenson/DTD Tellico V9.0//EN" "http://periapsis.org/tellico/dtd/v9/tellico.dtd">';
	$out->startTag("tellico",syntaxVersion => 9, xmlns => "http://periapsis.org/tellico/");
		$out->startTag("collection", title => "My Books", type => 2);
			$out->startTag("fields");
				$out->emptyTag("field", name => "_default");
			$out->endTag("fields");
	for (my $i = 0; $i < scalar(@BOOKS); $i++) {			
			$out->startTag("entry",id=>$i);
		foreach my $key ( sort keys %{ $BOOKS[$i] } ) {
				if ( ref($BOOKS[$i]->{$key}) eq 'ARRAY' ) {
					$out->startTag($key.'s');
						foreach (@{ $BOOKS[$i]->{$key} }) {
							$out->dataElement($key,$_);
						}
					$out->endTag($key.'s');
				} else {
					$out->dataElement($key,$BOOKS[$i]->{$key});
				}
		}
			$out->endTag("entry");
	}
	if ( @IMAGES) {
			$out->startTag("images");
		foreach my $img (@IMAGES) {
				my $data = delete $img->{data};
				$out->dataElement( "image",$data, %$img );
				#$out->emptyTag("image",%$img);
		}
			$out->endTag("images");
	}
		$out->endTag("collection");
	$out->endTag("tellico");
	$out->end();
}


