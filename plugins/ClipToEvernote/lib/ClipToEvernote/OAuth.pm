package ClipToEvernote::OAuth;
use strict;
use warnings;
use MT::App;
use Net::OAuth;
$Net::OAuth::PROTOCOL_VERSION = Net::OAuth::PROTOCOL_VERSION_1_0A;
use base qw( Class::Accessor::Fast MT::ErrorHandler );

__PACKAGE__->mk_accessors(qw(
    consumer_key          consumer_secret     protocol_version
    request_token_url     access_token_url    authorize_url
));

sub new {
    my $pkg = shift;
    my (%param) = @_;
    die "consumer key is required"    unless $param{consumer_key};
    die "consumer secret is required" unless $param{consumer_secret};

    ## CONSTS
    %param = (
        %param, qw(
        request_token_url https://sandbox.evernote.com/oauth
        access_token_url  https://sandbox.evernote.com/oauth
        authorize_url     http://sandbox.evernote.com/OAuth.action
    ));

    return bless \%param, $pkg;
}

sub oauth_request {
    my $self = shift;
    my ( $request_to, %param ) = @_;
    my $app = MT->app;
    my $request = Net::OAuth->request($request_to)->new(
        consumer_key     => $self->consumer_key,
        consumer_secret  => $self->consumer_secret,
        signature_method => 'HMAC-SHA1',
        timestamp        => time(),
        callback         => $app->base . $app->uri(
                                mode => 'evernote_verify_handshake',
                                args => {},
                            ),
        nonce            => substr(MT::App::make_magic_token(), 0, 8),
        %param,
    );
    $request->sign;
    die "COULDN'T VERIFY! Check OAuth parameters.\n"
        unless $request->verify;
    $request;
}

sub get_temporary_credentials {
    my $self = shift;
    my $ua = MT->new_ua;
    my $request = $self->oauth_request(
        'request token',
        request_method => 'POST',
        request_url    => $self->request_token_url,
    );
    my $http_req = HTTP::Request->new('POST', $self->request_token_url);
    $http_req->content( $request->to_post_body );
    $http_req->content_type( 'application/x-www-form-urlencoded' );
    my $res = $ua->request( $http_req );
    die 'Failed to get OAuth Temporary Credentials: ' . $res->status_line
        unless $res->is_success;

    my $response = Net::OAuth->response('request token')->from_post_body($res->content);
    return {
        token        => $response->token,
        token_secret => $response->token_secret,
        redirect_url =>
            $self->authorize_url
            . '?oauth_token=' . $response->token,
    };
}

sub get_access_tokens {
    my $self = shift;
    my ( %param ) = @_;

    my $ua = MT->new_ua;
    my $request = $self->oauth_request(
        "access token",
        request_method => 'POST',
        request_url    => $self->access_token_url,
        token          => $param{oauth_token},
        verifier       => $param{oauth_verifier},
        token_secret   => $param{request_token_secret},
    );
    my $http_req = HTTP::Request->new('POST', $self->access_token_url);
    $http_req->content($request->to_post_body);
    $http_req->content_type( 'application/x-www-form-urlencoded' );

    my $res = $ua->request($http_req);
    my $response = Net::OAuth->response('access token')->from_post_body($res->content);
    die 'Failed to get OAuth Tokens: ' . $res->status_line
        unless $res->is_success;
    return $response->token;
}

1;

