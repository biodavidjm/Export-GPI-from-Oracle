#!/usr/bin/perl -w

use POSIX;
use strict;
use feature qw/say/;
use warnings;

use DBI;

# Connecting to the Database on nubic 
my $user = "CGM_CHADO";
my $passwd = "CGM_CHADO";

print "Connecting to vm.nubic...";
my $dbh = DBI->connect("dbi:Oracle:host=dicty-oracle-vm.nubic.northwestern.edu;sid=orcl;port=1521", $user,$passwd,
	# {
	# 	PrintError => 0, #don't report errors via warn
	# 	RaiseError => 1, # Please, report error via die()
	# }
) or die "\n\nOh no! I could not connect to the Oracle database:" . DBI->errstr . "\n\n";

print " Successfully connected to dicty-oracle-vm.nubic.northwestern.edu\n\n";

# Adjusting the LongReadLen to avoid errors:
print "LongReadLen is '", $dbh->{LongReadLen}, "'\n";
# print "LongTruncOk is ", $dbh->{LongTruncOk}, "\n";
$dbh->{LongReadLen} = 25000;
print "LongReadLen is '", $dbh->{LongReadLen}, "'\n";

# Query to get the alternative names
my $query = '
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

SELECT dg.gene_id gene_id, gene.name,wm_concat(syn.name) gsyn
FROM cgm_chado.feature gene
JOIN cgm_chado.dbxref on gene.dbxref_id=dbxref.dbxref_id
JOIN dicty_coding_genes dg on dg.gene_id=dbxref.accession
LEFT JOIN cgm_chado.feature_synonym fsyn on gene.feature_id=fsyn.feature_id
LEFT JOIN cgm_chado.synonym_ syn on syn.synonym_id=fsyn.SYNONYM_ID
group by gene.name,dg.gene_id
order by gene.name DESC
';


# my $query = '
# SELECT feature_id, organism_id, uniquename, name FROM cgm_chado.feature WHERE organism_id = 10
# ';

my $results = $dbh->prepare($query);
$results->execute() 
	or die "\n\nOh no! I could not execute: " . DBI->errstr . "\n\n";

# print "\n\tPrint out query\n\t".$query."\n";

my %allnames = ();
my @row;
my $c = 0;
my $n = 0;

while (@row = $results->fetchrow_array())
{
	foreach (@row) {$_ = '' unless defined};
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

# Test2Delete: Access one element
print "\nTest on one element\n";
foreach ( @{$allnames{'DDB_G0285391'}} )
{
    print $_." ";
}

my $t = 1;
for my $ddbs (keys %allnames)
{
	print $t." ".$ddbs.": ".$allnames{$ddbs}[0];
	if ($allnames{$ddbs}[1])
	{
		" -> ". $allnames{$ddbs}[1]."\n";
	}
	else
	{
		print "\n";
	}
	$t++;
}

# Need stats to check?
print "\nYes: ".$c."\n";
say "No: ".$n;


my @result = $dbh->selectrow_array("SELECT count(*) FROM feature");
say "\tNumber of features at dicty: ".$result[0];


# my $oresults = $dbh->prepare("SELECT fe.uniquename fe.name FROM feature");
# $oresults->execute() or die "\n\nOh no! I could not execute: " . DBI->errstr . "\n\n";

# while (my @rows = $oresults->fetchrow_array())
# {

# 	foreach my $element (@rows)
# 	{
# 		print $element." ";
# 	}
# 	print "\n";
# }

# print "\n\tNow print from the hash:\n";
# foreach my $id (sort { $a <=> $b } keys %testhash)
# {
# 	print "\t\tSpecie_ID: $id - $testhash{$id}[1] (".$testhash{$id}[2]." ".$testhash{$id}[3]."\n";
# }


# $dbh->disconnect();
# say "\nWe are done (and disconnected from DB). Bye bye!\n";

exit;
