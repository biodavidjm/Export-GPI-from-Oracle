#!/usr/bin/perl -w

use POSIX;
use strict;
use feature qw/say/;
use warnings;

use DBI;
 
my $user = "CGM_CHADO";
my $passwd = "CGM_CHADO";

say "going to connect";
my $dbh = DBI->connect("dbi:Oracle:host=dicty-oracle-vm.nubic.northwestern.edu;sid=orcl;port=1521", $user,$passwd);
say "connected";
my @result = $dbh->selectrow_array("SELECT count(*) FROM feature");
say $result[0];
# $sth->execute();
$dbh->disconnect();
# $dbh = DBI->connect('dbi:Oracle:host=foobar;sid=DB;port=1521', 'scott/tiger', '');



