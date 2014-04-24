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

my $row_statement = $results->fetchall_arrayref();

my %allnames = ();

my $count_statement_in  = 0;
my $count_statement_out = 0;
foreach my $linea (@$row_statement) {
    my ( $gene_id, $gene_name, $gsyn ) = @$linea;

    if ($gene_id) {
        $count_statement_in++;
        if ( !$allnames{$gene_id} ) {
            my @temp = ( $gene_name, $gsyn );
            $allnames{$gene_id} = [@temp];
        }
        else {
            $count_statement_out++;
        }
    }
}
print " (and now data in hashes also)\n";

print "\tIN: " . $count_statement_in . " OUT: " . $count_statement_out . "\n";

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Database setup
# Statement 2: statement_splitgenes. It selects split genes in
# order to address the curiosity of Petra. It was going to be used as a filter
# (parsing them out), but I was advised to include them in the final output
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

my $statement_splitgenes = "
WITH split_replaced AS( SELECT dbxref.accession acc 
      FROM cgm_chado.featureprop fprop 
      JOIN cgm_chado.cvterm on cvterm.cvterm_id=fprop.type_id 
      JOIN cgm_chado.feature on feature.feature_id=fprop.feature_id 
      JOIN cgm_chado.cvterm ftype on ftype.cvterm_id=feature.type_id 
      JOIN cgm_chado.dbxref on feature.dbxref_id=dbxref.dbxref_id 
     WHERE ftype.name = 'gene'
       AND cvterm.name = 'replaced by' 
       AND feature.is_deleted = 1 
       AND feature.uniquename like 'DDB_G%'
     GROUP BY dbxref.accession
    HAVING count(to_char(fprop.value)) > 1  )
SELECT to_char(fprop.value) split_id 
  FROM cgm_chado.feature 
  JOIN cgm_chado.featureprop fprop on fprop.feature_id=feature.feature_id 
  JOIN cgm_chado.dbxref on dbxref.dbxref_id=feature.dbxref_id 
  JOIN cgm_chado.cvterm on cvterm.cvterm_id=fprop.type_id 
  JOIN split_replaced on split_replaced.acc=dbxref.accession 
 WHERE cvterm.name = 'replaced by' 
   AND fprop.value like 'DDB_G%'
";

my $result_sliptgenes = $dbh->prepare($statement_splitgenes);

print "> Execute statement_splitgenes ";
$result_sliptgenes->execute()
    or die "\n\nOh no! I could not execute: " . DBI->errstr . "\n\n";
print " done!!";

my $rowsplitgenes = $result_sliptgenes->fetchall_arrayref();

my %hash_splitgenes = ();

foreach my $line (@$rowsplitgenes) {
    my ($split_id) = @$line;
    chomp($split_id);

    if ( !$hash_splitgenes{$split_id} ) {
        $hash_splitgenes{$split_id} = 1;
    }
    else {
        print "\n\nERROR! \n";
        print "This gene id" . $split_id . " is retrieve twice?\n";
        exit;
    }
}

print " (and now data in hashes also)\n";

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Database setup

# Statement 3: statement_gene_product. It selects gene products. For those genes
# with several gene products, the newest one is selected.
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

my $statement_gene_product = "
SELECT dx.accession AS DDB_G_ID, gp.gene_product, (TO_CHAR(gp.date_created, 'YYYY-MM-DD'))
FROM cgm_ddb.gene_product gp
INNER JOIN cgm_ddb.locus_gp lgp     ON      lgp.gene_product_no = gp.gene_product_no
INNER JOIN cgm_chado.v_gene_dictybaseid d      ON   lgp.locus_no = d.gene_feature_id
INNER JOIN cgm_chado.v_gene_features g      ON   g.feature_id = d.gene_feature_id
INNER JOIN cgm_chado.dbxref dx              ON g.dbxref_id = dx.dbxref_id
INNER JOIN cgm_chado.organism o             ON o.organism_id    = g.organism_id
INNER JOIN cgm_chado.feature f              ON f.dbxref_id = g.dbxref_id
WHERE o.common_name = 'dicty'
ORDER BY dx.accession, gp.gene_product
";

my $result_gene_product = $dbh->prepare($statement_gene_product);

print "> Execute statement_gene_product ";
$result_gene_product->execute()
    or die "\n\nOh no! I could not execute: " . DBI->errstr . "\n\n";
print " done!!";

my $rowproduct = $result_gene_product->fetchall_arrayref();

my %hashgenproduct = ();

foreach my $line (@$rowproduct) {
    my ( $ddb_g, $gene_product, $date_created ) = @$line;
    chomp($ddb_g);

    if ( !$hashgenproduct{$ddb_g}{$date_created} ) {
        $hashgenproduct{$ddb_g}{$date_created} = $gene_product;
    }
}

print " (and now data in hashes also)\n";

# Final gen product hash (with only one gen product, the newest)
my %hash_gen_product       = ();
my $count_one_geneproduct  = 0;
my $count_more_geneproduct = 0;

for my $ddb ( sort keys %hashgenproduct ) {

    my $totalnumber = keys %{ $hashgenproduct{$ddb} };
    if ( $totalnumber > 1 ) {

        # printing total
        my $last_date = ( reverse sort keys %{ $hashgenproduct{$ddb} } )[0];
        my $gene_product_selected = $hashgenproduct{$ddb}{$last_date};
        $hash_gen_product{$ddb}{$last_date} = $gene_product_selected;
        $count_more_geneproduct++;

    }
    else {
        my $last_date             = ( keys %{ $hashgenproduct{$ddb} } )[0];
        my $gene_product_selected = $hashgenproduct{$ddb}{$last_date};
        $hash_gen_product{$ddb}{$last_date} = $gene_product_selected;
        $count_one_geneproduct++;
    }
}

print "\t-DDB_G with only ONE product: " . $count_one_geneproduct . "\n";
print "\t-DDB_G with MORE THAN one pd: " . $count_more_geneproduct . "\n";

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Database setup
# Statement 4: statement_ddb2uniprot. It maps DDB_G_ID into Uniprot IDs.
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

my $statement_ddb2uniprot = "
SELECT gxref.accession geneid, dbxref.accession uniprot 
FROM dbxref
JOIN db 
ON db.db_id = dbxref.db_id
JOIN feature_dbxref fxref ON
fxref.dbxref_id = dbxref.dbxref_id
JOIN feature polypeptide ON 
polypeptide.feature_id = fxref.feature_id
JOIN feature_relationship frel 
ON polypeptide.feature_id = frel.subject_id
JOIN feature transcript 
ON transcript.feature_id = frel.object_id
JOIN feature_relationship frel2 
ON frel2.subject_id = transcript.feature_id
JOIN feature gene 
ON frel2.object_id = gene.feature_id
JOIN cvterm ptype
ON ptype.cvterm_id = polypeptide.type_id
JOIN cvterm mtype 
ON mtype.cvterm_id = transcript.type_id
JOIN cvterm gtype 
ON gtype.cvterm_id = gene.type_id
JOIN dbxref gxref 
ON gene.dbxref_id = gxref.dbxref_id
WHERE 
ptype.name = 'polypeptide'
AND
mtype.name = 'mRNA'
AND
gtype.name = 'gene'
AND 
db.name = 'DB:SwissProt'
";

my $results_ddb2uniprot = $dbh->prepare($statement_ddb2uniprot);

print ">Execute statement_ddb2uniprot ";
$results_ddb2uniprot->execute()
    or die "\n\nOh no! I could not execute: " . DBI->errstr . "\n\n";
print " done!!";

# ADD all the info to a hash
my $rowddb2uniprot = $results_ddb2uniprot->fetchall_arrayref();

# hash to store
my %hash_ddb2uniprot = ();
my %hash_uniprot2ddb = ();

# check point charlie
my %noredundancies = ();
my $cred           = 1;

# Transverse
foreach my $lineddb (@$rowddb2uniprot) {
    my ( $ddb_g, $uniprot_id ) = @$lineddb;
    chomp($ddb_g);
    chomp($uniprot_id);
    if ( !$hash_ddb2uniprot{$ddb_g} ) {
        $hash_ddb2uniprot{$ddb_g} = $uniprot_id;
    }

    if ( !$hash_uniprot2ddb{$uniprot_id} ) {
        $hash_uniprot2ddb{$uniprot_id} = $ddb_g;
    }
}

print " (and now data in hashes also)\n";

my $number_ddb2uniprot = keys %hash_ddb2uniprot;
print "\t-DDB_G ids with Uniprot IDS: " . $number_ddb2uniprot . "\n";

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
my $outfile = "$ymd.gpi_dicty";

open my $out, '>', $outfile
    or print "Big problem: I can't create '$outfile'";

    # Head info to the GPI FILE
    my $headinfo = "
!
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
! Generated on localtime()
!
";

print {$out} $headinfo . "\n";

my $count_genes = 0;               #I'll use it at the end
my $gene        = "gene";
my $taxon       = "taxon:44689";

# Checking:
my $count_geneprod   = 0;
my $count_nogeneprod = 0;
my $count_altnames   = 0;
my $count_noaltnames = 0;
my $count_uniprot    = 0;
my $count_nouniprot  = 0;

my $count_splitgenes = 0;

#pppppppppppppppppppppppppppppppppppppppppppprint
for my $ddbs ( keys %allnames ) {
    if ( $hash_splitgenes{$ddbs} ) {
        $count_splitgenes++;
    }

    print {$out} $ddbs . "\t" . $allnames{$ddbs}[0] . "\t";

    my $date_gene_product = '';
    $date_gene_product = ( keys %{ $hash_gen_product{$ddbs} } )[0];

    my $gene_product = '';
    if ($date_gene_product) {
        $gene_product = $hash_gen_product{$ddbs}{$date_gene_product};
    }

    if ($gene_product) {
        print {$out} $gene_product . "\t";
        $count_geneprod++;
    }
    else {
        print {$out} "";
        $count_nogeneprod++;
    }

    if ( $allnames{$ddbs}[1] ) {
        my $nocomma = $allnames{$ddbs}[1];
        $nocomma =~ s/,/\|/g;
        print {$out} $nocomma . "\t";
        $count_altnames++;
    }
    else {
        print {$out} "";
        $count_noaltnames++;
    }

    print {$out} $gene . "\t" . $taxon . "\tDictyBase:" . $ddbs . "\t";
    my $map_uniprot = '';
    $map_uniprot = $hash_ddb2uniprot{$ddbs};
    if ($map_uniprot) {
        print {$out} $map_uniprot . "\n";
        $count_uniprot++;
    }
    else {
        print {$out} "\n";
        $count_nouniprot++;
    }
    $count_genes++;
}

#pppppppppppppppppppppppppppppppppppppppppppprint

print "\nDicty GPI file ("
    . $count_genes
    . " genes, $count_splitgenes are split genes)\n";
print "\t- Gene products: "
    . $count_geneprod
    . " \tNo Gene Product: "
    . $count_nogeneprod . "\n";
print "\t- Alternt names: "
    . $count_altnames
    . " \tNo Alt Names   : "
    . $count_noaltnames . "\n";
print "\t- Uniprot ids  : "
    . $count_uniprot
    . " \tNo uniprot     : "
    . $count_nouniprot . "\n";

close $out;
$dbh->disconnect();

exit;

=head1 NAME

gen_gpi_file-v2.pl - Generate a GPI file from the dictyBase


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



