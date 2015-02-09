#!/usr/bin/perl -w

use strict;
use feature qw/say/;

use DBI;

use Getopt::Long;
use IO::File;
use autodie qw/open close/;
use Text::CSV;

my $script_name = "generate-gpi-file.pl";

# Validation section
my %options;
GetOptions( \%options, 'host=s', 'user=s', 'passwd=s' );
for my $arg (qw/host user passwd/) {
    die
        "\nError!\n\nUSAGE: perl $script_name -host=ORACLE_DNS -user=USERNAME -passwd=PASSWD\n\n"
        if not defined $options{$arg};
}

my $host = $options{host};
my $user = $options{user};
my $pass = $options{passwd};

print "\n" . $script_name . " is connecting to the database... ";
my $dbh = DBI->connect( "dbi:Oracle:host=$host;sid=orcl;port=1521",
    $options{user}, $options{passwd},
    { RaiseError => 1, LongReadLen => 2**20 } );
say " done!!\n";

# Get DDB_G and Uniprot ids
say "> Getting ddb_g and Uniprot from gp2protein file... ";
my %hash_gp2protein = get_gp2protein($dbh);

# Get locus and gene names
print "> Getting gene name... ";
my ( $hash_gene, $hash_locus )
    = get_gen_locus_name( $dbh, \%hash_gp2protein );
my %hash_ddbg2gene_name    = %$hash_gene;
my %hash_ddbg2locus_number = %$hash_locus;
say " done!";

# Get gene products
print "> Getting gene product... ";
my %hash_geneproduct = get_gene_products( $dbh, \%hash_ddbg2locus_number );

# Get gen syn
print "> Getting gene synonyms... ";
my %hash_gene_synonym = get_gene_alt_names( $dbh, \%hash_gp2protein );

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# OUTPUT FILE
# Output file name (uses date & time)
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst )
    = localtime(time);
my $ymd = sprintf(
    "%04d%02d%02d_%02d%02d%02d",
    $year + 1900,
    $mon + 1, $mday, $hour, $min, $sec
);
my $outfile = "data/$ymd.gp2protein.gpi_dicty";

open my $out, '>', $outfile
    or die "Big problem: I can't create '$outfile'";

my $localtime = localtime();

# Head info to the GPI FILE
my $headinfo = "!
! gpi-version: 1.1
! namespace: dictyBase
!
! This file contains additional information for genes in the dictyBase.
! Gene accessions are represented in this file even if there is no associated GO annotation.
!
! Columns:
!
!   name                   required? cardinality   GAF column #
!   DB_Object_ID           required  1             2/17        
!   DB_Object_Symbol       required  1             3           
!   DB_Object_Name         optional  0 or greater  10          
!   DB_Object_Synonym(s)   optional  0 or greater  11          
!   DB_Object_Type         required  1             12          
!   Taxon                  required  1             13          
!   Parent_Object_ID       optional  0 or 1        -           
!   DB_Xref(s)             optional  0 or greater  -           
!   Properties             optional  0 or greater  -           
!
! Generated on $localtime
!
";

print {$out} $headinfo;

my $c_genes    = 0;
my $c_products = 0;
my $c_syn      = 0;

print {$out}
    "DDB_G_ID\tGene_Name\tGene_Product\tAlternative_gene_name\tObject_type\tTaxon\tParent_Object\tUniprotKB:ID\n";
for my $ddbg ( sort keys %hash_gp2protein ) {

    # ddbg
    print {$out} $ddbg . "\t";

    # Gene name
    print {$out} $hash_ddbg2gene_name{$ddbg} . "\t";

    # Gene product
    my $is_product = $hash_geneproduct{$ddbg};
    if ( !$is_product ) {
        print {$out} " \t";
    }
    else {
        print {$out} $hash_geneproduct{$ddbg} . "\t";
        $c_products++;
    }

    # gene synonyms
    my $is_syn = $hash_gene_synonym{$ddbg};
    if ( !$is_syn ) {
        print {$out} " \t";
    }
    else {
        print {$out} $is_syn . "\t";
        $c_syn++;
    }

    # Object type, taxon
    print {$out} "gene\ttaxon:44689\t \t";

    # Uniprot ID
    print {$out} "UniProtKB:".$hash_gp2protein{$ddbg} . "\n";

    $c_genes++;
}

say "\nDouble checking numbers ";
say "\t- Has products: " . $c_products;
say "\t- Has synonyms: " . $c_syn;

$dbh->disconnect();

exit;

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# get_gp2protein
#
# Map DDB_G_ID to Uniprot IDs from gp2protein file.
# Use this as a list of genes (DDB_G ids)
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub get_gp2protein {

    my ($dbh) = @_;

    my $filename = "data/gp2protein.dictyBase";
    open my $FILE, '<', $filename or die "Cannot open '$filename'!\n";

    my %hash_gp2protein = ();

    # stats
    my $c_regex = 0;

    foreach my $line (<$FILE>) {
        chomp($line);
        if ( $line =~ /dictyBase:(\S+)\s+UniProtKB:(\w{6})/ ) {
            my $ddb = $1;
            my $uni = $2;

            if ( !$hash_gp2protein{$ddb} ) {
                $hash_gp2protein{$ddb} = $uni;
                $c_regex++;
            }
            else {
                die "\n\nOooops " . $line . " is repeated!!\n";
            }
        }
    }

    say "\tNumber of DDB_G to Uniprot: " . $c_regex;

    return (%hash_gp2protein);

    # my %hash_gp2protein = get_gp2protein($dbh);
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# get_gen_locus_name
#
# SQL Statement: 1 to 1
# It selects DDB_G ID, locus, and gene name from the database
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub get_gen_locus_name {

    my ( $dbh, $hash ) = @_;

    my %hash_gp2protein = %$hash;

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
        my @data
            = $dbh->selectrow_array( $statement_genename, {}, ($ddbg_id) );

        my $DDB_G     = $data[0];
        my $locus_no  = $data[1];
        my $gene_name = $data[2];

        # just a control
        if ( !$DDB_G ) {
            die
                "\noh no!!! how is this possible there is no DDB_G_ID!!! (from get_gen_locus_name)\n";
        }
        elsif ( !$locus_no ) {
            die
                "\noh no!!! how is this possible there is no feature_id (locus number)!!!(from get_gen_locus_name)\n";
        }
        elsif ( !$gene_name ) {
            die
                "\noh no!!! how is this possible there is no gene name!!! (from get_gen_locus_name)\n";
        }

        # Double checking
        if ( !$ddbg2gene_name{$DDB_G} ) {
            $ddbg2gene_name{$DDB_G} = $gene_name;
        }
        else {
            die
                "\n\nWhattttt??? ERROR! Something is wrong (from get_gen_locus_name)\n\n";
        }

        $ddbg2locus_number{$DDB_G} = $locus_no;
    }

    return ( \%ddbg2gene_name, \%ddbg2locus_number );

 # my ($hash_gene, $hash_locus) = get_gen_locus_name($dbh, \%hash_gp2protein);
 # my %hash_ddbg2gene_name = %$hash_gene;
 # my %hash_ddbg2locus_number = %$hash_locus;
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# SQL Statement: 1 to 1
# For a hash of locus numbers, gets the gene PRODUCT from the database
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub get_gene_products {

    my ( $dbh, $hash ) = @_;

    my %ddbg2locus_number = %$hash;

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

    my %hash_geneproduct = ();

    my $count_no  = 0;    # count no gene product
    my $count_yes = 0;    # count has product
    my $count_t   = 0;    # total number

    for my $ddb ( sort keys %ddbg2locus_number ) {

        my $locus_no = $ddbg2locus_number{$ddb};
        my @data
            = $dbh->selectrow_array( $statement_geneproduct, {},
            ($locus_no) );

        my $gene_product = '';
        $gene_product = $data[0];
        if ( !$gene_product ) {
            $count_no++;
            $hash_geneproduct{$ddb} = "";
        }
        else {
            $count_yes++;
            $hash_geneproduct{$ddb} = $gene_product;
        }
        $count_t++;
    }

    say "\n\twith Gene Product: "
        . $count_yes
        . "\n\twithout gene product: "
        . $count_no
        . "\n\tTotal: "
        . $count_t;

    return (%hash_geneproduct);

   # my %hash_geneproduct = get_gene_products($dbh, \%hash_ddbg2locus_number);
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# get_gene_alt_name
#
# SQL statement: 1 to many
# For each DDB_G ID, get all the gene and protein alternative names
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
sub get_gene_alt_names {

    my ( $dbh, $hash ) = @_;

    my %hash_gp2protein = %$hash;

    my $statement_syn = <<"STATEMENT";
SELECT wm_concat(syn.name) gsyn
FROM cgm_chado.feature gene
JOIN dbxref on dbxref.dbxref_id=gene.dbxref_id
LEFT JOIN cgm_chado.feature_synonym fsyn on gene.feature_id=fsyn.feature_id
LEFT JOIN cgm_chado.synonym_ syn on syn.synonym_id=fsyn.SYNONYM_ID
WHERE dbxref.accession = ?
GROUP BY dbxref.accession
STATEMENT

    my $count_syn   = 0;
    my $count_nosyn = 0;
    my $total       = 0;

    my %hash_gene_synonym = ();

    for my $ddbg_id ( sort keys %hash_gp2protein ) {

        my $syn = '';

        my @data = $dbh->selectrow_array( $statement_syn, {}, ($ddbg_id) );

        if ( $data[0] ) {
            $syn = $data[0];
            $syn =~ s/,/\|/g;
            $hash_gene_synonym{$ddbg_id} = $syn;
            $count_syn++;
        }
        else {
            $hash_gene_synonym{$ddbg_id} = "";
            $count_nosyn++;
        }
        $total++;
    }

    # Alternative gene and protein names
    say "\n\tWith syn: " . $count_syn;
    say "\tWithout syn  : " . $count_nosyn;
    say "\tTotal DDB_G ids: " . $total;

    return (%hash_gene_synonym);

    # my %hash_gene_synonym = get_gene_alt_names ($dbh, \%hash_gp2protein);
}

=head1 NAME

generate-gpi-file.pl - Generate a GPI file from the dictyBase

=head1 VERSION
 
Version 3.3: it differs from gen_gpi_file_gp2protein-v2.pl in:
- It runs from the root of the github project (change the path to the files)

=head1 SYNOPSIS

perl generate-gpi-file.pl  --host=<Oracle DSN> --user=<Oracle user> --passwd=<Oracle password>

(It resquires the gp2protein file at Export-GPI-from-Oracle/data/gp2protein.dictyBase).


=head1 OPTIONS

 --host          Oracle database HOST
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

There are a group of 501 genes from the gp2protein file that are TE or RTE.

