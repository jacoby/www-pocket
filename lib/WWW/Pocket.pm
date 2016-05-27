package WWW::Pocket;
use Moose;
# ABSTRACT: Wrapper for the Pocket v3 API

use HTTP::Tiny;
use IO::Socket::SSL; # Necessary for https URLs on HTTP::Tiny.
use JSON::PP;
use Carp;

=head1 SYNOPSIS

  use WWW::Pocket;

  my $pocket = WWW::Pocket->new(
      # get a consumer key at https://getpocket.com/developer/
      consumer_key => '...',
  );

  my ($url, $code) = $pocket->start_authentication('https://example.com/');
  # visit $url, log in
  $pocket->finish_authentication($code);

  say for map { $_->{resolved_url} } values %{ $pocket->retrieve->{list} };

=head1 DESCRIPTION

This module wraps the L<Pocket|https://getpocket.com/> v3 API. To use, you
must first authenticate via OAuth by providing a valid consumer key, and then
visiting the OAuth endpoint (handled by the C<start_authentication> and
C<finish_authentication> methods). Once logged in, you can interact with the
API via the C<add>, C<modify>, and C<retrieve> methods, which correspond to
the endpoints documented at L<https://getpocket.com/developer/docs/overview>.

This module also ships with a command line scripts called C<pocket>, for
interacting with the API from the command line. See the documentation for that
script for more details.

=cut

=attr consumer_key

The consumer key for your application. You can generate a consumer key at
L<https://getpocket.com/developer/apps/>. Required.

=cut

has consumer_key => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

=attr access_token

The token returned when you successfully authenticate. This can be used to
reauthenticate with the server without having to log in every time. It is set
automatically by C<finish_authentication>, but can also be provided directly
to avoid having to reauthenticate. It is required to be set before any API
methods are called.

=cut

has access_token => (
    is        => 'ro',
    isa       => 'Str',
    lazy      => 1,
    default   => sub { die "You must authenticate first." },
    predicate => 'has_access_token',
    writer    => '_set_access_token',
);

=attr username

The username that you have authenticated as. It is set automatically by
C<finish_authentication>, and can also be provided directly. It is
informational only.

=cut

has username => (
    is        => 'ro',
    isa       => 'Str',
    predicate => 'has_username',
    writer    => '_set_username',
);

=attr base_uri

The base URI for the Pocket service. Defaults to C<https://getpocket.com/>.

=cut

has base_uri => (
    is      => 'ro',
    isa     => 'Str',
    default => 'https://getpocket.com/',
);

=attr api_base_uri

The base URI for the API endpoints. Defaults to appending C</v3/> to the
C<base_uri>.

=cut

has api_base_uri => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        my $base = $_[0]->base_uri;
        $base =~ s{/$}{};
        return "$base/v3/"
    },
);

=attr auth_base_uri

The base URI for the authentication endpoints. Defaults to appending C</auth/>
to the C<base_uri>.

=cut

has auth_base_uri => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        my $base = $_[0]->base_uri;
        $base =~ s{/$}{};
        return "$base/auth/"
    },
);

=attr ua

The L<HTTP::Tiny> instance used to access the api.

=cut

has ua => (
    is      => 'ro',
    isa     => 'HTTP::Tiny',
    lazy    => 1,
    default => sub { HTTP::Tiny->new },
);

=method start_authentication($redirect_uri)

Call this method to begin the authentication process. You must provide the
C<$redirect_uri>, which is where the user will be redirected to after
authenticating. This method returns a URL and an authentication code. The user
must visit the URL to log into Pocket and approve the application, and then
you should call C<finish_authentication> with the authentication code after
that is done.

=cut

sub start_authentication {
    my $self = shift;
    my ($redirect_uri) = @_;

    return if $self->has_access_token;

    my $response = $self->_request(
        $self->api_base_uri . 'oauth/request',
        {
            consumer_key => $self->consumer_key,
            redirect_uri => $redirect_uri,
        },
    );
    return (
        $self->auth_base_uri . "authorize?request_token=$response->{code}&redirect_uri=$redirect_uri",
        $response->{code},
    );
}

=method finish_authentication($code)

Finishes the authentication process. Call this method with the code returned
by C<start_authentication> after the user has visited the URL which was also
returned by C<start_authentication>. Once this method returns, the
C<access_key> and C<username> attributes will be set, and other API methods
can be successfully called.

=cut

sub finish_authentication {
    my $self = shift;
    my ($code) = @_;

    my $response = $self->_request(
        $self->api_base_uri . 'oauth/authorize',
        {
            consumer_key => $self->consumer_key,
            code         => $code,
        },
    );

    $self->_set_access_token($response->{access_token});
    $self->_set_username($response->{username});

    return;
}

=method add(%params)

Wraps the L<add|https://getpocket.com/developer/docs/v3/add> endpoint.
C<%params> can include any parameters documented in the API documentation.

=cut

sub add {
    my $self = shift;
    my (%params) = @_;
    return $self->_endpoint_request('add', \%params);
}

=method modify

Wraps the L<modify|https://getpocket.com/developer/docs/v3/modify> endpoint.
C<%params> can include any parameters documented in the API documentation.

=cut

sub modify {
    my $self = shift;
    my (%params) = @_;
    return $self->_endpoint_request('send', \%params);
}

=method retrieve

Wraps the L<retrieve|https://getpocket.com/developer/docs/v3/retrieve>
endpoint. C<%params> can include any parameters documented in the API
documentation.

=cut

sub retrieve {
    my $self = shift;
    my (%params) = @_;
    return $self->_endpoint_request('get', \%params);
}

sub _endpoint_request {
    my $self = shift;
    my ($endpoint, $params) = @_;
    $params->{consumer_key} = $self->consumer_key;
    $params->{access_token} = $self->access_token;
    return $self->_request($self->api_base_uri . $endpoint, $params);
}

sub _request {
    my $self = shift;
    my ($uri, $params) = @_;

    my $response = $self->ua->post(
        $uri,
        {
            content => encode_json($params),
            headers => {
                'Content-Type' => 'application/json; charset=UTF-8',
                'X-Accept'     => 'application/json',
            },
        },
    );
    croak "Request for $uri failed ($response->{status}): $response->{content}"
        unless $response->{success};

    return decode_json($response->{content});
}

__PACKAGE__->meta->make_immutable;
no Moose;

=head1 BUGS

No known bugs.

Please report any bugs to GitHub Issues at
L<https://github.com/doy/www-pocket/issues>.

=head1 SEE ALSO

L<Webservice::Pocket> for the v2 API

=head1 SUPPORT

You can find this documentation for this module with the perldoc command.

    perldoc WWW::Pocket

You can also look for information at:

=over 4

=item * MetaCPAN

L<https://metacpan.org/release/WWW-Pocket>

=item * Github

L<https://github.com/doy/www-pocket>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=WWW-Pocket>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/WWW-Pocket>

=back

=cut

1;
