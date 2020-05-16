use inc::Module::Install;

name            'App-dex';
all_from        'lib/App/Dex.pm';

requires        'YAML::PP';
requires        'IPC::Run3';

install_script  'packed/dex';

WriteAll;
