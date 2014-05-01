#!/usr/bin/perl -w

use strict;
use feature qw/say/;

use DBI;

use Getopt::Long;
use IO::File;
use autodie qw/open close/;
use Text::CSV;

my $script_name = "gen_gpi_file_gp2protein.pl";

# Validation section
my %options;
GetOptions( \%options, 'dsn=s', 'user=s', 'passwd=s' );
for my $arg (qw/dsn user passwd/) {
    die
        "\tperl $script_name -dsn=ORACLE_DNS -user=USERNAME -passwd=PASSWD\n\n"
        if not defined $options{$arg};
}

my $host = $options{dsn};
my $user = $options{user};
my $pass = $options{passwd};

print "Connecting to the database... ";
my $dbh = DBI->connect( "dbi:Oracle:host=$host;sid=orcl;port=1521",
    $options{user}, $options{passwd},
    { RaiseError => 1, LongReadLen => 2**20 } );
say " done!!";

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Map DDB_G_ID to Uniprot IDs from gp2protein file.
# Use this as a list of genes (DDB_G ids)
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
my $filename = "../data/gp2protein.dictyBase";

open my $FILE, '<', $filename or die "Cannot open '$filename'!\n";

my %hash_gp2protein = ();

# stats
my $c_file  = 0;
my $c_regex = 0;
my $c_lines = 0;

foreach my $line (<$FILE>) {
    chomp($line);
    $c_lines++;
    if ( $line =~ /dictyBase:(\S+)\s+UniProtKB:(\w{6})/ ) {
        my $ddb = $1;
        my $uni = $2;
        $c_file++;
        # say $ddb. "--->" . $uni;
        if ( !$hash_gp2protein{$ddb} ) {    
            $hash_gp2protein{$ddb} = $uni;
            $c_regex++;
        }
        else {
            die "\n\nOooops " . $line . " is repeated!!\n";
        }
    }
    else {
        print $line. "\n";
    }
}

say "\nStats in gp2protein file:\n";
say "Lines in file: ".$c_lines;
say "In file: " . $c_file;
say "In loop: " . $c_regex;


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Database setup
# Statement: 1 to 1
# It selects DDB_G ID and gene name from the database
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

my $statement_genename = <<"STATEMENT";
SELECT DISTINCT dbxref.accession gene_id, gene.feature_id, gene.name
FROM cgm_chado.feature gene
JOIN organism ON organism.organism_id=gene.organism_id
JOIN dbxref on dbxref.dbxref_id=gene.dbxref_id
JOIN cgm_chado.cvterm gtype on gtype.cvterm_id=gene.type_id
JOIN cgm_chado.feature_relationship frel ON frel.object_id=gene.feature_id
JOIN cgm_chado.feature mrna ON frel.subject_id=mrna.feature_id
JOIN cgm_chado.cvterm mtype ON mtype.cvterm_id=mrna.type_id
WHERE dbxref.accession = ?
STATEMENT

my %ddbg2gene_name    = ();
my %ddbg2locus_number = ();
my $count_prot_coding = 0;
my $unique            = 0;
my $duplications      = 0;

for my $ddbg_id ( keys %hash_gp2protein ) {
    my @data = $dbh->selectrow_array($statement_genename, {}, ($ddbg_id) );

    my $DDB_G = $data[0];
    my $locus_no = $data[1];
    my $gene_name = $data[2];

    # just a control
    if (!$DDB_G) {
        die "\noh no!!! how is this possible there is no DDB_G_ID!!!\n";
    }
    elsif (!$locus_no) {
        die "\noh no!!! how is this possible there is no feature_id (locus number)!!!\n";
    }
    elsif (!$gene_name) {
        die "\noh no!!! how is this possible there is no gene name!!!\n";
    }

    # Double checking
    if ( !$ddbg2gene_name{$DDB_G} ) {
        $ddbg2gene_name{$DDB_G} = $gene_name;
        $unique++;
    }
    else {
        $duplications++;
    }

    $ddbg2locus_number{$DDB_G} = $locus_no;
    $count_prot_coding++;
}

say "Total number of DDB_G_ID: " . $unique;


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

say "> Checking for Gene Products";
# SELECT dx.accession AS DDB_G_ID,

my %hash_geneproduct = ();

my $count_u  = 0;    # count unknowns gene products
my $count_t  = 1;
my $count_gp = 0;

for my $ddb ( sort keys %ddbg2locus_number ) {

    my $locus_no = $ddbg2locus_number{$ddb};
    my @data = $dbh->selectrow_array($statement_geneproduct, {}, ($locus_no) );

    my $gene_product = '';
    $gene_product = $data[0];
    if (!$gene_product) {
        $count_u++
    }
    else {
        $count_gp++;
        $hash_geneproduct{$ddb} = $gene_product;
        # say $ddb." has this gene product: ".$gene_product;
    }
    $count_t++;
}

say "WITH GENE PRODUCT: "
    . $count_gp
    . " (unknown: "
    . $count_u
    . ") out of a total of "
    . $count_t;


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Database setup
# Statement: 1 to many
# For each DDB_G ID, get all the gene and protein alternative names
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

my $statement_syn = <<"STATEMENT";
SELECT wm_concat(syn.name) gsyn
FROM cgm_chado.feature gene
JOIN dbxref on dbxref.dbxref_id=gene.dbxref_id
LEFT JOIN cgm_chado.feature_synonym fsyn on gene.feature_id=fsyn.feature_id
LEFT JOIN cgm_chado.synonym_ syn on syn.synonym_id=fsyn.SYNONYM_ID
WHERE dbxref.accession = ?
GROUP BY dbxref.accession
STATEMENT

my $result_syn  = $dbh->prepare($statement_syn);
my $count_syn   = 0;
my $count_nosyn = 0;
my $total       = 1;

for my $ddbg_id ( sort keys %ddbg2gene_name ) {
    
    $result_syn->execute($ddbg_id);

    my $syn = '';
    while ( ($syn) = $result_syn->fetchrow_array ) {
        if ($syn) {

            # print $syn . "\n";
            $count_syn++;
        }
        else {
            # print "null\n";
            $count_nosyn++;
        }
    }    # while
    $total++;
}


# -------------------------------------------------------------
# Print out STATS
# Gene product
say "Gene products: "
    . $count_gp
    . " (unkowns: "
    . $count_u
    . ") out of "
    . $count_t;

# Alternative gene and protein names
say "\nTotal DDB_G ids: " . ( $total - 1 );
say "\tWith syn: " . $count_syn;
say "\tNO syn  : " . $count_nosyn;

$dbh->disconnect();

exit;

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Map DDB_G_ID to Uniprot IDs from gp2protein file.
# Use this as a list of genes (DDB_G ids)
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub get_gp2protein {

    my ($dbh) = @_;
    
    my $filename = "../data/gp2protein.dictyBase";
    open my $FILE, '<', $filename or die "Cannot open '$filename'!\n";

    my %hash_gp2protein = ();

    # stats
    my $c_file  = 0;
    my $c_regex = 0;
    my $c_lines = 0;

    foreach my $line (<$FILE>) {
        chomp($line);
        $c_lines++;
        if ( $line =~ /dictyBase:(\S+)\s+UniProtKB:(\w{6})/ ) {
            my $ddb = $1;
            my $uni = $2;
            $c_file++;
            # say $ddb. "--->" . $uni;
            if ( !$hash_gp2protein{$ddb} ) {    
                $hash_gp2protein{$ddb} = $uni;
                $c_regex++;
            }
            else {
                die "\n\nOooops " . $line . " is repeated!!\n";
            }
        }
    }

    say "\nStats in gp2protein file:\n";
    say "Lines in file: ".$c_lines;
    say "In file: " . $c_file;
    say "In loop: " . $c_regex."\n";

    return (%hash_gp2protein);
    my %hash_gp2protein = get_gp2protein($dbh);

}






=head1 NAME

gen_gpi_file_gp2protein.pl - Generate a GPI file from the dictyBase

=head1 VERSION
 
Version 3

=head1 SYNOPSIS

perl gen_gpi_file_gp2protein.pl  --dsn=<Oracle DSN> --user=<Oracle user> --passwd=<Oracle password>
(It resquires the gp2protein file at Export-GPI-from-Oracle/data/gp2protein.dictyBase).


=head1 OPTIONS

 --dsn           Oracle database DSN
 --user          Database user name
 --passwd        Database password

=head1 OUTPUT

YYYYMMDD_HHMMSS.gp2protein.gpi_dicty

=head1 DESCRIPTION

It connects to the dictyOracle database and generates a GPI file
(YYYYMMDD_HHMMSS.gp2protein.gpi_dicty)

The script uses the DDB_G_IDS corresponding to protein coding genes available
at the gp2protein file.


=head1 DETAILS

Additional information about the GPI format can be found in the following url:
http://wiki.geneontology.org/index.php/Final_GPAD_and_GPI_file_format

=head1 ISSUES





