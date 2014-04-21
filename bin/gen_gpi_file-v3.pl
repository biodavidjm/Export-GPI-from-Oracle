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
# Statement: 1 to 1
# It selects DDB_G ID and gene name from the database
# Excludes pseudogenes
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

my $statement = <<"STATEMENT";
SELECT dbxref.accession gene_id, gene.feature_id, gene.name
FROM cgm_chado.feature gene
JOIN organism ON organism.organism_id=gene.organism_id
JOIN dbxref on dbxref.dbxref_id=gene.dbxref_id
JOIN cgm_chado.cvterm gtype on gtype.cvterm_id=gene.type_id
JOIN cgm_chado.feature_relationship frel ON frel.object_id=gene.feature_id
JOIN cgm_chado.feature mrna ON frel.subject_id=mrna.feature_id
JOIN cgm_chado.cvterm mtype ON mtype.cvterm_id=mrna.type_id
WHERE gtype.name='gene' AND mtype.name='mRNA' AND organism.common_name = 'dicty'
AND gene.name NOT LIKE '%\\_ps%' ESCAPE '\\'
STATEMENT

print "> Execute statement... ";

my $results = $dbh->prepare($statement);
$results->execute()
    or die "\n\nOh no! I could not execute: " . DBI->errstr . "\n\n";

say " done!!";

my ( $DDB_G, $locus_no, $gene_name );
my %ddbg2gene_name    = ();
my %ddbg2locus_number = ();

while ( ( $DDB_G, $locus_no, $gene_name ) = $results->fetchrow_array ) {
    $ddbg2gene_name{$DDB_G}    = $gene_name;
    $ddbg2locus_number{$DDB_G} = $locus_no;
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Database setup
# Statement: 1 to 1
# DDB_G ID and gene PRODUCTS from the database
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

my $statement_geneproduct = <<"STATEMENT";
SELECT gporder.gene_product FROM (
SELECT gp.gene_product
FROM cgm_ddb.gene_product gp
INNER JOIN cgm_ddb.locus_gp lgp ON lgp.gene_product_no = gp.gene_product_no
WHERE lgp.locus_no = ?
ORDER BY date_created DESC
) gporder
WHERE rownum = 1
STATEMENT

# SELECT dx.accession AS DDB_G_ID,
my $result_product = $dbh->prepare($statement_geneproduct);
my $count_u  = 0;    # count unknowns gene products
my $count_t  = 1;
my $count_gp = 0;

for my $ddb ( sort keys %ddbg2locus_number ) {
    my $locus_no = $ddbg2locus_number{$ddb};
    $result_product->execute($locus_no);
    my $gene_product;
    print $count_t. " "
        . $ddb . " -> "
        . $ddbg2locus_number{$ddb} . "\t"
        . $ddbg2gene_name{$ddb} . "\t";
    while ( ($gene_product) = $result_product->fetchrow_array ) {
        print $gene_product ;
        if ( $gene_product eq "unknown" ) {
            $count_u++;
        }
        $count_gp++;
    }
    $count_t++;
    print "\n";
}

say "Gene products: "
    . $count_gp
    . " (unkowns: "
    . $count_u
    . ") out of "
    . $count_t;

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


