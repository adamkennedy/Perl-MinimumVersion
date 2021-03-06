use inc::Module::Install::DSL 1.06;

all_from       lib/Perl/MinimumVersion.pm
requires       version                0.76
requires       List::Util             1.20
requires       Params::Util           0.25
requires       File::Find::Rule       0.32
requires       File::Find::Rule::Perl 1.04
requires       PPI                    1.215
requires       Perl::Critic::Utils    1.104
requires       PPIx::Regexp           0.033
test_requires  File::Spec             0.80
test_requires  Test::More             0.47
test_requires  Test::Script           1.03
install_script perlver
