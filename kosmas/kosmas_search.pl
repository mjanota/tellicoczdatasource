#!/usr/bin/perl -w

use strict;

use LWP::Simple;
use Getopt::Std;
use Data::Dumper;
#use Smart::Comments;
use HTML::TreeBuilder;
use Encode;
use Cz::Cstocs;
sub win1250_utf8;
*win1250_utf8 = new Cz::Cstocs '1250', 'utf8';
sub utf8_ascii;
*utf8_ascii = new Cz::Cstocs 'utf8', 'ascii';
use utf8;
use XML::Writer;
use IO::File;

use Digest::MD5;
use MIME::Base64 qw(encode_base64);


my $ADDRESS = 'http://www.kosmas.cz';
my $TMPADDR = '/tmp/czech_book_search_' . $$;
my @BOOKS;
my @IMAGES;
my $html;

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

my %optw = (
    a => 'Author',
	i => 'ISBN_EAN',
    l => 'Illustrator',
    p => 'Publisher',
    r => 'Translator',
    t => 'Title',     
);

my $post_data = join "&", ('sortBy=datum', 
    map  { 
	    $option{$_} =~ s/(\s+)/+/g;
	    "Filters." . $optw{$_} . "=" . lc( utf8_ascii($option{$_}) );
	 } grep( $option{$_}, keys %option ) );
### $post_data

$html = `wget -q -O '-'  --post-data='$post_data' $ADDRESS/hledani`;

## $html;

 
my @refs = get_ref($html);


exit 0 if scalar @refs < 1;

foreach my $ref (@refs) {
        ### $ref
		$html = `wget -q -O '-' ${ADDRESS}$ref`;
        ## html
#		$html = get($ADDRESS.$ref);
		push @BOOKS, html2perl($html);
}	


### @BOOKS

&perl2xml if scalar @BOOKS > 0;


#####################################################################
#					Functions										#
#####################################################################


sub get_ref {
	my $Tree = HTML::TreeBuilder->new_from_content(decode_utf8($_[0]));
	## $Tree
	my @a =  $Tree->look_down( _tag => 'a', class => 'titul-title');
	my @refs ;

	foreach my $ref (@a) {
		push @refs, $ref->attr('href');
	}

	return @refs;
}


sub html2perl {
	my $Tree = HTML::TreeBuilder->new_from_content(decode_utf8($_[0]));
#my $Tree = HTML::TreeBuilder->new_from_content(decode_utf8($_[0]));
	my %h;	
	get_data(\%h,$Tree);
	get_titul(\%h,$Tree);
    get_comments(\%h,$Tree);

	my $img = $Tree->look_down(_tag => 'img', class=> 'detail-cover-image');
	push @IMAGES, get_image(\%h,$img->attr('src')) if $img;
	return \%h; 
#	print Dumper(\%H);
}

sub get_data {
	my $h = shift;
	my $tree = shift;
	my $div = $tree->look_down(_tag => 'div', class => 'titul-info-left');
	my @lis = $div->look_down( _tag => 'li');
	foreach ( @lis ) {
		if ( $_->as_trimmed_text =~ /(nakladatel|isbn|orig|rok|eklad|popis)/i ) {
			my $fce = 'get_' . lc($1);
			eval {
				no strict;
				### $fce
				&{$fce}($h,$_->as_trimmed_text) if defined &$fce;		
	
			};
			die $@ if ($@);
		}
	}
}

sub get_titul {
	my $h = shift;
	my $tree = shift;
	my $head = $tree->look_down( _tag => 'div', class => 'detail-heading');
	return unless $head;
	$h->{title} = $head->look_down( _tag => 'h1')->as_trimmed_text;
	my @authors = $head->look_down( _tag => 'h2', class => 'authors' );
	foreach my $auth ( @authors ) {
		push @{ $h->{author} }, $auth->as_trimmed_text; 
	}
}

my $I = 0;
sub get_image {
	my $h = shift;
	my $src = shift;
	my %img;
	my $imgdata = `wget -q -O '-' $src`;
	my $imgname = generate_imgname($imgdata) . ".gif";
	$$h{cover} = $imgname; 	
	$img{format} = 'GIF';
	$img{id} = $imgname;
	$img{width} = 100;
	$img{height} = 150;
#	$img{'link'} = 'true';
	$img{data} = encode_base64($imgdata); 
#	print "$src.\n";
	return { %img };
}

sub get_nakladatel {
	my ($h,$r) = @_;
	my ($p,$s) = $r =~ /^Nakladatel:\s*(.*?)(?:, edice: (.*);)?$/;
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
	my ($p) = $r =~ /Originál:\s*(.*?)\s*$/;
	$$h{encode_utf8('název-originálu')} = $p if $p;
}

sub get_eklad {
	my ($h,$r) = @_;
	### $r
	my ($s) = $r =~ /eklad:\s*(.*?)\s*$/;
	my @eklads = split /,\s*/, $s;
	for ( my $i = 0; $i < scalar(@eklads); $i+=2) {
		push @{ $$h{translator} }, $eklads[$i] . ", " . $eklads[$i+1]
	}
}

sub get_popis {
	my ($h,$r) = @_;
	## $r
	$r =~ /Popis:\s*(.*?)$/;
	my @a = split ', ', $1;
    ### @a
	if (scalar(@a) == 5 ) {
		shift @a;
	}
	$a[1] =~ /(\d+)\s*stran/;
	$$h{pages} = $1 if $1; 
	$$h{language} = $a[3];
	$$h{binding} = $a[0];
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

sub get_comments {
    my $h = shift;
    my $tree = shift;
    $h->{comments} = $tree->look_down( _tag => 'div', class => 'detail-description' )->as_trimmed_text;
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
				$out->dataElement( "image",$data, %$img );
				#$out->emptyTag("image",%$img);
		}
			$out->endTag("images");
	}
		$out->endTag("collection");
	$out->endTag("tellico");
	$out->end();
}


