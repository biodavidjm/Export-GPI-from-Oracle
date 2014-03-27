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
my $dbh = DBI->connect("dbi:Oracle:host=dicty-oracle-vm.nubic.northwestern.edu;sid=orcl;port=1521", $user,$passwd) or die "\n\nOh no! I could not connect to the Oracle database:" . DBI->errstr . "\n\n";
print " Successfully connected to dicty-oracle-vm.nubic.northwestern.edu\n\n";

# First test: Let's counting the number of organisms

my @result = $dbh->selectrow_array("SELECT count(*) FROM organism");
say "\tNumber of organisms at dicty: ".$result[0];

my $results = $dbh->prepare("SELECT common_name FROM organism");
$results->execute() or die "\n\nOh no! I could not execute: " . DBI->errstr . "\n\n";
print "\n\tThese organisms are: \n";

while (my @rows = $results->fetchrow_array())
{
	my ($specie_name) = @rows;
	print "\t\t".$specie_name."\n";
}


my @result2 = $dbh->selectrow_array("SELECT COUNT(fcvt.feature_cvterm_id) annotations
FROM cgm_chado.feature_cvterm fcvt 
JOIN cgm_chado.feature gene ON gene.feature_id = fcvt.feature_id 
JOIN cgm_chado.cvterm type ON type.cvterm_id = gene.TYPE_ID 
JOIN cgm_chado.cvterm GO ON GO.cvterm_id = fcvt.cvterm_id 
JOIN cgm_chado.cv ON cv.cv_id = GO.cv_id
JOIN cgm_chado.organism ON organism.organism_id = gene.organism_id
WHERE  type.name = 'gene'
AND gene.is_deleted = 0
AND 
cv.name IN('molecular_function',   'biological_process',   'cellular_component')
AND GO.is_obsolete = 0
AND organism.common_name = 'dicty'");

say "\n\tCannonical query: ".$result2[0];


my @goann = $dbh->selectrow_array("SELECT COUNT (DISTINCT fcvt.feature_id) gene_with_annotations
FROM CGM_CHADO.feature_cvterm fcvt
JOIN CGM_CHADO.feature_cvtermprop fcvt_prop ON fcvt_prop.feature_cvterm_id = fcvt.feature_cvterm_id
JOIN CGM_CHADO.cvterm evterm ON evterm.cvterm_id=fcvt_prop.type_id
JOIN CGM_CHADO.cv ev ON ev.cv_id=evterm.cv_id
JOIN CGM_CHADO.cvtermsynonym evsyn ON evterm.cvterm_id=evsyn.cvterm_id
JOIN CGM_CHADO.cvterm syn_type ON syn_type.cvterm_id = evsyn.type_id
JOIN CGM_CHADO.cv syn_cv ON syn_cv.cv_id = syn_type.cv_id
JOIN CGM_CHADO.feature gene ON gene.feature_id = fcvt.feature_id
JOIN CGM_CHADO.cvterm type ON type.cvterm_id = gene.type_id
JOIN organism organism ON organism.organism_id = gene.organism_id
WHERE gene.is_deleted = 0
AND type.name = 'gene'
AND ev.name like 'evidence_code%'
AND syn_type.name IN ('EXACT', 'RELATED', 'BROAD')
AND syn_cv.name = 'synonym_type'
AND organism.common_name = 'dicty'");

say "\tNumber of GO annotations: " . $goann[0];


$dbh->disconnect();
say "\nJob done and disconnected. Bye bye\n";

exit;
