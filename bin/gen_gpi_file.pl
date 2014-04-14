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

use Time::Piece;
# my $t = Time::Piece->strptime("20111230", "%Y%m%d");
# print $t->strftime("%d-%b-%Y\n");

# Validation section
my %options;
GetOptions( \%options, 'dsn=s', 'user=s', 'passwd=s');
for my $arg (qw/dsn user passwd/)
{
	# print "\n\tError: Arguments required! Example:\n";
	die "\tperl gen_gpi_file.pl -dsn=ORACLE_DNS -user=USERNAME -passwd=PASSWD\n\n" if not defined $options{$arg};
}

my $host = $options{dsn};
my $user = $options{user};
my $pass = $options{passwd};

# Connecting to the Database
print "Connect to the database, ";
my $dbh = DBI -> connect("dbi:Oracle:host=$host;sid=orcl;port=1521", $options{user}, $options{passwd}, 
	{ RaiseError => 1, LongReadLen => 2**20 } );


# Database setup
# Select gene name, gene synonym and protein synonym, DDB_G ID
# Excluding pseudogenes
my $statement = '
WITH dicty_coding_genes AS (
SELECT dbxref.accession gene_id
FROM cgm_chado.feature gene
JOIN organism ON organism.organism_id=gene.organism_id
JOIN dbxref on dbxref.dbxref_id=gene.dbxref_id
JOIN cgm_chado.cvterm gtype on gtype.cvterm_id=gene.type_id
JOIN cgm_chado.feature_relationship frel ON frel.object_id=gene.feature_id
JOIN cgm_chado.feature mrna ON frel.subject_id=mrna.feature_id
JOIN cgm_chado.cvterm mtype ON mtype.cvterm_id=mrna.type_id
WHERE gtype.name=\'gene\'
AND mtype.name=\'mRNA\'
AND organism.common_name = \'dicty\'
AND gene.name NOT LIKE \'%\_ps%\'
ESCAPE \'\\\'
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
';

print "execute statement ";
my $results = $dbh->prepare($statement);
$results->execute() or die "\n\nOh no! I could not execute: " . DBI->errstr . "\n\n";
print "...done ";


# ADD the data to a hash
my $row_statement = $results->fetchall_arrayref();

# My hash to store
my %allnames = ();

foreach my $linea (@$row_statement)
{
	my ($gene_id, $gene_name, $gsyn) = @$linea;
	if ($gene_id)
	{
		if( !$allnames{$gene_id} )
		{
			my @temp = ($gene_name,$gsyn);
			$allnames{$gene_id} = [@temp];
		}
	}
}
print "...and data in hashes\n";

# SQL to get the gen product
my $statement_gene_product = '
SELECT dx.accession AS DDB_G_ID, gp.gene_product, (TO_CHAR(gp.date_created, \'YYYY-MM-DD\'))
FROM cgm_ddb.gene_product gp
INNER JOIN cgm_ddb.locus_gp lgp 	ON 		lgp.gene_product_no = gp.gene_product_no
INNER JOIN cgm_chado.v_gene_dictybaseid d      ON 	lgp.locus_no = d.gene_feature_id
INNER JOIN cgm_chado.v_gene_features g 		ON   g.feature_id = d.gene_feature_id
INNER JOIN cgm_chado.dbxref dx              ON g.dbxref_id = dx.dbxref_id
INNER JOIN cgm_chado.organism o             ON o.organism_id    = g.organism_id
INNER JOIN cgm_chado.feature f 			    ON f.dbxref_id = g.dbxref_id
WHERE o.common_name = \'dicty\'
ORDER BY dx.accession, gp.gene_product
';


# database handle
my $result_gene_product = $dbh->prepare($statement_gene_product);

print "Execute statement_gene_product ";
$result_gene_product->execute() or die "\n\nOh no! I could not execute: " . DBI->errstr . "\n\n";
print "...done ";

# ADD all the info to a hash
my $rowproduct = $result_gene_product->fetchall_arrayref();

# hash to store
my %hashgenproduct = ();

# Transverse
foreach my $line (@$rowproduct)
{
	my ($ddb_g, $gene_product, $date_created) = @$line;
	# print $ddb_g." Gene_product: ".$gene_product." Date: ".$date_created."\n";	

	# If two dates are the same, it must be a weird error
	if ( !$hashgenproduct{$ddb_g}{$date_created} )
	{
		$hashgenproduct{$ddb_g}{$date_created} = $gene_product;
	}
}

print "...and data in hashes\n";

# p p p p p p p p p p p p p p p p p p p p p p p p p p p p p p p p p
# for my $a (sort keys %hashgenproduct)
# {
	
# 	my $totalnumber = keys %{$hashgenproduct{$a} };
# 	if ($totalnumber > 1)
# 	{
# 		print $totalnumber." ".$a." ---> \n";
# 		for my $b (reverse sort keys %{$hashgenproduct{$a} } )
# 		{
				
# 			print "\t".$b."  ".$hashgenproduct{$a}{$b}."\n";
# 		}
# 		print "\n";
# 		my $highest = (reverse sort keys %{$hashgenproduct{$a} } )[0];
# 		print "\t\t".$highest."\n";
# 	}
# }
# p p p p p p p p p p p p p p p p p p p p p p p p p p p p p p p p p


my $statement_ddb2uniprot = '
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
ptype.name = \'polypeptide\'
AND
mtype.name = \'mRNA\'
AND
gtype.name = \'gene\'
AND 
db.name = \'DB:SwissProt\'
';

# database handle
my $results_ddb2uniprot = $dbh->prepare($statement_ddb2uniprot);

print "execute statement_ddb2uniprot ";
$results_ddb2uniprot->execute() or die "\n\nOh no! I could not execute: " . DBI->errstr . "\n\n";
print "...done\n";

# ADD all the info to a hash
my $rowddb2uniprot = $results_ddb2uniprot->fetchall_arrayref();

# hash to store
my %hash_ddb2uniprot = ();
my %hash_uniprot2ddb = ();

# check point charlie
my %noredundancies = ();
my $n = 1;

# Transverse
foreach my $lineddb (@$rowddb2uniprot)
{
	my ($ddb_g, $uniprot_id) = @$lineddb;
	# print $ddb_g." = ".$uniprot_id."\n";
	if(!$hash_ddb2uniprot{$ddb_g})
	{
		$hash_ddb2uniprot{$ddb_g} = $uniprot_id;
	}
	else
	{
		if ($uniprot_id ne $hash_ddb2uniprot{$ddb_g})
		{
			# print $ddb_g." -> ".$uniprot_id." and ".$hash_ddb2uniprot{$ddb_g}."\n";
			# exit;			
		}
	}
	if (!$hash_uniprot2ddb{$uniprot_id})
	{
		$hash_uniprot2ddb{$uniprot_id} = $ddb_g;
	}
	else
	{
		if ($ddb_g ne $hash_uniprot2ddb{$uniprot_id})
		{
			if (!$noredundancies{$uniprot_id})
			{
				$noredundancies{$uniprot_id} = 1;	
				# print $n." ".$uniprot_id." -> ".$ddb_g." ".$hash_uniprot2ddb{$uniprot_id}."\n";
				$n++;
			}
			# exit;
		}
	}

}

print "...and data in hashes\n";

exit;

# OUTPUT FILE
# - - - - - - - - - - - - - - - - -
# Output file name (uses date & time)
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $ymd = sprintf("%04d%02d%02d_%02d%02d%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my $outfile = "$ymd.gpi_dicty";
open (FILE, ">".$outfile);

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

print FILE $headinfo."\n";

my $p = 0; #I'll use it at the end
my $gene = "gene";
my $taxon = "taxon:44689";
my $nulldata = "NULL";

#pppppppppppppppppppppppppppppppppppppppppppprint
for my $ddbs (keys %allnames)
{
	print FILE $ddbs."\t".$allnames{$ddbs}[0]."\t";

	if ($allnames{$ddbs}[1])
	{
		my $nocomma = $allnames{$ddbs}[1];
		$nocomma =~ s/,/\|/g;
		print FILE "\t", $nocomma."\t";
	}
	else
	{
		print FILE $nulldata."\t";
	}
	print FILE $gene."\t".$taxon."\tDictyBase:".$ddbs."\n";
	$p++;
}
#pppppppppppppppppppppppppppppppppppppppppppprint

print "Dicty GPI file (".$p." genes): ".$outfile."\n";

close FILE;
$dbh->disconnect();


=head1 NAME

gen_gpi_file.pl - Generate a GPI file (YYYYMMDD_HHMMSS.gpi_dicty) from the dictyBase


=head1 SYNOPSIS

perl gen_gpi_file.pl  --dsn=<Oracle DSN> --user=<Oracle user> --passwd=<Oracle password>


=head1 OPTIONS

 --dsn           Oracle database DSN
 --user          Database user name
 --passwd        Database password

=head1 DESCRIPTION

Connect to the dictyOracle database and dump to a file (YYYYMMDD_HHMMSS.gpi_dicty) the following information:

Columns:

name                   required? cardinality   GAF column
DB_Object_ID           required  1             2/17      
DB_Object_Symbol       required  1             3         
DB_Object_Name         optional  0 or greater  10        
DB_Object_Synonym(s)   optional  0 or greater  11        
DB_Object_Type         required  1             12        
Taxon                  required  1             13        
Parent_Object_ID       optional  0 or 1        -         
DB_Xref(s)             optional  0 or greater  -         
Properties             optional  0 or greater  -         