use inc::Module::Install;

name            'App-dex';
all_from        'lib/App/Dex.pm';

requires        'YAML::XS';
requires        'IPC::Run3';

install_script  'scripts/dex';

WriteAll;
