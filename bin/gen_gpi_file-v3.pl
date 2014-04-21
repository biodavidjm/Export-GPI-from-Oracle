#!/usr/bin/perl -w

use POSIX;
use strict;
use feature qw/say/;
use warnings;

use DBI;

use Getopt::Long;
use IO::File;
use autodie qw/open close/;
use Text::CSV;
use Perl::Tidy;

# Validation section
my %options;
GetOptions( \%options, 'dsn=s', 'user=s', 'passwd=s' );
for my $arg (qw/dsn user passwd/) {
    die
        "\tperl gen_gpi_file.pl -dsn=ORACLE_DNS -user=USERNAME -passwd=PASSWD\n\n"
        if not defined $options{$arg};
}

my $host = $options{dsn};
my $user = $options{user};
my $pass = $options{passwd};

print "Connecting to the database... ";
my $dbh = DBI->connect( "dbi:Oracle:host=$host;sid=orcl;port=1521",
    $options{user}, $options{passwd},
    { RaiseError => 1, LongReadLen => 2**20 } );

print " done!!\n";

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Database setup
# Statement 1: It selects DDB_G ID and gene name from the database
# Excludes pseudogenes
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

my $statement = "
SELECT dbxref.accession gene_id, gene.name
FROM cgm_chado.feature gene
JOIN organism ON organism.organism_id=gene.organism_id
JOIN dbxref on dbxref.dbxref_id=gene.dbxref_id
JOIN cgm_chado.cvterm gtype on gtype.cvterm_id=gene.type_id
JOIN cgm_chado.feature_relationship frel ON frel.object_id=gene.feature_id
JOIN cgm_chado.feature mrna ON frel.subject_id=mrna.feature_id
JOIN cgm_chado.cvterm mtype ON mtype.cvterm_id=mrna.type_id
WHERE gtype.name='gene' AND mtype.name='mRNA' AND organism.common_name = 'dicty'
AND gene.name NOT LIKE '%\\_ps%' ESCAPE '\\'
";

print "> Execute statement... ";
my $results = $dbh->prepare($statement);
$results->execute()
    or die "\n\nOh no! I could not execute: " . DBI->errstr . "\n\n";
print " done!!";


my ($DDB_G, $genename);
my %ddbg2genename = ();

while( ($DDB_G, $genename) = $results->fetchrow_array) {
	$ddbg2genename{$DDB_G} = $genename;
}

my $count_d = 1;
for my $key (sort keys %ddbg2genename)
{
	say $count_d." ".$key." -> ".$ddbg2genename{$key};
	$count_d++;
}

$dbh->disconnect();

exit;

=head1 NAME

gen_gpi_file-v3.pl - Generate a GPI file from the dictyBase

=head1 VERSION
 
Version 3


=head1 SYNOPSIS

perl gen_gpi_file.pl  --dsn=<Oracle DSN> --user=<Oracle user> --passwd=<Oracle password>


=head1 OPTIONS

 --dsn           Oracle database DSN
 --user          Database user name
 --passwd        Database password

=head1 OUTPUT

YYYYMMDD_HHMMSS.gpi_dicty

=head1 DESCRIPTION

Connect to the dictyOracle database and dump to a file
(YYYYMMDD_HHMMSS.gpi_dicty) the following information:

- DDB_G ID
- Gene name 

=head1 DETAILS

Additional information about the GPI format can be found in the following url:
http://wiki.geneontology.org/index.php/Final_GPAD_and_GPI_file_format

=head1 ISSUES

Statement 3 needs to be revised. According to the curation statistics, there
should be ~9,000 gene products. However this script gets less.



