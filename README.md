Export-GPI-from-Oracle
======================

Dump a gp_information (GPI) file from our Oracle database according to the GO specifications


### GPI format

The description of the GPI file format can be found in the [Gene Ontology wiki](http://wiki.geneontology.org/index.php/Final_GPAD_and_GPI_file_format).

***
column | name                    | required? | cardinality  | GAF column  | Example for UniProt | Example for WormBase
-------| ----------------        | --------- | -----------  |  ---------  |  ------------------ | --------------------
01     | DB_Object_ID            | required  | 1            | 2/17        | Q4VCS5-1 | WBGene00000035
02     | DB_Object_Symbol        | required  | 1            | 3           | AMOT | ace-1
03     | DB_Object_Name          | optional  | 0 or 1       | 10          | Angiomotin	
04     | DB_Object_Synonym(s)    | optional  | 0 or greater | 11	KIAA1071|AMOT | ACE1
05     | DB_Object_Type          | required  | 1            | 12          | protein | gene
06     | Taxon                   | required  | 1            | 13          | taxon:9606 | taxon:6239
07     | Parent_Object_ID        | optional  | 0 or 1       | -           | UniProtKB:Q4VCS5 | WB:WBGene00000035
08     | DB_Xref(s)              | optional  | 0 or greater | -           | - | UniProtKB:P38433
09     | Gene_Product_Properties | optional  | 0 or greater | -           | See Note 4 below	
***


