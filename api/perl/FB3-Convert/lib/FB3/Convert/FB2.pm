package FB3::Convert::FB2;

use strict;
use base 'FB3::Convert';
use XML::LibXML;
use File::Basename;
use File::Temp qw(tempfile tempdir);
use Encode qw(encode_utf8 decode_utf8);
use MIME::Base64 qw(decode_base64);
use Clone qw(clone);
use utf8;

my $XPC = XML::LibXML::XPathContext->new;

sub Reaper {
  my $self = shift;
  my $X = shift;

  my %Args = @_;
  my $Source = $Args{'source'} || $X->Error("Source path not defined");
	my $TmpDir;
	if (!$X->{'src_type'} && -d $Source) {
		$TmpDir = $Source;
		opendir(DH, $Source);
		for (readdir(DH)){
			if (lc($_) =~ /\.fb2$/) {
				$Source = $Source.'/'.$_;
				last;
			}
		}
		closedir(DH);
	}

	$X->Error("File '.fb2' not defined") if (!$X->{'src_type'} && lc($Source) !~ /\.fb2$/);

  my $XC = XML::LibXML::XPathContext->new();
	
	my $FB2Doc = XML::LibXML->load_xml( location => $Source );
	$FB2Doc->setEncoding('utf-8');

	$XPC->registerNs('fb', 'http://www.gribuser.ru/xml/fictionbook/2.0');

	#fix FB2 with regular expression checks (what XLST 1.0 can't do itself)
	my $IsValidUUIDRegEx = qr/^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$/;
	my( $FB2IdNode ) = $XPC->findnodes(
		'/fb:FictionBook/fb:description/fb:document-info/fb:id/text()', $FB2Doc );
	if( $FB2IdNode && $FB2IdNode->data !~ $IsValidUUIDRegEx ) {
		$FB2IdNode->setData( '00000000-0000-0000-0000-000000000000' );
	}
	for my $PersonNode ( $XPC->findnodes(
			'/fb:FictionBook/fb:description/fb:title-info/fb:author
			| /fb:FictionBook/fb:description/fb:title-info/fb:translator', $FB2Doc )) {

		my( $IdTextNode ) = $XPC->findnodes( 'fb:id/text()', $PersonNode );
		if( $IdTextNode && $IdTextNode->data !~ $IsValidUUIDRegEx ) {
			$IdTextNode->setData( '00000000-0000-0000-0000-000000000000' );
		}
	}
	my( $PublishInfoNode ) =
		$XPC->findnodes( '/fb:FictionBook/fb:description/fb:publish-info', $FB2Doc );
	if( $PublishInfoNode ) {
		my $IsValidISBNRegEx = qr/([0-9]+[\-\s]){3,6}[0-9]*[xX0-9]/;
		for my $ISBNNode ( $XPC->findnodes( 'fb:isbn', $PublishInfoNode )) {
			my $ISBN = $ISBNNode->textContent;
			unless( $ISBN =~ /^$IsValidISBNRegEx$/ ) {
				my $FixedISBN;
				if( $ISBN =~ /^[0-9]{10,13}$/ ) {
					# this is ISBN without separators. Need just to prettify it
					if( length( $ISBN ) == 10 ) {
						# ISBN 10, format it as 5-699-15000-5
						$FixedISBN = substr($ISBN,0,1).'-'.substr($ISBN,1,3).'-'.substr($ISBN,4,5).
							'-'.substr($ISBN,9);
					} else {
						# ISBN 13, format it as 978-5-17-084861-4
						$FixedISBN = substr($ISBN,0,3).'-'.substr($ISBN,3,1).'-'.substr($ISBN,4,2).
							'-'.substr($ISBN,6,6).'-'.substr($ISBN,12);
					}
				} elsif( $ISBN =~ /($IsValidISBNRegEx)/ ) {
					# Whole ISBN is invalid, but it contains valid ISBN inside
					$FixedISBN = $1;
				}
				if( $FixedISBN ) {
					my( $ISBNTextNode ) = $XPC->findnodes( 'text()', $ISBNNode );
					$ISBNTextNode->setData( $FixedISBN );
				} else {
					# this is completely corrupted ISBN, throw it away
					$PublishInfoNode->removeChild( $ISBNNode );
					#warn "Removed ISBN '$ISBN' as it's not matching pattern for valid ISBNs in FB3";
				}
			}
		}
	}

	# корректируем заголовок сноски: берём текст между фигурными/квадратными скобками
	my $AutoNoteNumber = 0;
	for my $note ( $XPC->findnodes('//fb:a[@type="note"]', $FB2Doc) ) {
	  if ( my $text = [ $note->findnodes('./text()') ]->[0] ) {
      $text->setData($1) if ( $text->data =~ /\[(\w+)\]/ or $text->data =~ /\{(\w+)\}/ );
	  }
	  else {
	    # если в заголовке сноски нет ничего, формируем самостоятельно
	    $note->appendTextNode('#' . ++$AutoNoteNumber);
	  }
	}

	# Особо сложные эпиграфы порубим на куски тут. TODO полностью перенести работу с эпиграфами сюда.
	for my $Cite ( $XPC->findnodes('//fb:epigraph/fb:cite[1]', $FB2Doc )) {
		my @SetInEpigraph;
		for my $Sibling ( $XPC->findnodes('following-sibling::*', $Cite)) { # всё что после первого cite выделяем в отдельный эпиграф
			push @SetInEpigraph, $Sibling;
			if ($Sibling->nodeName eq 'cite') {
				CreateEpigraph($FB2Doc, $Cite->parentNode, @SetInEpigraph);
				@SetInEpigraph = ();
			}
		}
		CreateEpigraph($FB2Doc, $Cite->parentNode, @SetInEpigraph); # сбросим хвост
	}

	# приведём в порядок цитаты без текста, только с заголовками
	for my $Cite ( $XPC->findnodes('//fb:section/fb:cite', $FB2Doc )) {

		# текст циаты найден, всё в порядке, идём дальше
		next if scalar $XPC->findnodes('./fb:p|./fb:poem', $Cite);

		# если не нашли ни заголовков ни текста -- удаляем цитату и идём дальше
		my @Titles = $XPC->findnodes('./fb:subtitle', $Cite);
		unless ( scalar @Titles ) {

			$Cite->unbindNode();
			next;
		}

		for my $Title ( @Titles ) {

			for my $Node ( $XPC->findnodes('*', $Title) ) {

				$Cite->appendChild($Node);
			}

			if ( my $Text = $Title->textContent ) {

				my $PNode = $FB2Doc->createElement('p');
				$PNode->appendTextNode($Text);

				$Cite->appendChild($PNode);
			}

			$Title->unbindNode();
		}

		for my $EmptyLine ( $XPC->findnodes('./fb:subtitle/following-sibling::empty-line', $Cite) ) {

			$EmptyLine->unbindNode();
		}
	}

	# Работаем с картинками, которые нужно выделить в div или section
	for my $ImgNode ( $XPC->findnodes('//fb:section[ancestor::fb:body[not(@name="notes")]]/fb:image', $FB2Doc )) {
		# Ищем подпись. Все <p> до <empty-line/>, но не более 300 символов.
		my @SubscrNodes;
		my $ImgSubscrLength;
		# удалим пустые строки до картинки. Этот кусок можно в будущем использовать для нахождения подписи до картинки
		my @NodesForDelete;
		my $PrevSibling = $ImgNode;
		while ($PrevSibling = $PrevSibling->previousSibling()) {
			if ($PrevSibling->nodeName eq 'empty-line') {
				push @NodesForDelete, $PrevSibling;
			} else {
				last;
			}
		}
		foreach (@NodesForDelete) {
			$_->unbindNode();
		}
		# найдем подпись и удалим пустые строки после картинки
		my $EmptyLineFound = 0;
		for my $Sibling ( $XPC->findnodes('following-sibling::*', $ImgNode )) {
			if ($ImgSubscrLength <= 300) {
				my $SiblingName = $Sibling->nodeName;
				if ($SiblingName eq 'p' && !$EmptyLineFound) {
					$ImgSubscrLength += length($Sibling->textContent);
					push @SubscrNodes, $Sibling;
				} elsif ($SiblingName eq 'empty-line') {
					$Sibling->unbindNode();
					$EmptyLineFound = 1;
				} else {
					@SubscrNodes = () unless $EmptyLineFound;
					last;
				}
			} else {
				@SubscrNodes = ();
				last;
			}
		}

		# Перенесем подпись и картинку куда положено
		# Переносим картинку
		my $ParentNode = $ImgNode->parentNode;
		my $PNode = $FB2Doc->createElement('p');
		my $NextSibling = $ImgNode->nextNonBlankSibling();
		my $NewParentNode;
		if ($XPC->exists('following-sibling::fb:section', $ImgNode)) {
			$NewParentNode = $FB2Doc->createElement('section');
		} else {
			$NewParentNode = $FB2Doc->createElement('div');
			$NewParentNode->setAttribute('float', 'center');
			$NewParentNode->setAttribute('on-one-page', '1');
		}
		$ParentNode->insertBefore($NewParentNode, $ImgNode);
		$NewParentNode->appendChild($PNode);
		$PNode->appendChild($ImgNode);
		#Переносим подпись
		foreach (@SubscrNodes) {
			$NewParentNode->appendChild($_);
		}
	}

	$TmpDir ||= tempdir(CLEANUP=>1);

	my $TmpFB2File = "$TmpDir/book.fb2";
	open my $fh, '>:utf8', $TmpFB2File
		or die "Could not open $TmpFB2File for writing";
	print $fh decode_utf8($FB2Doc->toString);
	close $fh;
	$X->{'temp_fb2'} = $TmpFB2File;
}

sub CreateEpigraph {
	my $FB2Doc = shift;
	my $Epigraph = shift;
	my @SetInEpigraph = @_;
	return unless scalar @SetInEpigraph;

	my $NewEpigraph = $FB2Doc->createElement('epigraph');
	$Epigraph->parentNode->insertAfter($NewEpigraph, $Epigraph);
	foreach (@SetInEpigraph) {
		$Epigraph->removeChild($_);
		$NewEpigraph->appendChild($_);
	}

	return $NewEpigraph;
}

sub FB3Creator {
	my $self = shift;
	my $X = shift;
  $X->Msg("Create FB3\n","w");

  my $FB3Path = $X->{'DestinationDir'};
	my $XSLT = XML::LibXSLT->new;
	my $FB2Doc = XML::LibXML->load_xml( location => $X->{'temp_fb2'} );

	#prepare directory structure for FB3

	foreach ("/fb3", "/fb3/img", "/fb3/style", "/fb3/meta", "/fb3/_rels", "/_rels"){
	  mkdir "$FB3Path$_";
	}
	$X->Msg("Directory structure is created successfully");

	my @TransformConfig = (
	  {stylesheet => "/body.xsl", output => "/fb3/body.xml"},
	  {stylesheet => "/body_rels.xsl", output => "/fb3/_rels/body.xml.rels"},
	  {stylesheet => "/core.xsl", output => "/fb3/meta/core.xml"}
	);
	unless( -s $FB3Path."/fb3/description.xml" ) {
		# no meta file was given, so need to generate meta from FB2
		push @TransformConfig,
			{stylesheet => "/description.xsl", output => "/fb3/description.xml"};
	}

	#transform
	for (@TransformConfig) {
	  my $Stylesheet = $XSLT->parse_stylesheet_file($X->{'xsl_path'}.$_->{stylesheet});
	  my $Results = $Stylesheet->transform_file( $X->{'temp_fb2'} );
	  $Stylesheet->output_file($Results, $FB3Path.$_->{output});
	}
	unlink $X->{'temp_fb2'}; # удаляем за ненадобностью
	$X->Msg("XML transformation has been successful");

	#extract images
	my ($CoverNode)=$XPC->findnodes('/fb:FictionBook/fb:description/fb:title-info/fb:coverpage/fb:image[1]',$FB2Doc);
	my $CoverID;
	if ($CoverNode){
	  $CoverID=lc($CoverNode->getAttribute('l:href'));
	  $CoverID=~s/^#//;
	}

	my $ImagesFound = 0;
	for ($XPC->findnodes('/fb:FictionBook/fb:binary',$FB2Doc)) {
	  $ImagesFound = 1;

	  my $id=$_->getAttribute('id');
	  $X->Msg("Converting image '$id'...\n");
	  my $ContentType=$_->getAttribute('content-type');

	  if (defined($id) && $ContentType=~ /image\/(jpeg|png)/i) {
	    my $FN="$FB3Path/fb3/img/".lc($id);
	    open IMGFILE, ">$FN" or die "$FN: $!";
	    binmode IMGFILE;
	    print (IMGFILE decode_base64($_->string_value()));
	    close IMGFILE;

	  } elsif (defined($id) && $ContentType=~ /image\/gif/i) {
	    $!=18;
	    die "GIF image found!";
	  } elsif (defined($id) && $ContentType){
	    $!=18;
	    die "Unknown type '$ContentType' binary found!";
	  }
	}
	$X->Msg("Cover image found: $CoverID") if $CoverID;
	$X->Msg("Pictures extracted successfully") if $ImagesFound;

	#extract stylesheets
	my $SheetCount = 0;
	for my $SheetNode ( $XPC->findnodes( '/fb:FictionBook/fb:stylesheet', $FB2Doc )) {
	  $SheetCount++;

	  $X->Msg("Converting #$SheetCount stylesheet...");

	  my $ContentType = $SheetNode->getAttribute('type');
	  unless( $ContentType eq 'text/css' ) {
	    $!=18;
	    die "Can convert only text/css stylesheets, but received a $ContentType";
	  }

	  my $FN="$FB3Path/fb3/style/style$SheetCount.css";
	  open FH, ">", $FN
	    or die "$FN: $!";
	  print FH $SheetNode->string_value;
	  close FH;
	}
	$X->Msg("Stylesheets extracted successfully.") if $SheetCount > 0;

	#compile required files
	my $FN="$FB3Path/[Content_Types].xml";
	open FH, ">$FN" or die "$FN: $!";
	print FH <<EOF;
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
	<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml" />
	<Default Extension="png" ContentType="image/png"/>
	<Default Extension="jpg" ContentType="image/jpeg"/>
	<Default Extension="jpeg" ContentType="image/jpeg"/>
	<Default Extension="gif" ContentType="image/gif"/>
	<Default Extension="svg" ContentType="image/svg+xml"/>
	<Default Extension="xml" ContentType="application/xml"/>
	<Default Extension="css" ContentType="text/css"/>

	<Override PartName="/fb3/meta/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>

	<Override PartName="/fb3/description.xml" ContentType="application/fb3-description+xml"/>
	<Override PartName="/fb3/body.xml" ContentType="application/fb3-body+xml"/>
</Types>
EOF
	close FH;

	my $FN="$FB3Path/_rels/.rels";
	open FH, ">$FN" or die "$FN: $!";
	print FH qq{<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
	<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
		}.( $CoverID ? qq{<Relationship Id="rId0" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail" Target="fb3/img/$CoverID"/>} : '' ).qq{
		<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="fb3/meta/core.xml"/>
		<Relationship Id="rId2" Type="http://www.fictionbook.org/FictionBook3/relationships/Book" Target="fb3/description.xml"/>
	</Relationships>};
	close FH;

	my $FN="$FB3Path/fb3/_rels/description.xml.rels";
	open FH, ">$FN" or die "$FN: $!";
	print FH <<EOF;
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
	<Relationship Id="rId0"
		Target="body.xml"
		Type="http://www.fictionbook.org/FictionBook3/relationships/body" />
</Relationships>
EOF
	close FH;
	$X->Msg("Reference files successfully created.");

	return $FB3Path;
}

1;
