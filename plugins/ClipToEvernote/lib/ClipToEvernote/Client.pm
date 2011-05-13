package ClipToEvernote::Client;
use strict;
use warnings;
use Encode;
use MT;
use MT::Entry;
use HTML::Parser;
use Thrift::HttpClient;
use Thrift::BinaryProtocol;
use EDAMTypes::Types;
use EDAMErrors::Types;
use EDAMNoteStore::NoteStore;

sub url {
    return MT->config->EvernoteDebug
        ? 'https://sandbox.evernote.com/' # for debug
        : 'https://www.evernote.com/';
}

sub endpoint {
    return url() . 'edam/note/';
}

sub new {
    my $pkg   = shift;
    my $app   = shift or die "Internal error: app is required";
    my $user  = $app->user or die "User is required";
    my $token = $user->evernote_oauth_token
        or return;
    my %param = map { split '=', $_ } split ':', $token;
    my $share = $param{S};
    my $endpoint = endpoint();
    $endpoint .= Encode::encode_utf8($share);
    my $note_http_client = new Thrift::HttpClient( Encode::encode_utf8($endpoint) );
    my $note_protocol    = new Thrift::BinaryProtocol($note_http_client);
    my $client           = new EDAMNoteStore::NoteStoreClient($note_protocol, $note_protocol);
    return bless {
        endpoint => $endpoint,
        token    => $token,
        client   => $client,
    }, $pkg;
}

sub proc {
    my $self    = shift;
    my $command = shift;
    my $result;
    eval { $result = $self->{client}->$command( $self->{token}, @_) };
    if ( my $exception = $@ ) {
        if ( !ref $exception ) {
            MT->log('Failed to access Evernote: ' . $exception);
            return;
        }
        if ( $exception->{errorCode} == EDAMErrors::EDAMErrorCode::AUTH_EXPIRED ) {
            #TBD
            use Data::Dumper;
            print STDERR Dumper $exception;
        }
        else {
            use Data::Dumper;
            print STDERR Dumper $exception;
        }
    }
    return $result;
}

sub entry2note {
    my $self = shift;
    my ( $entry, $notebook_guid ) = @_;
    my ( $note, $method );
    if ( my $guid = $entry->evernote_note_guid ) {
        $note   = $self->proc('getNote', $guid);
        $method = 'updateNote';
    }
    else {
        $note ||= new EDAMTypes::Note();
        $note->{active}  = 1;
        $note->{created} = time * 1000;
        $method = 'createNote';
    }
    $note->{notebookGuid} = $notebook_guid;
    $note->{title}        = $entry->title;
    my $text    = _cleanup_enml( $entry->text );
    my $content = <<"ENML";
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">
<en-note>
$text
</en-note>
ENML
    $note->{content} = $content;
    return $self->proc($method, $note);
}

{
    my @allowed_elems = qw(
    A ABBR ACRONYM ADDRESS AREA B BDO BIG BLOCKQUOTE BR CAPTION CENTER CITE CODE COL COLGROUP DD DEL DFN DIV DL DT EM FONT H1 H2 H3 H4 H5 H6 HR I IMG INS KBD LI MAP OL P PRE Q S SAMP SMALL SPAN STRIKE STRONG SUB SUP TABLE TBODY TD TFOOT TH THEAD TITLE TR TT U UL VAR XMP
    );
    my %allowed_elems = map { lc $_ => 1 } @allowed_elems;

    my @disallowed_attrs = qw(
        id class accesskey data dynsrc tabindex
    );
    my %disallowed_attrs = map { $_ => 1 } @disallowed_attrs;

    sub _cleanup_enml {
        my ($str) = @_;
        return $str unless $str =~ /</;
        my $p = HTML::Parser->new();
        my $out = '';
        $p->handler(text  => sub { $out .= $_[1]; } );
        $p->handler(start => sub {
            my $p = shift;
            my ( $tag, $attr_hash, $attr_array, $txt ) = @_;
            if ( $allowed_elems{ lc $tag } ) {
                $out .= "<$tag";
                my @ok_attrs;
                for my $attr ( @$attr_array ) {
                    next if $disallowed_attrs{$attr};
                    next if $attr =~ /^on/i;
                    if ( $attr eq '/' ) {
                        push @ok_attrs, '/';
                    }
                    else {
                        push @ok_attrs, sprintf( ' %s = "%s"', $attr, $attr_hash->{$attr} );
                    }
                }
                $out .= join ' ', @ok_attrs;
                $out .= '>';
            }
        });

        $p->handler( end => sub {
            my $p = shift;
            my ( $tag, $txt ) = @_;
            if ( $allowed_elems{ lc $tag } ) {
                $out .= "</$tag>";
            }
        });
        $p->parse($str);
        $out;
    }
}

1;
