############################################################################
# Copyright © 2011 Six Apart Ltd.
# This program is free software: you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
# version 2 for more details. You should have received a copy of the GNU
# General Public License version 2 along with this program. If not, see
# <http://www.gnu.org/licenses/>.

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
    my ( $guid, $notebook_guid, $notebooks );
    my $ever = ClipToEvernote::Client->new($app);
    if ( $ever ) {
        $notebooks = $ever->proc('listNotebooks');
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
    }
    if ( $entry && ( $guid = $entry->evernote_note_guid ) ) {
        $param{evernote_note_guid} = $guid;
        $param{evernote_note_url}  = ClipToEvernote::Client::url() . 'Home.action#n=' . $guid;
        if ( $ever && ( my $note = $ever->proc( 'getNote', $guid, 1 ) ) ) {
            $param{evernote_notebook_guid} = $notebook_guid
                = $note->{notebookGuid};
            my $entry_modified = 1000
                * MT::Util::ts2epoch( $entry->blog_id, $entry->modified_on );
            $param{evernote_time_diff} = $note->updated - $entry_modified;
            $param{evernote_is_modified}
                = ( $note->updated - $entry_modified ) > 0;
            my $content = $note->content;
            $content =~ m{<en-note>(.*)</en-note>}s;
            $param{evernote_note_content} = $1;
        }
    }
    if ( $notebooks ) {
        $param{evernote_notebooks} = [ map {
            {   name    => Encode::decode_utf8( $_->{name} ),
                guid    => $_->{guid},
                default => $notebook_guid             ? $_->{guid} eq $notebook_guid
                         : !defined $guid             ? 0
                         : $_->{defaultNotebook}      ? 1
                         :                              0,
            }
        } @$notebooks ];
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
        consumer_key    => $plugin->get_config_value('evernote-consumer-key',    'system'),
        consumer_secret => $plugin->get_config_value('evernote-consumer-secret', 'system'),
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
