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

# Validation section
my %options;
GetOptions( \%options, 'dsn=s', 'user=s', 'passwd=s');
for my $arg (qw/dsn user passwd/)
{
	# print "\n\tError: Arguments required! Example:\n";
	die "\tperl gen_gpi_file.pl --dsn=ORACLE_DNS --user=USERNAME --passwd=PASSWD\n\n" if not defined $options{$arg};
}

my $host = $options{dsn};
my $user = $options{user};
my $pass = $options{passwd};

# Connecting to the Database
print "Connecting to the database, ";
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
$results->execute() 
	or die "\n\nOh no! I could not execute: " . DBI->errstr . "\n\n";
print "...done\n";

# ADD all the info to a hash (although I could print everything here)
my %allnames = ();
my @row;
my $c = 0;
my $n = 0;

while (@row = $results->fetchrow_array())
{
	foreach (@row) {$_ = '' unless defined}; # Check point Charlie
	if ($row[0])
	{
		if ( !$allnames{$row[0]} )
		{
			my @temp = ($row[1],$row[2]);
			$allnames{$row[0]} = [@temp]
		}
	}
}
warn "Data fetching terminated early by error: $DBI::errstr\n"
      if $DBI::err;


# OUTPUT FILE
# - - - - - - - - - - - - - - - - -
# Output file name
my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
my $ymd = sprintf("%04d%02d%02d_%02d%02d%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
my $outfile = "$ymd.gpi_dicty";

print $outfile."\n";

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

print $headinfo."\n";

exit;

my $p = 0; #I'll use it at the end
my $gene = "gene";
my $taxon = "taxon:44689";
my $nulldata = "NULL";

#pppppppppppppppppppppppppppppppppppppppppppprint
for my $ddbs (keys %allnames)
{
	printf "%-16s %-16s ", $ddbs, $allnames{$ddbs}[0];

	# print "01:".$ddbs." 02:".$allnames{$ddbs}[0]." 03:NULL ";
	if ($allnames{$ddbs}[1])
	{
		my $nocomma = $allnames{$ddbs}[1];
		$nocomma =~ s/,/\|/g;
		printf "%-15s ", $nocomma." ";
	}
	else
	{
		printf "%-15s ", $nulldata;
	}
	printf "%-15s %-15s %-15s\n",$gene, $taxon, $ddbs;
	# printf "05: gene 06:Taxon:44689 07:".$ddbs." 08:NULL 09:NULL\n";
	$p++;
}
#pppppppppppppppppppppppppppppppppppppppppppprint


my @result = $dbh->selectrow_array("SELECT count(*) FROM feature");
say "\tTotal number of features at dicty: ".$result[0];
say "\tPrinted here: ".$p."\n";
$dbh->disconnect();


=head1 NAME

gen_gpi_file.pl - Generate a GPI file (YYYYMMDD_dicty.gpi) from the dictybase


=head1 SYNOPSIS

perl gen_gpi_file.pl  --dsn <Oracle DSN> --user <Oracle user> ---pass <Oracle password>


=head1 OPTIONS

 --dsn           Oracle database DSN
 --user          Database user name
 --pass          Database password

=head1 DESCRIPTION

Connect to the dictyOracle database and dump to a file the following information:

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

