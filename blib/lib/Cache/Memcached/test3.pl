#!/usr/bin/perl 
#===============================================================================
#
#         FILE: test3.pl
#
#        USAGE: ./test3.pl  
#
#  DESCRIPTION: 
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: YOUR NAME (), 
#      COMPANY: 
#      VERSION: 1.0
#      CREATED: 04/22/2012 08:52:23 PM
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use Data::Dumper;
use Cache::Memcached::Fast;
use Cache::Memcached::Queue;
         my $memd = new Cache::Memcached::Fast({
             servers => [ { address => 'localhost:11211', weight => 2.5 },
                          ],});


my $queue = Cache::Memcached::Queue->new( servers => [{address => 'localhost:11211'}],
                                            id => 1,
                                        );
        

print Dumper $queue;

print Dumper $memd;    
