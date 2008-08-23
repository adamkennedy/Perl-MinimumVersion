use inc::Module::Install 0.77;

all_from       'lib/Perl/MinimumVersion.pm';
requires       'Carp'             => 0;
# Push the versioning for version.pm heavily,
# as it has been through flaky periods
requires       'version'          => '0.76';
requires       'List::Util'       => '1.19';
requires       'Params::Util'     => '0.25';
requires       'File::Find::Rule' => 0;
requires       'PPI'              => '1.118';
test_requires  'File::Spec'       => '0.80';
test_requires  'Test::More'       => '0.47';
test_requires  'Test::Script'     => '1.02';
install_script 'perlver';

WriteAll;
