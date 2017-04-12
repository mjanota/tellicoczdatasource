#!/usr/bin/perl -w

use strict;

use LWP::Simple;
use Getopt::Std;
use Data::Dumper;
# use Smart::Comments;
use HTML::TreeBuilder;
use Encode;
use utf8;
use XML::Writer;
use IO::File;
use File::Basename;

use Digest::MD5;
use MIME::Base64 qw(encode_base64);


my $ADDRESS = 'http://www.databazeknih.cz';
my $TMPADDR = '/tmp/czech_book_search_' . $$;
my @BOOKS;
my @IMAGES;
my $html;
my $pmore;

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
  -p <publisher>
  -r <translator>
  -t <title>
EOF
    exit 0;
}


my $title = $option{t};
$title =~ s/(\s+)/+/g;

my $getdata = sprintf'?q=%s&hledat=&stranka=search',$title;
### $getdata

$html = `wget -q -O '-'  $ADDRESS/search$getdata`;

## $html

 
my @refs = get_ref($html);

### @refs

exit 0 if scalar @refs < 1;

foreach my $ref (@refs) {
		$html = `wget -q -O '-' $ADDRESS/$ref`;
        ### $ref
        if ( $ref =~ /(\d+)$/ ) {
            $pmore = `wget -q -O '-' $ADDRESS/helpful/ajax/more_binfo.php?bid=$1`;
        ### $pmore
        }
#		$html = get($ADDRESS.$ref);
		push @BOOKS, html2perl($html, $pmore, "$ADDRESS/$ref");
}	


### @BOOKS
### @IMAGES

warn "Could'nt find any book" unless @BOOKS;

&perl2xml if scalar @BOOKS > 0;


#####################################################################
#					Functions										#
#####################################################################


sub get_ref {
	my $Tree = HTML::TreeBuilder->new_from_content(decode_utf8($_[0]));
	## $Tree
	my @a =  $Tree->look_down( _tag => 'a', class => 'search_to_stats', type=>'book');
	my @refs ;
    my %r;
	foreach my $ref (@a) {
        continue if $r{ $ref->attr('href') };

        push @refs, $ref->attr('href');
        if ( $ref->attr('href') =~ /(\d+)$/ ) {
            ### $1
            my $editionhtml = `wget -q -O '-' $ADDRESS/book_detail_types.php?cislo=$1`;
            my $ETree       = HTML::TreeBuilder->new_from_content( decode_utf8($editionhtml) );
            my @ea          = $ETree->look_down( _tag => 'a', class => 'new strong', href => qr/dalsi-vydani/ );
            foreach my $eref (@ea) {
                push @refs, $eref->attr('href');
            }

        }
        $r{$ref->attr('href')} = 1;
	}

	return @refs;
}


sub html2perl {
    my $html = decode_utf8($_[0]);
    my $pmore = decode_utf8($_[1]);
	my $Tree = HTML::TreeBuilder->new_from_content($html);
  my $content = $Tree->look_down( _tag => 'div', id => 'content');
#my $Tree = HTML::TreeBuilder->new_from_content(decode_utf8($_[0]));
	my %h;
	$h{link} = $_[2];
	get_titul(\%h,$content);
    get_publisher( \%h, $content );
    get_pub_year( \%h, $content );
	get_origtitle(\%h,$content->look_down(_tag => 'td', class => 'binfo_hard',
            sub {$_[0]->as_trimmed_text =~ /Origin/} )
        ->parent()) if $content->look_down(_tag => 'td', class => 'binfo_hard', sub {$_[0]->as_trimmed_text =~ /Origin/} );
    get_years(\%h,$content->look_down(_tag => 'td', class => 'binfo_hard',
            sub {$_[0]->as_trimmed_text =~ /Rok vyd/} )
        ->parent()) if $content->look_down(_tag => 'td', class => 'binfo_hard', sub {$_[0]->as_trimmed_text =~ /Rok vyd/} );
    get_data(\%h, HTML::TreeBuilder->new_from_content($pmore));
	# print Dumper(\%h);
	# exit 1;
	my $img = $content->look_down(_tag => 'img', class=> 'kniha_img');
	push @IMAGES, get_image(\%h,$img->attr('src')) if $img;
	return \%h; 
}

sub get_data {
	my $h = shift;
	my $pmore = shift;
    return unless $pmore;
    get_edition( $h, $pmore );
    get_isbn($h,$pmore);
    get_translator($h,$pmore);
    get_pages( $h, $pmore );
    get_from_html($h,$pmore);
}

sub get_titul {
	my $h = shift;
	my $tree = shift;
	my $title = $tree->look_down( _tag => 'h1', itemprop => 'name')->as_trimmed_text;
  ($h->{title}, my $orig ) = split /\s*\/\s*/, $title, 2;
	$h->{encode_utf8('název-originálu')} = $orig if $orig;
	my @authors = $tree->look_down( _tag => 'h2', class => 'jmenaautoru' )->look_down( _tag => 'a');
	foreach my $auth ( @authors ) {
		push @{ $h->{author} }, $auth->as_trimmed_text; 
	}
  
  $h->{comments} = $tree->look_down(_tag => 'p', id => 'biall', itemprop => 'description')->as_trimmed_text if $tree->look_down(_tag => 'p', id => 'biall', itemprop => 'description');
}

my $I = 0;
sub get_image {
	my $h = shift;
	my $src = shift;
    ### $src 
	### src: basename($src)
	my %img;
#	my $imgdata = `wget -q -O '-' $ADDRESS/$src`;
#   oprava 3.2.2014
	my $imgdata = `wget -q -O '-' $src`;
	
	(undef,my $imgtype) = split /\./, basename($src);
	my $imgname = generate_imgname($imgdata) . "." . $imgtype;
	$$h{cover} = $imgname; 	
	$img{format} = lc($imgtype);
	$img{id} = $imgname;
	$img{width} = 100;
	$img{height} = 150;
#	$img{'link'} = 'true';
	$img{data} = encode_base64($imgdata); 
#	print "$src.\n";
	return { %img };
}

sub get_publisher {
	my ($h,$pmore) = @_;
	my @publishers = $pmore->look_down( _tag => 'a', 'href' => qr/nakladatelstvi/);
    ## @publishers
	@{$$h{publisher}} = map {$_->as_trimmed_text} @publishers if @publishers;
}

sub get_pub_year {
    my ( $h, $pmore ) = @_;
    $h->{pub_year} = $pmore->look_down( _tag => 'span', itemprop => 'datePublished' )->as_trimmed_text if $pmore->look_down( _tag => 'span', itemprop => 'datePublished' );
}

sub get_edition {
    my ( $h, $pmore ) = @_;
    $h->{edice} = $pmore->look_down( _tag => 'a', itemprop => 'BookEdition' )->as_trimmed_text if $pmore->look_down( _tag => 'a', itemprop => 'bookEdition' );
}

sub get_isbn {
	my ($h,$pmore) = @_;
    $$h{isbn} = $pmore->look_down( _tag => 'span', itemprop => 'isbn' )->as_trimmed_text if $pmore->look_down( _tag => 'span', itemprop => 'isbn' );
}

sub get_pages {
    my ( $h, $pmore ) = @_;
    $$h{pages} = $pmore->look_down( _tag => 'td', itemprop => 'numberOfPages' )->as_trimmed_text if $pmore->look_down( _tag => 'td', itemprop => 'numberOfPages' );
}

sub get_translator {
	my ($h,$pmore) = @_;
	my @itrans = $pmore->look_down( _tag => 'a', href => qr/prekladatele/);
#	@{ $$h{translator} } = map {$_->as_trimmed_text} @itrans if @itrans;
	@{ $$h{encode_utf8('překladatel')} } = map {$_->as_trimmed_text} @itrans if @itrans; 
}

sub get_years {
	my ($h,$r) = @_;
    $r = $r->as_HTML;
    ### $r
    #$h->{pub_year} = $1 if $r =~ /Rok vyd.*?<\/td><td><strong>\s*(\d+)/;

	$h->{cr_year} = $1 if $r =~ /1\. vyd.*?<strong>(.*?)<\/strong>/;
}

sub get_origtitle {
	my ($h,$r) = @_;
    $r = $r->as_HTML;
    ### $r
	$h->{encode_utf8('název-originálu')} = $1 if $r =~ /Origin.*?<\/td><td><h4>(.*?)<\/h4>/;
}

sub get_from_html {
	my ($h, $pmore) = @_;
	my $html = $pmore->as_HTML;
	# vazba
    $h->{binding} = $1 if $html =~ /Vazba knihy:\s*<\/td><td>(.*?)<\/td>/;
    #$h->{pages} = $1 if $html =~ /stran:\s*<\/td><td><strong>(.*?)<\/strong>/;
	# rok vydani originalu
#	$h->{cr_year} = $1 if $html =~ /Rok (?:1\. )?vyd.*?<strong>(.*?)<\/strong>/;
	## $html
}


sub generate_imgname {
	my $ctx = Digest::MD5->new();
	$ctx->add($_[0]);
	return $ctx->hexdigest;
#	print $ctx->hexdigest ."\n";
}


sub perl2xml {
	my $out = new XML::Writer(OUTPUT => *STDOUT);
	print '<?xml version="1.0" encoding="UTF-8"?>';
	print '<!DOCTYPE tellico PUBLIC "-//Robby Stephenson/DTD Tellico V9.0//EN" "http://periapsis.org/tellico/dtd/v9/tellico.dtd">';
	$out->startTag("tellico",syntaxVersion => 9, xmlns => "http://periapsis.org/tellico/");
		$out->startTag("collection", title => "My Books", type => 2);
			$out->startTag("fields");
				$out->emptyTag("field", name => "_default");
				$out->emptyTag("field", title=>"Link", flags=>"0", category=>encode_utf8("Obecné"), format=>"4", description=>"Odkaz", type=>"7", name=>"link");
			$out->endTag("fields");

	for (my $i = 0; $i < scalar(@BOOKS); $i++) {			
			$out->startTag("entry",id=>$i);
		foreach my $key ( sort keys %{ $BOOKS[$i] } ) {
				if ( ref($BOOKS[$i]->{$key}) eq 'ARRAY' ) {
					$out->startTag($key.'s');
						foreach (@{ $BOOKS[$i]->{$key} }) {
							$out->dataElement($key,$_ ? encode_utf8($_): '');
						}
					$out->endTag($key.'s');
				} else {
					$out->dataElement($key,$BOOKS[$i]->{$key} ? encode_utf8($BOOKS[$i]->{$key}) : '');
				}
		}
			$out->endTag("entry");
	}
	if ( @IMAGES) {
			$out->startTag("images");
		foreach my $img (@IMAGES) {
				my $data = delete $img->{data};
				$out->dataElement( "image", $data, %$img );
				#$out->emptyTag("image",%$img);
		}
			$out->endTag("images");
	}
		$out->endTag("collection");
	$out->endTag("tellico");
	$out->end();
}


