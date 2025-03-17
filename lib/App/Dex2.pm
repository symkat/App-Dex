package App::Dex2;
use Moo;
use File::pushd qw|pushd|;
use List::Util qw( first );
use Pod::Usage qw(pod2usage);
use Template::Simple;
use Try::Tiny; 
use YAML::PP qw( LoadFile );
use IPC::Run3;

our $VERSION = '0.002003';

has argv => (
    is      => 'ro', 
    default => sub { [] }
);

has config_file => (
    is      => 'ro',
    isa     => sub { die "Error: No config file found\n" unless $_[0] && -e $_[0] },
    lazy    => 1,
    default => sub {

        return $ENV{DEX_FILE} if $ENV{DEX_FILE};

        return first { -e $_ } @{shift->config_file_names};
    },
);

our @CONFIG_FILE_NAMES = qw( dex.yaml .dex.yaml ); 

has config_file_names => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        return [ @CONFIG_FILE_NAMES ],
    },
);

has config => (
    is      => 'ro',
    isa     => sub { die "Error: Invaild Config Version\n" unless ref($_[0]) eq 'HASH' and $_[0]->{version} and $_[0]->{version} == 2 }, 
    lazy    => 1,
    builder => sub {
        my ( $self ) = @_;

        return try { LoadFile $self->config_file } catch { die "Error reading config file: \n$_" };
    },
);

has config_version => (
    is      => 'ro',
    lazy    => 1, 
    builder => sub {
        my ( $self ) = @_; 

        return $self->config->{version};
    },
);


has config_blocks => (
    is      => 'ro',
    lazy    => 1,
    builder => sub {
       shift->config->{blocks};
    },
);

has global_vars => (
    is      => 'ro',
    lazy    => 1, 
    builder => sub {
        my ( $self ) = @_; 

        return $self->init_vars($self->config->{vars});
    },
);

sub init_vars {
    my ( $self, $var_cfg ) = @_;

    $var_cfg ||= {};
    my $ret = {};

    foreach my $var ( keys %$var_cfg ) {
        my $val = $var_cfg->{$var};

        if ( !ref($val) or ref($val) eq 'ARRAY' ) {
            $val = { value => $val };
        }
        elsif( ref($val) ne 'HASH' ) {
            die "Invalid var $var"
        }

        if ( $val->{from_command} ) {
            local $?;

            my $stdout;
            run3(['/bin/bash', '-c', $val->{from_command}], undef, \$stdout );

            if ( $stdout && !$? ) {
                chomp $stdout;
                my @lines = split(/\n/, $stdout); 
                $ret->{$var} = scalar @lines == 1 ? $lines[0] : \@lines;
            }
        }
        elsif ( $val->{from_env} ) { 
            $ret->{$var} = $ENV{$val->{from_env}};
        }

        if (! defined $ret->{$var}) {
            $ret->{$var} = $val->{value} || $val->{default};
        }

    }

    return $ret;
}

has tt => (
    is      => 'ro',
    lazy    => 1, 
    builder => sub {
       Template::Simple->new();
    },
);

sub render {
    my ( $self, $tmpl, $vars ) = @_; 

    return ${ $self->tt->render( $tmpl, { %{$self->global_vars}, %$vars } ) };
}

sub get_for_vars {
    my ( $self, $list, $vars ) = @_;

    return 1 if !$list;

    # If we have an array already just return that.
    if ( ref($list) eq 'ARRAY' ) { 
        return @{$list};
    }
    # If we have a scalar value search for a matching local or global 
    # var. Return an empty list if no match is found.
    elsif ( $list && !ref($list) ) {
        return @{ $vars->{$list} || $self->global_vars->{$list} || [] };
    }

    die "Invalid for-vars"
}

# Returns true if condition fails.
sub check_cond_fail {
    my ( $self, $cond_tmpl, $vars ) = @_;  

    return 0 if !$cond_tmpl;

    my $cond = $self->render( $cond_tmpl, $vars );

    system('/bin/bash', '-c', "test $cond");

    my $exit = $? >> 8;

    return $exit;
}

has menu => (
    is      => 'ro',
    lazy    => 1,
    builder => sub {
        my ( $self ) = @_;
        return [ $self->_menu_data( $self->config_blocks, 0 ) ];
    }
);

sub _menu_data {
    my ( $self, $config, $depth ) = @_;

    my @menu;
    foreach my $block ( @{$config} ) {
        push @menu, {
            name  => $block->{name},
            desc  => $block->{desc},
            depth => $depth,
        };
        if ( $block->{children} ) {
            push @menu, $self->_menu_data($block->{children}, $depth + 1);

        }
    }
    return @menu;
}

sub display_menu {
    my ( $self, $menu ) = @_;

    $menu = $self->menu unless $menu;

    foreach my $item ( @{$menu} ) {
        printf( "%s%-24s: %s\n", " " x ( 4 * $item->{depth} ), $item->{name}, $item->{desc} );
    }
}

sub resolve_block {
    my ( $self, $path ) = @_;

    return $self->_resolve_block( $path, $self->config_blocks );
}

sub _resolve_block {
    my ( $self, $path, $config ) = @_;

    my $block;
    while ( defined ( my $segment = shift @{$path} ) ) {
        $block = first { $_->{name} eq $segment } @{$config};

        return undef unless $block;

        if ( @{$path} ) {
            $config = $block->{children};
            next;
        }
    }
    return $block;
}

sub process_block {
    my ( $self, $block ) = @_;

    my $vars = $self->init_vars( $block->{vars} );

    my $dir       = $block->{dir}; 
    my $block_dir = pushd $self->render( $dir, $vars ) if $dir;

    $block->{commands} ||= [];

    foreach my $cfg ( @{$block->{commands}} ) {

        if ( $self->check_cond_fail($cfg->{condition}, $vars) ) {
           next; 
        }

        if ( my $dir = $cfg->{dir} ) {
            undef $block_dir; # calls File::pushd destructor to return us to original directory
            $block_dir = pushd $self->render( $dir, { var => $_, %$vars } );
        }

        if ( my $diag_tmpl = $cfg->{diag} ) {
           $cfg->{exec} = "echo '$diag_tmpl'";
        }

        if ( my $cmd_tmpl = $cfg->{exec} ) {

            my $index = 0;
            run3( $self->render( $cmd_tmpl, { var => $_, index => $index++, %$vars } ) )
                foreach $self->get_for_vars($cfg->{'for-vars'}, $vars );
        }
    }

}

sub run {
    my ( $self ) = @_;

    my @argv = @{$self->argv};

    if ( @argv && ( $argv[0] eq '--help' || $argv[0] eq '-h' ) ) {
        pod2usage( -verbose => 2 );
    }

    if ( @argv ) {
        my $block = $self->resolve_block( [ @argv ] );

        if ( ! $block ) {
            if ( my $fallback = $ENV{DEX_FALLBACK_CMD} || $self->config->{fallback} ) {
                exec $fallback, @argv;
            } else {
                print STDERR "Error: No such command.\n\n";
                $self->display_menu;
                exit -1;
            }
        }

        $self->process_block( $block );
    } else {
        $self->display_menu;
    }

}

1;

__END__

=encoding utf8

=head1 NAME

App::dex - Directory Execute

=head1 DESCRIPTION

B<dex> provides a command line utility for managing directory-specific commands.

=head1 USAGE

    dex                    - Display the menu
    dex command            - Run a command
    dex command subcommand - Run a sub command

Create a file called C<dex.yaml> or C<.dex.yaml> and define commands to be run.

=head1 DEX FILE SPECIFICATION

This is an example dex file.

    - name: build
      desc: "Run through the build process, including testing."
      shell:
        - ./fatpack.sh
        - dzil test
        - dzil build
    - name: test
      desc: "Just test the changes"
      shell:
        - dzil test
    - name: release
      desc: "Publish App::Dex to CPAN"
      shell:
        - dzil release
    - name: clean
      desc: "Remove artifacts"
      shell:
        - dzil clean
    - name: authordeps
      desc: "Install distzilla and dependencies"
      shell:
        - cpanm Dist::Zilla
        - dzil authordeps --missing | cpanm
        - dzil listdeps --develop --missing | cpanm

When running the command dex, a menu will display:

    $ dex
    build                   : Run through the build process, including testing.
    test                    : Just test the changes
    release                 : Publish App::Dex to CPAN
    clean                   : Remove artifacts
    authordeps              : Install distzilla and dependencies

To execute the build command run C<dex build>.

=head2 SUBCOMMANDS

Commands can be grouped to logically organize them, for example:

    - name: foo
      desc: "Foo command"
      children:
        - name: bar
          desc: "Bar subcommand"
          shell:
            - echo "Ran the command!"

The menu for this would show the relationship:

    $ dex
    foo                     : Foo command
        bar                     : Bar subcommand

To execute the command one would run C<dex foo bar>.


=head1 FALLBACK COMMAND

When dex doesn't understand the command it will give an error and display the menu. It
can be configured to allow another program to try to execute the command.

Set the environment variable C<DEX_FALLBACK_CMD> to the command you would like to run
instead.

=head1 AUTHOR

Kaitlyn Parkhurst (SymKat) I<E<lt>symkat@symkat.comE<gt>> ( Blog: L<http://symkat.com/> )

=head1 CONTRIBUTORS

=head1 SPONSORS

=head1 COPYRIGHT

Copyright (c) 2019 the App::dex L</AUTHOR>, L</CONTRIBUTORS>, and L</SPONSORS> as listed above.

=head1 LICENSE

This library is free software and may be distributed under the same terms as perl itself.

=head2 AVAILABILITY

The most current version of App::dec can be found at L<https://github.com/symkat/App-dex>
