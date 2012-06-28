use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;
use Carp qw/confess cluck/;
use CPAN;

my $pre_reqs = {
		'Cache::Memcached::Fast' => 1 , 
		'Moose' => 1 , 
        'Data::UUID::MT' => 1,
		};

foreach my $module(keys %{$pre_reqs}){
	if($pre_reqs->{$module}){
        print "\nchecking $module";
		eval "use $module";
		if($@){
			eval {
				print "Instalando o modulo $module\n";
				CPAN::install $module;
			};
			if($@){
				cluck "Problemas para instalar o modulo '$module' - $@";
			}
			else {
				print "O modulo '$module' instalado!\n";
			}
		}
		else {
			print "\nModule '$module' ok!";
		}
	}
}



WriteMakefile(
    NAME                => 'Cache::Memcached::Queue',
    AUTHOR              => q{Andre Garcia Carneiro <andregarciacarneiro@gmail.com>},
    VERSION_FROM        => 'lib/Cache/Memcached/Queue.pm',
#    ABSTRACT_FROM       => 'lib/Cache/Memcached/Queue.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {'Test::More' => 0}, 
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Cache-Memcached-Queue-*' },
);




