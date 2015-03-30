package WWW::Pocket::Script;
use Moose;

with 'MooseX::Getopt';

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
    traits  => ['NoGetopt'],
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
    my @args = @{ $self->extra_argv };

    my $method = shift @args;
    if ($self->can($method)) {
        return $self->$method(@args);
    }
    else {
        $self->print_usage_text($self->usage);
    }
}

sub authenticate {
    my $self = shift;
    $self->pocket;
}

sub add {
    my $self = shift;
    my @args = @_;

    $self->_pretty_print($self->pocket->add(@args));
}

sub modify {
    my $self = shift;
    my @args = @_;

    $self->_pretty_print($self->pocket->modify(@args));
}

sub retrieve {
    my $self = shift;
    my @args = @_;

    $self->_pretty_print($self->pocket->retrieve(@args));
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
