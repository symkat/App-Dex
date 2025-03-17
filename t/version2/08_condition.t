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
            '      - exec: echo "nothing"',
            '        condition: 1 -eq 0',
        ],
        argv      => [qw|command_test|],
        commands =>  [], 
        title       => 'conditional command fails condition',
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
            '      - exec: echo "someting"',
            '        condition: 1 -eq 1',
        ],
        argv      => [qw|command_test|],
        commands =>  [
           'echo "someting"'
        ], 
        title       => 'conditional command passes condition',
        line        => __LINE__,
    }, 
    {
        content => [
            '---',
            'version: 2',
            'vars:',
            '  is_true: 1',
            'blocks:',
            '  - name: command_test',
            '    desc: Command Test',
            '    commands:',
            '      - exec: echo "someting"',
            '        condition: 1 -eq [%is_true%]',
        ],
        argv      => [qw|command_test|],
        commands =>  [
           'echo "someting"'
        ], 
        title       => 'variable conditional command passes condition',
        line        => __LINE__,
    },  
    #{
    #    content => [
    #        '---',
    #        'version: 2',
    #        'vars:',
    #        '  some_list:',
    #        '    - "one"',
    #        '    - "two"',
    #        '    - "three"',
    #        'blocks:',
    #        '  - name: command_test',
    #        '    desc: Command Test',
    #        '    commands:',
    #        '      - exec: echo "[%var%]"',
    #        '        for-vars: some_list',
    #    ],
    #    argv      => [qw|command_test|],
    #    commands =>  [
    #      'echo "one"',
    #      'echo "two"',
    #      'echo "three"'
    #    ], 
    #    title       => 'for-vars list var',
    #    line        => __LINE__,
    #}, 
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

    cmp_deeply $commands_run, $test->{commands}, sprintf( "line %d: %s", $test->{line}, $test->{title} ); 

    $commands_run = [];
}

done_testing();   
