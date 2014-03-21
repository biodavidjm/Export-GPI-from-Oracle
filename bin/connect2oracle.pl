#!/usr/bin/perl -w

use POSIX;
use strict;
use warnings;

use DBI;
 
my $user = "CGM_CHADO";
my $passwd = "CGM_CHADO";

my $dbh = DBI->connect("dbi:Oracle:", 'CGM_CHADO@dicty-oracle-vm.nubic.northwestern.edu', $passwd);

# $dbh = DBI->connect('dbi:Oracle:host=foobar;sid=DB;port=1521', 'scott/tiger', '');



