package ClipToEvernote::CMS;
use strict;
use warnings;
use ClipToEvernote::OAuth;
use ClipToEvernote::Client;

sub show_widget {
    my ( $app ) = @_;
    my $plugin = MT->component('cliptoevernote');
    my %param;

    my $user = $app->user;
    if ( $app->param('signout') ) {
        $user->evernote_oauth_token('');
        $user->save;
    }
    my $entry = MT->model('entry')->load($app->param('entry_id'));
    my ( $guid, $notebook_guid );
    my $ever = ClipToEvernote::Client->new($app);
    if ( $ever ) {
        my $notebooks = $ever->proc('listNotebooks');
        if ( !$notebooks ) {
            my $errstr = $ever->errstr
                or die "Failed to access Evernote";
            chomp $errstr;
            if ( $errstr eq 'EXPIRED' ) {
                $ever = undef;
            }
            else {
                return $app->error( $errstr );
            }
        }
        else {
            $param{evernote_notebooks} = [ map {
                {   name    => Encode::decode_utf8( $_->{name} ),
                    guid    => $_->{guid},
                    default => $notebook_guid             ? $_->{guid} eq $notebook_guid
                             : defined $guid              ? 0
                             : $_->{defaultNotebook}      ? 1
                             :                              0,
                }
            } @$notebooks ];
        }
    }
    if ( $entry && ( $guid = $entry->evernote_note_guid )) {
        $param{evernote_note_guid} = $guid;
        $param{evernote_note_url}  = ClipToEvernote::Client::url() . 'Home.action#n=' . $guid;
        if ( $ever && ( my $note = $ever->proc('getNote', $guid) )) {
            $param{evernote_notebook_guid} = $notebook_guid = $note->{notebookGuid};
        }
    }
    $plugin->load_tmpl('evernote_widget.tmpl', \%param);
}

sub close_dialog {
    my ( $app ) = @_;
    my $plugin = MT->component('cliptoevernote');
    return $plugin->load_tmpl('close_dialog.tmpl');
}

sub get_oauth_client {
    my $plugin = MT->component('cliptoevernote');
    return ClipToEvernote::OAuth->new(
        consumer_key    => $plugin->get_config_value('consumer_key',    'system'),
        consumer_secret => $plugin->get_config_value('consumer_secret', 'system'),
    );
}

sub start_handshake {
    my $app = shift;
    my $client = get_oauth_client();
    my $res = $client->get_temporary_credentials;
    return $app->error( 'failed to start OAuth session: ' . $client->errstr )
        unless $res;
    my $redirect  = $app->param('redirect');
    my $author_id = $app->user->id;

    ## FIXME: set cookie expire
    my $cookie = $app->bake_cookie (
        -name => 'evernote_oauth_credential',
        -value => {
            author_id    => $author_id,
            redirect     => $redirect,
            token        => $res->{token},
            token_secret => $res->{token_secret},
        },
        -path=>'/',
    );
    $app->redirect(
        $res->{redirect_url},
        UseMeta => 1,
        -cookie => $cookie
    );
}

sub verify_handshake {
    my $app = shift;
    my $q = $app->param;
    my %cookie = $q->cookie('evernote_oauth_credential');
    my $client = get_oauth_client();
    if ( !$q->param('oauth_verifier') || !$cookie{'token'} ) {
        return $app->forward('evernote_close_dialog')
    }
    my $token = $client->get_access_tokens(
        request_token        => $cookie{token},
        request_token_secret => $cookie{token_secret},
        oauth_token          => $q->param('oauth_token'),
        oauth_verifier       => $q->param('oauth_verifier'),
    ) or $app->error( 'Failed to get OAuth token: ' . $client->errstr );

    my $user = $app->user;
    $user->evernote_oauth_token($token);
    $user->save;
    return $app->forward('evernote_close_dialog');
}

1;
