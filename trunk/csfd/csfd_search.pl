#!/usr/bin/perl 
#===============================================================================
#
#         FILE:  csfd_search.pl
#
#        USAGE:  ./csfd_search.pl 'movie title'
#
#  DESCRIPTION:  Script for searching movies on czech movie database www.csfd.cz
#
#      OPTIONS:  ---
# REQUIREMENTS:  liblwp-useragent-perl
#		 libhttp-request-perl
#		 libxml-writer-perl
#		 libdigest-md5-file-perl	      		    
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Martin Janota (mjan), <janota.m@cce.cz>
#      COMPANY:  CCE
#      VERSION:  0.1
#      CREATED:  30.11.08 11:56:06 CET
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;


use LWP::UserAgent;
use HTTP::Request::Common qw { POST };
use Data::Dumper;
use XML::Writer;
use IO::File;

use Digest::MD5;
use MIME::Base64 qw(encode_base64);

my $ADDRESS = 'http://www.csfd.cz';
my @MOVIES;
my @IMAGES;

#===  FUNCTION  ================================================================
#         NAME:  get_page_post
#   PARAMETERS:  url, arrray post 
#      RETURNS:  page content or undef
#  DESCRIPTION:  stahne html zadaneho url metodou post
#     COMMENTS:  none
#===============================================================================

sub get_page_post  {
	my $ua = LWP::UserAgent->new;
	my $req = POST $_[0], $_[1];
	my $res = $ua->request($req);
	if ($res->is_success) {
		return $res->as_string
	}
	print "False\n";
	undef;
}


#===  FUNCTION  ================================================================
#         NAME:  get_page_get
#   PARAMETERS:  url
#      RETURNS:  page content or undef 
#  DESCRIPTION:  stahne html zadaneho url metodou get
#     COMMENTS:  none
#===============================================================================

sub get_page_get {
	my $ua = LWP::UserAgent->new;
	$ua->agent("$0/1.0" . $ua->agent);
	my $req = HTTP::Request->new(GET => $_[0] );
	$req->header('Accept' => 'text/html');
	
	my $res = $ua->request($req);
#	print Dumper($res);
	if ($res->is_success) {
		return $res->as_string;
	}
	undef;
}

#===  FUNCTION  ================================================================
#         NAME:  download_file
#   PARAMETERS:  url
#      RETURNS:  1 | 0
#  DESCRIPTION:  stahne soubor a vrati 1 / 0
#     COMMENTS:  none
#===============================================================================

sub download_file {
	my $ua = LWP::UserAgent->new;
	my $expected_length;
	my $bytes_received = 0;
	my $file = shift;
	my $req = HTTP::Request->new(GET => shift);
	my $res = $ua->request($req,$file);
	if ($res->is_success) {
#		print "Download OK\n";
		return 1;
	}
#	print $res->status_line, "\n";
	0;
}



#===  FUNCTION  ================================================================
#         NAME:  get_movie_ref
#   PARAMETERS:  html
#      RETURNS:  array of movie links
#  DESCRIPTION:  vraci pole adress na jednotlive filmy
#     COMMENTS:  none
#===============================================================================

sub get_movie_ref {
	my $title = shift;
	my $searchaddr = $ADDRESS . '/hledani-filmu-hercu-reziseru-ve-filmove-databazi/';
	my @words = split /\s+/, $title;
	my (@arefs, %hrefs, $html);
	foreach ( @words ) {
		my %h;
		$html = get_page_post($searchaddr,[ search => $_ ]); 
		$html =~ s/\n//g;
#		print $html ."\n";
		while ( $html =~ /href=("|')(\/film\/\d+.*?)\1/g ) { 
			next if exists $h{$2};
			$hrefs{$2}++;
			$h{$2} = 1;
		}
	}
#	print Dumper(\%hrefs);
	foreach ( keys %hrefs ) {
		push @{ $arefs[$hrefs{$_}] }, $_;
	}
	return @{ $arefs[-1] };
}


#===  FUNCTION  ================================================================
#         NAME:  get_movie_data
#   PARAMETERS:  link to movie
#      RETURNS:  1/0  
#  DESCRIPTION:  rozebere stranku s danym, filmem a prevede ji do hashe, ktery ulozi do pole @MOVIES
#     COMMENTS:  none
#===============================================================================

sub get_movie_data {
	my $ref = $ADDRESS . shift;
	my %movie;
#	print $ref. "\n";
	my $html = get_page_get($ref);
	$html =~ s/\n//g;
#	print $html ."\n";
	%movie = get_movie_info($html);
	$movie{title} = get_movie_title($html);
	@{ $movie{director} }= get_movie_person($html,'reziser');
	@{ $movie{cast} } = get_movie_person($html,'herec');
	for ( my $i = 0; $i < scalar(@{ $movie{cast} }); $i++ ) {
#		print $i."\n";
		$movie{cast}[$i] = [ $movie{cast}[$i] ];  
	}
	$movie{plot} = get_movie_plot($html,$ref);
	my %img = get_image($html);
	if ( %img ) {
		$movie{cover} = delete $img{cover};
		push @IMAGES, {%img};
	} 
	return %movie;
}


#===  FUNCTION  ================================================================
#         NAME:  get_movie_title
#   PARAMETERS:  html
#      RETURNS:  movie title
#  DESCRIPTION:  titul, v tagu <h1>titul</h1> 
#     COMMENTS:  none
#===============================================================================

sub get_movie_title {
	$_[0] =~ /<h1.*?>\s*(.*?)\s*<\/h1>/i;
	my $title = $1;
	$title =~ s/\s*$//;
#	warn $title."\n";
	$title;
}


#===  FUNCTION  ================================================================
#         NAME:  get_movie_person
#   PARAMETERS:  html
#      RETURNS:  array of actors
#  DESCRIPTION:  herci,reziser vybiram podle odkazu <a href="/herec/...>herec</a>
#     COMMENTS:  none
#===============================================================================

sub get_movie_person {
	my $html = shift;
	my $person = shift;
	my (@people,$p);
	while ( $html =~ /<a\s+href="\/$person\/.*?".*?>(.*?)<\/a>/gi ) {
		$p = $1;
		$p =~ s/(&nbsp;)/ /g;
		$p =~ s/\s*$//;
		push @people, $p;
	}
	@people;
}


#===  FUNCTION  ================================================================
#         NAME:  get_movie_info
#   PARAMETERS:  html
#      RETURNS:  hash
#  DESCRIPTION:  vraci informace o filmu, zanry, delka trvani, .... 
#     COMMENTS:  none
#===============================================================================

sub get_movie_info {
	my $html = shift;
	my ($national, %h, $time, $genres,$info );
	$html =~ /<\/h1>\s*<br>\s*<br>\s*(?:<table.*?<\/table>)?\s*<br>\s*<b>(.*?)<\/b>\s*<BR>\s*<BR>\s*/i;
	$html = $1;
#	warn "$html\n";
	$html =~ s/&nbsp;/ /g;
	($genres,$info) = split /\s*<br>\s*/i, $html;
	@{ $h{genre} } = split /\s*\/\s*/, $genres if $genres;
	if ($info) {
		($national,$h{year},$time) = split /\s*,\s*/, $info;
		@{ $h{nationality} } = split /\s*\/\s*/, $national if $national;
		( $h{time} ) = ( $time =~/(\d+)/ ) if $time;
	}
	%h;
}


#===  FUNCTION  ================================================================
#         NAME:  get_movie_plot
#   PARAMETERS:  html
#      RETURNS:  movie plot as string
#  DESCRIPTION:  vraci obsah filmu 
#     COMMENTS:  none
#===============================================================================



sub get_movie_plot {
	my $html = shift;
	$html =~ /href="(\?text=\d+)"/;
	if ($1) {
		$html = get_page_get(shift() . $1);
		$html =~ s/\n//g;
	}
	$html =~ /<div style='float:left;width:425px;padding-top:10px;font-weight:normal'>(.*?)<\/div>/;
	return $1 || '';
}

#===  FUNCTION  ================================================================
#         NAME:  get_image
#   PARAMETERS:  $html
#      RETURNS:  hash img
#  DESCRIPTION:  download img_file
#     COMMENTS:  none
#===============================================================================

sub get_image {
	my $html = shift;
	$html =~ /(http:\/\/img\.csfd\.cz\/posters.*?jpg)/;
#	print $1."\n";
	return () unless $1;
	my $src = $1;
	my %img;
	my $file = '/tmp/movie_poster.jpg';
	unless ( download_file($file,$src) ) {
		return ();  
	}
	my $imgname = generate_imgname($file) . ".jpg";
	$img{cover} = $imgname; 	
	$img{format} = 'JPG';
	$img{id} = $imgname;
	$img{width} = 134;
	$img{height} = 180;
#	$img{'link'} = 'true';
	$img{data} = file_encode64($file); 
#	print "$src.\n";
	return %img;
}


#===  FUNCTION  ================================================================
#         NAME:  generate_imgname
#   PARAMETERS:  file
#      RETURNS:  file md5 sum 
#  DESCRIPTION:  vrati md5 soucet 	 
#     COMMENTS:  none
#===============================================================================

sub generate_imgname {
	my $file = shift;
	my $ctx = Digest::MD5->new();
	open (M,$file);
	$ctx->addfile(*M);
	return $ctx->hexdigest;
	close M;
#	print $ctx->hexdigest ."\n";
}

#===  FUNCTION  ================================================================
#         NAME:  file_encode64
#   PARAMETERS:  file
#      RETURNS:  encoded file as string
#  DESCRIPTION:  
#     COMMENTS:  none
#===============================================================================

sub file_encode64 {
	my $file = shift;
	open (E,$file);
	my $txt;
	while(<E>) {
		$txt .= $_;	
	}
	return encode_base64($txt);
}


#===  FUNCTION  ================================================================
#         NAME:  perl2xml
#   PARAMETERS:  
#      RETURNS:  Tellico XML
#  DESCRIPTION:  prevadi pole @MOVIES do XML v Tellico formatu
#     COMMENTS:  none
#===============================================================================

sub perl2xml {
	my $fh = new IO::File(*STDOUT);
	my $out = new XML::Writer(OUTPUT => $fh);
	print '<?xml version="1.0" encoding="UTF-8"?>';
	print '<!DOCTYPE tellico PUBLIC "-//Robby Stephenson/DTD Tellico V9.0//EN" "http://periapsis.org/tellico/dtd/v9/tellico.dtd">';
	$out->startTag("tellico",syntaxVersion => 9, xmlns => "http://periapsis.org/tellico/");
		$out->startTag("collection", title => "Video", type => 3);
			$out->startTag("fields");
				$out->emptyTag("field", name => "_default");
			$out->endTag("fields");
	for (my $i = 0; $i < scalar(@MOVIES); $i++) {			
			$out->startTag("entry",id=>$i);
		foreach my $key ( sort keys %{ $MOVIES[$i] } ) {
				if ( ref($MOVIES[$i]->{$key}) eq 'ARRAY' ) {
					$out->startTag($key.'s');
						foreach (@{ $MOVIES[$i]->{$key} }) {
							if ( ref($_) eq 'ARRAY' ){
								$out->startTag($key);
									foreach my $v ( @$_ ) {
										$out->dataElement('column',$v);
									}
								$out->endTag($key);
							} else {
								$out->dataElement($key,$_);
							}
						}
					$out->endTag($key.'s');
				} else {
					$out->dataElement($key,$MOVIES[$i]->{$key});
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




#---------------------------------------------------------------------------
#  			MAIN BODY
#---------------------------------------------------------------------------


my @movies = get_movie_ref($ARGV[0]);
exit 1 unless @movies;

#print Dumper(\@movies);
my %m;
foreach (@movies) {
#	print $_."\n";
	%m = get_movie_data($_);
	push @MOVIES, { %m };
}

perl2xml();
#print Dumper(\@MOVIES);

