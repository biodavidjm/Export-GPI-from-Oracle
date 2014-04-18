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
# Statement 1: Main query. It selects gene name, gene synonym and protein synonym, DDB_G ID
# Excluding pseudogenes
#
# Precaution: it is not a copy and paste from the SQL dictywiki.
# The following line was rearranged:
# Original: SELECT gene.name,wm_concat(syn.name) gsyn,dg.gene_id gene_id
# Here: dg.gene_id gene_id, gene.name, wm_concat(syn.name) gsyn
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

my $statement = "
WITH dicty_coding_genes AS (
SELECT dbxref.accession gene_id
FROM cgm_chado.feature gene
JOIN organism ON organism.organism_id=gene.organism_id
JOIN dbxref on dbxref.dbxref_id=gene.dbxref_id
JOIN cgm_chado.cvterm gtype on gtype.cvterm_id=gene.type_id
JOIN cgm_chado.feature_relationship frel ON frel.object_id=gene.feature_id
JOIN cgm_chado.feature mrna ON frel.subject_id=mrna.feature_id
JOIN cgm_chado.cvterm mtype ON mtype.cvterm_id=mrna.type_id
WHERE gtype.name='gene'
AND mtype.name='mRNA'
AND organism.common_name = 'dicty'
AND gene.name NOT LIKE '%\\_ps%'
ESCAPE '\\'
group by dbxref.accession
)

SELECT dg.gene_id gene_id, gene.name, wm_concat(syn.name) gsyn
FROM cgm_chado.feature gene
JOIN cgm_chado.dbxref on gene.dbxref_id=dbxref.dbxref_id
JOIN dicty_coding_genes dg on dg.gene_id=dbxref.accession
LEFT JOIN cgm_chado.feature_synonym fsyn on gene.feature_id=fsyn.feature_id
LEFT JOIN cgm_chado.synonym_ syn on syn.synonym_id=fsyn.SYNONYM_ID
group by gene.name,dg.gene_id
order by gene.name DESC
";

print "> Execute statement ";
my $results = $dbh->prepare($statement);
$results->execute()
    or die "\n\nOh no! I could not execute: " . DBI->errstr . "\n\n";
print " done!!";


close $out;
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

=head1 DETAILS

Additional information about the GPI format can be found in the following url:
http://wiki.geneontology.org/index.php/Final_GPAD_and_GPI_file_format

=head1 ISSUES

Statement 3 needs to be revised. According to the curation statistics, there
should be ~9,000 gene products. However this script gets less.



