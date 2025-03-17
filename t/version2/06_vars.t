#!/usr/bin/env perl
use warnings;
use strict;
use Cwd;
use Test::More;
use Test::Deep;
use App::Dex2;
use File::Temp;
use Test::MockModule;
use IPC::Run3;

my $commands_run = [];
my $mock_run3 = sub {
    my ($cmd, @args) = @_;

    push @$commands_run, $cmd;

    run3($cmd, @args)
};

my $mock = Test::MockModule->new('App::Dex2');
$mock->mock(run3 => $mock_run3 );

$ENV{TESTENV} = 'env value';

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
        argv      => [qw|command_test|],
        commands =>  [
          'echo "hello world in somedir"'
        ], 
        title       => 'exec command',
        line        => __LINE__,
    },
    {
        content => [
            '---',
            'vars:', 
            '  say_this: "hello world"',
            'version: 2',
            'blocks:',
            '  - name: command_test',
            '    desc: Command Test',
            '    commands:',
            '      - diag: "[%say_this%]"'
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
            'vars:', 
            '  say_this: "hello world"',
            'version: 2',
            'blocks:',
            '  - name: command_test',
            '    desc: Command Test',
            '    vars:', 
            '      say_this: "fizz buzz"', 
            '      and_this: "foo bar"',
            '    commands:',
            '      - diag: "[%say_this%] and [%and_this%]"'
        ],
        argv      => [qw|command_test|],
        commands =>  [
          q|echo 'fizz buzz and foo bar'|
        ], 
        title       => 'diag local var override command',
        line        => __LINE__,
    },    
    {
        content => [
            '---',
            'version: 2',
            'vars:', 
            '  test_dir: "t"',   
            'blocks:',
            '  - name: command_test',
            '    desc: Command Test',
            '    commands:',
            '      - dir: "[%test_dir%]"',
            '        exec: echo "$(pwd)"'
        ],
        argv      => [qw|command_test|],
        run => sub { 
            my ($app, $test) = @_;

            $mock->mock(run3 => sub { 

                 $mock_run3->(@_);

                 my $dir = getcwd;
                 ok $dir =~ qr|t$|, 'changed to var directory';
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
    {
        content => [
            '---',
            'version: 2',
            'vars:', 
            '  test_env: ',
            '    from_env: TESTENV',
            'blocks:',
            '  - name: command_test',
            '    desc: Command Test',
            '    commands:',
            '      - exec: echo "[%test_env%]"'
        ],
        argv      => [qw|command_test|],
        commands =>  [
          q|echo "env value"|
        ], 
        title       => 'var from ENV',
        line        => __LINE__,
    },  
    {
        content => [
            '---',
            'version: 2',
            'vars:', 
            '  test_env: ',
            '    from_env: BOOLENV',
            '    default: "false"',
            'blocks:',
            '  - name: command_test',
            '    desc: Command Test',
            '    commands:',
            '      - exec: echo "[% test_env %]"'
        ],
        argv      => [qw|command_test|],
        commands =>  [
          q|echo "false"|
        ], 
        title       => 'var from ENV default',
        line        => __LINE__,
    },
    {
        content => [
            '---',
            'version: 2',
            'vars:', 
            '  test_cmd: ',
            '    from_command: echo  "command value"',
            '    default: "failed"',
            'blocks:',
            '  - name: command_test',
            '    desc: Command Test',
            '    commands:',
            '      - exec: echo "var [%test_cmd%]"'
        ],
        argv      => [qw|command_test|],
        commands =>  [
          [ '/bin/bash', '-c', 'echo  "command value"' ],
          q|echo "var command value"|
        ], 
        title       => 'var from command',
        line        => __LINE__,
    },
    {
        content => [
            '---',
            'version: 2',
            'vars:', 
            '  list_cmd: ',
            '    from_command: printf "this\nthat\nthese\n"',
            '    default: "failed"',
            'blocks:',
            '  - name: command_test',
            '    desc: Command Test',
            '    commands:',
            '      - exec: echo "var [% var %]"',
            '        for-vars: list_cmd'
        ],
        argv      => [qw|command_test|],
        commands =>  [
          [ '/bin/bash', '-c', 'printf "this\nthat\nthese\n"' ],
          q|echo "var this"|,
          q|echo "var that"|,
          q|echo "var these"|,
        ], 
        title       => 'for-vars var from command',
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
