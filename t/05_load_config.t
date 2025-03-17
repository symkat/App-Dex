#!/usr/bin/env perl
use warnings;
use strict;
use Cwd;
use Test::More;
use Test::Deep;
use App::Dex;
use File::Temp;
use Test::MockModule; 
use Try::Tiny;

my $tests = [
    {
        content => [
            '---',
            'version: 2',
            'vars:', 
            '  dir: "somedir"',  
            'blocks:',
            '  - name: command_test',
            '    desc: Command Test',
            '    commands:',
            '      - exec: echo "hello world in [%dir%]"'
        ],
        class     => 'App::Dex2',
        argv      => [qw|command_test|],
        commands =>  [
          'echo "hello world in somedir"'
        ], 
        title       => 'App::Dex2 config file',
        line        => __LINE__,
    },
    {
        content => [
            '---',
            '- name: command_test',
            '  desc: Command Test',
        ],
        class     => 'App::Dex',
        title       => 'App::Dex config file',
        line        => __LINE__,
    },
    {
        content => [
            '---',
            'vars:', 
            '  dir: "somedir"',  
            'blocks:',
            '  - name: command_test',
            '    desc: Command Test',
            '    commands:',
            '      - exec: echo "hello world in [%dir%]"'
        ],
        argv      => [qw|command_test|],
        title       => 'App::Dex2 no version number',
        line        => __LINE__,
        run         => 
            sub {
                my ($test) = @_; 

                my $app = try  { App::Dex->load_version_from_config( argv => $test->{argv} ) }
                          catch { is $_, "Invalid Config Version\n", 'Error on missing version' }; 

                fail('Did not die on mission version') if ref($app);

            },
    }, 
    {
        content => [
            'Bad Config ',
        ],
        argv      => [qw||],
        title       => 'App::Dex bad config',
        line        => __LINE__,
        run         => 
            sub {
                my ($test) = @_; 

                my $app = try  { App::Dex->load_version_from_config( argv => $test->{argv} ) }
                          catch { is $_, "Invalid Config\n", 'Error on bad config' }; 

                fail('Did not die on correctly on bad config') if ref($app);

            },
    },
];

foreach my $test ( @{$tests} ) {
    my $file = File::Temp->new( unlink => 1 );

    my $path = $file->filename;

    foreach my $line ( @{$test->{content}} ) {
        print $file "$line\n";
    }
    close($file); # Write the file

    local @App::Dex::CONFIG_FILE_NAMES = ($path);


    my $run = $test->{run} || sub { my ($test) = @_; my $app = App::Dex->load_version_from_config( argv => $test->{argv} ); isa_ok($app, $test->{class});  };

    $run->($test);
}

done_testing(); 
