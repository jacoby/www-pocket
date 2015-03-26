package WWW::Pocket;
use Moose;

use HTTP::Tiny;
use JSON::PP;

has consumer_key => (
    is  => 'rw',
    isa => 'Str',
);

has access_token => (
    is  => 'rw',
    isa => 'Str',
);

has username => (
    is  => 'rw',
    isa => 'Str',
);

has base_uri => (
    is      => 'ro',
    isa     => 'Str',
    default => 'https://getpocket.com/v3/',
);

has ua => (
    is      => 'ro',
    isa     => 'HTTP::Tiny',
    lazy    => 1,
    default => sub { HTTP::Tiny->new },
);

sub start_authentication {
    my $self = shift;
    my ($consumer_key, $redirect_uri) = @_;

    return if $self->consumer_key && $self->access_token;

    $redirect_uri ||= 'https://getpocket.com/';

    my $response = $self->_request(
        $self->base_uri . 'oauth/request',
        {
            consumer_key => $consumer_key,
            redirect_uri => $redirect_uri,
        },
    );
    return $response->{code};
}

sub finish_authentication {
    my $self = shift;
    my ($consumer_key, $code) = @_;

    my $response = $self->_request(
        $self->base_uri . 'oauth/authorize',
        {
            consumer_key => $consumer_key,
            code         => $code,
        },
    );

    $self->consumer_key($consumer_key);
    $self->access_token($response->{access_token});
    $self->username($response->{username});
}

sub add {
    my $self = shift;
    my (%params) = @_;
    return $self->_endpoint_request('add', \%params);
}

sub modify {
    my $self = shift;
    my (%params) = @_;
    return $self->_endpoint_request('send', \%params);
}

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
    return $self->_request($self->base_uri . $endpoint, $params);
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
    die "Request for $uri failed ($response->{status}): $response->{reason}"
        unless $response->{success};

    return decode_json($response->{content});
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
