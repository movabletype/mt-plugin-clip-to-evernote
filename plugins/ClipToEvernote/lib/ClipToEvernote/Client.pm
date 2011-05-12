package ClipToEvernote::Client;
use strict;
use warnings;
use Encode;
use MT;
use MT::Entry;
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
    my $note_protocol = new Thrift::BinaryProtocol($note_http_client);
    my $client = new EDAMNoteStore::NoteStoreClient($note_protocol, $note_protocol);
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
            use Data::Dumper;
            print STDERR Dumper $@;
        }
    }
    return $result;
}

sub entry2note {
    my $self = shift;
    my ( $entry, $notebook_guid ) = @_;
    my ( $note, $method );
    if ( my $guid = $entry->evernote_note_guid ) {
        $note = $self->proc('getNote', $guid);
        $method = 'updateNote';
    }
    else {
        $note ||= new EDAMTypes::Note();
        $note->{active} = 1;
        $note->{created} = time * 1000;
        $method = 'createNote';
    }
    $note->{notebookGuid} = $notebook_guid;
    $note->{title} = $entry->title;

    my $text = $entry->text;
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

1;
