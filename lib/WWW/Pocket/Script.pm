package WWW::Pocket::Script;
use Moose;

use Getopt::Long 'GetOptionsFromArray';
use JSON::PP;
use Path::Class;

use WWW::Pocket;

has consumer_key => (
    is        => 'ro',
    isa       => 'Str',
    lazy      => 1,
    default   => sub { die "consumer_key is required to authenticate" },
    predicate => '_has_consumer_key',
);

has redirect_uri => (
    is      => 'ro',
    isa     => 'Str',
    default => 'https://getpocket.com/',
);

has credentials_file => (
    is      => 'ro',
    isa     => 'Str',
    default => "$ENV{HOME}/.pocket",
);

has pocket => (
    is      => 'ro',
    isa     => 'WWW::Pocket',
    lazy    => 1,
    default => sub {
        my $self = shift;

        my $credentials_file = file($self->credentials_file);
        if (-e $credentials_file) {
            return $self->_apply_credentials($credentials_file);
        }
        else {
            return $self->_authenticate;
        }
    },
);

sub run {
    my $self = shift;
    my @argv = @_;

    my $method = shift @argv;
    if ($self->can($method)) {
        return $self->$method(@argv);
    }
    else {
        die "insert usage here";
    }
}

sub authenticate {
    my $self = shift;
    $self->pocket;
}

sub list {
    my $self = shift;
    my @argv = @_;

    my ($params) = $self->_parse_retrieve_options(@argv);

    print "$_\n" for $self->_retrieve_urls(%$params);
}

sub search {
    my $self = shift;
    my @argv = @_;

    my ($params, $extra_argv) = $self->_parse_retrieve_options(@argv);
    my ($search) = @$extra_argv;

    print "$_\n" for $self->_retrieve_urls(%$params, search => $search);
}

sub retrieve_raw {
    my $self = shift;
    my @argv = @_;

    my ($params) = $self->_parse_retrieve_options(@argv);

    $self->_pretty_print($self->pocket->retrieve(%$params));
}

sub _parse_retrieve_options {
    my $self = shift;
    my @argv = @_;

    my ($archive);
    GetOptionsFromArray(
        \@argv,
        "archive" => \$archive,
    ) or die "???";

    return (
        {
            ($archive ? (state => $archive) : ()),
            sort => 'oldest',
            detailType => 'simple',
        },
        [ @argv ],
    );
}

sub _retrieve_urls {
    my $self = shift;
    my %params = @_;

    my $response = $self->pocket->retrieve(%params);
    my $list = $response->{list};
    return unless ref($list) && ref($list) eq 'HASH';

    return map {
        $_->{resolved_url}
    } sort {
        $a->{sort_id} <=> $b->{sort_id}
    } values %{ $response->{list} };
}

sub add {
    my $self = shift;
    my ($url, $title) = @_;

    $self->pocket->add(
        url   => $url,
        title => $title,
    );
    print "Page Saved!\n";
}

sub _apply_credentials {
    my $self = shift;
    my ($file) = @_;

    my ($consumer_key, $access_token, $username) = $file->slurp(chomp => 1);
    return WWW::Pocket->new(
        consumer_key => $consumer_key,
        access_token => $access_token,
        username     => $username,
    );
}

sub _authenticate {
    my $self = shift;

    my $consumer_key = $self->_has_consumer_key
        ? $self->consumer_key
        : $self->_prompt_for_consumer_key;

    my $pocket = WWW::Pocket->new(consumer_key => $consumer_key);

    my $redirect_uri = $self->redirect_uri;
    my $code = $pocket->start_authentication($redirect_uri);

    print "Visit https://getpocket.com/auth/authorize?request_token=${code}&redirect_uri=${redirect_uri} and log in. When you're done, press enter to continue.\n";
    <STDIN>;

    $pocket->finish_authentication($code);

    my $fh = file($self->credentials_file)->openw;
    $fh->write($pocket->consumer_key . "\n");
    $fh->write($pocket->access_token . "\n");
    $fh->write($pocket->username . "\n");
    $fh->close;

    return $pocket;
}

sub _prompt_for_consumer_key {
    my $self = shift;

    print "Enter your consumer key: ";
    chomp(my $key = <STDIN>);
    return $key;
}

sub _pretty_print {
    my $self = shift;
    my ($data) = @_;

    print JSON::PP->new->utf8->pretty->canonical->encode($data), "\n";
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
