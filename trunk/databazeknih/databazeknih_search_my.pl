#!/usr/bin/perl -w

use strict;

use LWP::Simple;
use Getopt::Std;
use Data::Dumper;
#use Smart::Comments;
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

my $getdata = sprintf'?q=%s&hledat=Vyhledat&stranka=search',$title;
### $getdata

$html = `wget -q -O '-'  $ADDRESS/search$getdata`;

## $html

 
my @refs = get_ref($html);

### @refs

exit 0 if scalar @refs < 1;

foreach my $ref (@refs) {
		$html = `wget -q -O '-' $ADDRESS/$ref`;
#		$html = get($ADDRESS.$ref);
		push @BOOKS, html2perl($html);
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
	return () unless $Tree->look_down( _tag => 'ul', class => 'search_book');
	my @a =  $Tree->look_down( _tag => 'ul', class => 'search_book')->look_down( _tag => 'li');
	my @refs ;

	foreach my $ref (@a) {
		push @refs, $ref->look_down( _tag => 'a')->attr('href');
	}

	return @refs;
}


sub html2perl {
	my $Tree = HTML::TreeBuilder->new_from_content(decode_utf8($_[0]));
  my $content = $Tree->look_down( _tag => 'div', id => 'content');
#my $Tree = HTML::TreeBuilder->new_from_content(decode_utf8($_[0]));
	my %h;	
	get_titul(\%h,$content);
	get_data(\%h,$content);

	my $img = $content->look_down(_tag => 'img', class=> 'kniha_img');
	push @IMAGES, get_image(\%h,$img->attr('src')) if $img;
	return \%h; 
#	print Dumper(\%H);
}

sub get_data {
	my $h = shift;
	my $tree = shift;
  # rok vydani, pocet stran
  get_year_pages($h,$tree->look_down(_tag => 'p', class => 'binfo odtopm')->as_trimmed_text) if $tree->look_down(_tag => 'p', class => 'binfo odtopm');
   
  my $pmore  = $tree->look_down( _tag => 'p', id => 'more_binfo');
  return unless $pmore;
  get_publisher($h,$pmore);
  get_isbn($h,$pmore);
  get_translator($h,$pmore);
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
	### src: basename($src)
	my %img;
	my $imgdata = `wget -q -O '-' $ADDRESS/$src`;
	
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
	@{$$h{publisher}} = map {$_->as_trimmed_text} @publishers if @publishers;
	$h->{edice} = $pmore->look_down( _tag => 'a', href => qr/edice/)->as_trimmed_text if $pmore->look_down( _tag => 'a', href => qr/edice/);
}

sub get_isbn {
	my ($h,$pmore) = @_;
	$$h{isbn} = $pmore->look_down( _tag => 'span', itemprop => 'identifier')->as_trimmed_text if $pmore->look_down( _tag => 'span', itemprop => 'identifier');
}


sub get_translator {
	my ($h,$pmore) = @_;
	my @itrans = $pmore->look_down( _tag => 'a', href => qr/prekladatele/);
#	@{ $$h{translator} } = map {$_->as_trimmed_text} @itrans if @itrans;
	@{ $$h{encode_utf8('překladatel')} } = map {$_->as_trimmed_text} @itrans if @itrans; 
}

sub get_year_pages {
	my ($h,$r) = @_;
	$r =~ /Rok vydání:\s*(\d+)/;
	$$h{pub_year} = $1 if $1;
	$r =~ /stran:\s*(\d+)/;
	$$h{pages} = $1 if $1;
}

sub get_from_html {
	my ($h, $pmore) = @_;
	my $html = $pmore->as_HTML;
	# vazba
	$h->{binding} = $1 if $html =~ /Vazba knihy:\s*<strong>(.*?)<\/strong>/;
	# rok vydani originalu
	$h->{cr_year} = $1 if $html =~ /Rok (?:1\. )?vyd.*?<strong>(.*?)<\/strong>/;
	## $html
}


sub generate_imgname {
	my $ctx = Digest::MD5->new();
	$ctx->add($_[0]);
	return $ctx->hexdigest;
#	print $ctx->hexdigest ."\n";
}


sub perl2xml {
	my $fh = new IO::File(*STDOUT);
	my $out = new XML::Writer(OUTPUT => $fh);
	print '<?xml version="1.0" encoding="UTF-8"?>';
	print '<!DOCTYPE tellico PUBLIC "-//Robby Stephenson/DTD Tellico V9.0//EN" "http://periapsis.org/tellico/dtd/v9/tellico.dtd">';
	$out->startTag("tellico",syntaxVersion => 9, xmlns => "http://periapsis.org/tellico/");
		$out->startTag("collection", title => "My Books", type => 2);
			$out->startTag("fields");
				$out->emptyTag("field", flags=>"4", title=>encode_utf8("Název"), 			category=>encode_utf8("Obecné"), 		format=>"4", 	type=>"1", 	name=>"title");
   				$out->emptyTag("field", flags=>"7", title=>encode_utf8("Autor"),			category=>encode_utf8("Obecné"), 		format=>"2", 	type=>"1", 	name=>"author");
				$out->emptyTag("field", flags=>"3", title=>encode_utf8("Název originálu"),	category=>encode_utf8("Obecné"), 		format=>"4", 	type=>"1", 	name=>encode_utf8("název-originálu"));
   				$out->emptyTag("field", flags=>"0", title=>encode_utf8("Podtitul"),			category=>encode_utf8("Obecné"), 		format=>"1", 	type=>"1", 	name=>"subtitle");
   				$out->emptyTag("field", flags=>"0", title=>encode_utf8("Kupní cena"),		category=>encode_utf8("Publikování"), 	format=>"4", 	type=>"1", 	name=>"pur_price");
				$out->emptyTag("field", flags=>"7", title=>encode_utf8("Vydavatel"), 		category=>encode_utf8("Obecné"), 		format=>"4", 	type=>"1", 	name=>"publisher");
   				$out->emptyTag("field", flags=>"6", title=>encode_utf8("Edice"), 			category=>encode_utf8("Obecné"), 		format=>"4", 	type=>"1", 	name=>"edice");
   				$out->emptyTag("field", flags=>"0", title=>encode_utf8("Žánr"), 			category=>encode_utf8("Obecné"), 		allowed=>encode_utf8("Román;Novela;Povídky;Epos;Legenda;Básně;Divadelní hra;Pohádka;Paměti;Kronika;Deníky;Dopisy;Rozhovor;Literatura faktu;Esej;Technická literatura;Časopis;Dějiny"), 			format=>"4", type=>"3", name=>encode_utf8("žánr"));
   				$out->emptyTag("field", flags=>"0", title=>encode_utf8("Číslo svazku"), 	category=>encode_utf8("Obecné"), 		format=>"4", 	type=>"1", 	name=>encode_utf8("číslo-svazku"));
   				$out->emptyTag("field", flags=>"1", title=>encode_utf8("Vydání"), 			category=>encode_utf8("Publikování"), 	format=>"0", 	type=>"6", 	name=>"edition");
   				$out->emptyTag("field", flags=>"3", title=>encode_utf8("Rok copyrightu"), 	category=>encode_utf8("Publikování"), 	format=>"4", 	type=>"6", 	name=>"cr_year");
   				$out->emptyTag("field", flags=>"2", title=>encode_utf8("Rok vydání"),		category=>encode_utf8("Publikování"), 	format=>"4", 	type=>"6", 	name=>"pub_year");
   				$out->emptyTag("field", flags=>"0", title=>encode_utf8("ISBN č. "), 		category=>encode_utf8("Publikování"), 	format=>"4", 	type=>"1", 	name=>"isbn", description=>encode_utf8("Mezinárodní standardní knižní číslo"));
   				$out->emptyTag("field", flags=>"2", title=>encode_utf8("Vazba"), 			category=>encode_utf8("Publikování"), 	allowed=>encode_utf8("E-Book;Paperback;Žurnál;Časopis;Velký paperback;Vázaná;Brožovaná;Pevná vazba;vázaná;brožovaná"), 																			format=>"4", type=>"3", name=>"binding");
   				$out->emptyTag("field", flags=>"0", title=>encode_utf8("Stran"), 			category=>encode_utf8("Publikování"), 	format=>"4", 	type=>"6", 	name=>"pages");
   				$out->emptyTag("field", flags=>"7", title=>encode_utf8("Jazyk originálu"),	category=>encode_utf8("Publikování"), 	format=>"4",	type=>"1", 	name=>"language");
   				$out->emptyTag("field", flags=>"7", title=>encode_utf8("Překladatel"), 		category=>encode_utf8("Publikování"), 	format=>"2",	type=>"1", 	name=>encode_utf8("překladatel"));
   				$out->emptyTag("field", flags=>"2", title=>encode_utf8("Datum nabytí"), 	category=>encode_utf8("Osobní"), 		format=>"3",	type=>"12", name=>encode_utf8("datum-nabytí"));
   				$out->emptyTag("field", flags=>"0", title=>encode_utf8("Datum pozbytí"), 	category=>encode_utf8("Osobní"), 		format=>"3", 	type=>"12", name=>encode_utf8("datum-pozbytí"));
   				$out->emptyTag("field", flags=>"6", title=>encode_utf8("Knihkupectví"), 	category=>encode_utf8("Osobní"), 		format=>"4", 	type=>"1",	name=>encode_utf8("knihkupectví"));
   				$out->emptyTag("field", flags=>"0", title=>encode_utf8("Stav"), 			category=>encode_utf8("Osobní"), 		allowed=>encode_utf8("Sleva;Použitá;Nová;Antikvariát;Nový"), format=>"4", type=>"3", name=>"condition");
   				$out->emptyTag("field", flags=>"6", title=>encode_utf8("Stav 2"), 			category=>encode_utf8("Osobní"),			format=>"4", 	type=>"1", 	name=>"stav-2");
   				$out->emptyTag("field", flags=>"3", title=>encode_utf8("Přečtená"), 		category=>encode_utf8("Osobní"), 		format=>"4", 	type=>"1", 	name=>encode_utf8("přečtená"));
   				$out->startTag("field", flags=>"2", title=>encode_utf8("Hodnocení"), 		category=>encode_utf8("Osobní"), 		format=>"4", 	type=>"14",	name=>"rating");
   					$out->dataElement("prop",10, name=>"maximum");
   					$out->dataElement("prop",1, name=>"minimum");
				$out->endTag("field");
   				$out->emptyTag("field", flags=>"4", title=>encode_utf8("Umístění"), 		category=>encode_utf8("Osobní"), 		format=>"4", 	type=>"1", 	name=>encode_utf8("umístění"));
   				$out->startTag("field", flags=>"1", title=>encode_utf8("Hlavní postavy"), 	category=>encode_utf8("Hlavní postavy"), format=>"4", 	type=>"8", 	name=>encode_utf8("hlavní-postavy"));
   					$out->dataElement("prop",1, name=>"columns");
   				$out->endTag("field");
   				$out->emptyTag("field", flags=>"0", title=>encode_utf8("Téma"), 			category=>encode_utf8("Téma"), 			format=>"4", 	type=>"2", 	name=>"comments");
   				$out->emptyTag("field", flags=>"0", title=>encode_utf8("Přední obálka"), 	category=>encode_utf8("Přední obálka"), 	format=>"4", 	type=>"10",	name=>"cover");
   				$out->emptyTag("field", flags=>"2", title=>encode_utf8("Půjčená"), 			category=>encode_utf8("Osobní"), 		format=>"4", 	type=>"4", 	name=>"loaned");
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


