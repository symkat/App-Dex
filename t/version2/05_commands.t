#!/usr/bin/env perl
use warnings;
use strict;
use Cwd;
use Test::More;
use Test::Deep;
use App::Dex2;
use File::Temp;
use Test::MockModule;

my $commands_run = [];
my $mock_run3 = sub {
    my $cmd = shift;

    #if ( ref($cmd) ) {
    #    diag "running: ". join(' ', @$cmd);
    #}
    #else {
    #    diag "running: $cmd"; 
    #}

    push @$commands_run, $cmd;
};

my $mock = Test::MockModule->new('App::Dex2');
$mock->mock(run3 => $mock_run3 );


my $tests = [
    {
        content => [
            '---',
            'version: 2',
            'blocks:',
            '  - name: command_test',
            '    desc: Command Test',
            '    commands:',
            '      - exec: echo "hello world"'
        ],
        argv      => [qw|command_test|],
        commands =>  [
          'echo "hello world"'
        ], 
        title       => 'exec command',
        line        => __LINE__,
    },
    {
        content => [
            '---',
            'version: 2',
            'blocks:',
            '  - name: command_test',
            '    desc: Command Test',
            '    commands:',
            '      - diag: hello world'
        ],
        argv      => [qw|command_test|],
        commands =>  [
          q|echo 'hello world'|
        ], 
        title       => 'diag command',
        line        => __LINE__,
    }, 
    {
        content => [
            '---',
            'version: 2',
            'blocks:',
            '  - name: command_test',
            '    desc: Command Test',
            '    commands:',
            '      - dir: t/version2',
            '        exec: echo "$(pwd)"'
        ],
        argv      => [qw|command_test|],
        run => sub { 
            my ($app, $test) = @_;

            $mock->mock(run3 => sub { 

                 $mock_run3->(@_);

                 my $dir = getcwd;
                 ok $dir =~ qr|t/version2$|, 'changed directory';
            }); 

            $app->run(); 

            $mock->mock(run3 => $mock_run3 ); 
        },
        commands =>  [
          q|echo "$(pwd)"|
        ], 
        title       => 'dir command',
        line        => __LINE__,
    }, 
];

foreach my $test ( @{$tests} ) {
    my $file = File::Temp->new( unlink => 1 );

    foreach my $line ( @{$test->{content}} ) {
        print $file "$line\n";
    }
    close($file); # Write the file

    ok my $app = App::Dex2->new( config_file_names => [ $file->filename ], argv => $test->{argv} ), sprintf( "line %d: %s", $test->{line}, "Object Construction" );

    my $run = $test->{run} || sub { $app->run(); };

    $run->($app,$test);
    #diag explain $commands_run;

    cmp_deeply $commands_run, $test->{commands}, sprintf( "line %d: %s", $test->{line}, $test->{title} ); 

    $commands_run = [];
}

done_testing();  
