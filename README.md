Export-GPI-from-Oracle
======================

Dump a gp_information (GPI) file from our Oracle database according to the GO specifications

### Synopsis

```
`perl generate-gpi-file.pl  --dsn=<Oracle DSN> --user=<Oracle_user> --passwd=<Oracle password>`
```

### Output
The output is available at `data/` with the name YYYYMMDD_HHMMSS.gp2protein.gpi_dicty

### GPI format

The description of the GPI file format can be found in the [Gene Ontology wiki](http://wiki.geneontology.org/index.php/Final_GPAD_and_GPI_file_format).

***
column | name                    | required? | cardinality  | GAF column  | Example for UniProt | Example for WormBase
-------| ----------------        | --------- | -----------  |  ---------  |  ------------------ | --------------------
01     | DB_Object_ID            | required  | 1            | 2/17        | Q4VCS5-1            | WBGene00000035
02     | DB_Object_Symbol        | required  | 1            | 3           | AMOT                | ace-1
03     | DB_Object_Name          | optional  | 0 or 1       | 10          | Angiomotin
04     | DB_Object_Synonym(s)    | optional  | 0 or greater | 11 KIAA1071 | AMOT                | ACE1
05     | DB_Object_Type          | required  | 1            | 12          | protein             | gene
06     | Taxon                   | required  | 1            | 13          | taxon:9606          | taxon:6239
07     | Parent_Object_ID        | optional  | 0 or 1       | -           | UniProtKB:Q4VCS5    | WB:WBGene00000035
08     | DB_Xref(s)              | optional  | 0 or greater | -           | -                   | UniProtKB:P38433
09     | Gene_Product_Properties | optional  | 0 or greater | -           | See Note 4 below	
***

#### GPI file from other databases
- GPI files are available for Uniprot in this [site](ftp://ftp.ebi.ac.uk/pub/databases/GO/goa/UNIPROT/). And [this is the paper](http://www.ncbi.nlm.nih.gov/pmc/articles/PMC3245010/) related to it.

#### GPI FORMAT from Dictybase
Where is the info?

01 DB_Object_ID = dictyID (DDB#) = feature.uniquename

02 DB_Object_Symbol = GeneName = feature.name

03 DB_Object_Name = Gene Product (take the newest one, or think about it)

04 DB_Object_Synonym(s) = Alternative Gene names

05 DB_Object_Type = 'Gene' (Dicty is a gene centric database)

06 Taxon = 44689

07 Parent_Object_ID = DDB:GeneID (think about the problem of the different gene variants)

08 DB_Xref(s) = Either leave it empty or use the go2protein tool

09 Gene_Product_Properties = Think about it.


### Developing log

### Installation of DBD::Oracle on the Mac
Follow the instructions in the [General-Scripts readme file](https://github.com/dictyBase/General-Scripts/blob/master/README.md) about how to install DBD::Oracle on the Mac.

#### Refactoring
Incorporate issue's suggestions. 

* I made perltidy worked with Sublime Text 2 (it took me too much time to make it work on sublime, for stupid reasons)

* Create ``gen_gpi_file-v2.pl``: incorporate some of the options before I start the next version, which will follow the issue's suggestions. The stats from this file:

	```
	> Execute statement  done!! (and now data in hashes also)
		IN: 12862 OUT: 0
	> Execute statement_splitgenes  done!! (and now data in hashes also)
	> Execute statement_gene_product  done!! (and now data in hashes also)
		-DDB_G with only ONE product: 7179
		-DDB_G with MORE THAN one pd: 1389
	>Execute statement_ddb2uniprot  done!! (and now data in hashes also)
		-DDB_G ids with Uniprot IDS: 12690

	Dicty GPI file (12862 genes, 53 are split genes)
		- Gene products: 7950 	No Gene Product: 4912
		- Alternt names: 1826 	No Alt Names   : 11036
		- Uniprot ids  : 12674 	No uniprot     : 188
	```

* Create ``gen_gpi_file-v3.pl``: implementing Sidd's suggestions

With this script, I have found multiple problems that I need to resolve one by one. But in order to have a good version of the GPI file ready to go, I will write a temporal script taking a safer approach:

* Create ``gen_gpi_file_gp2protein.pl``: uses the gp2protein.dictyBase file as the reference for protein coding genes, which contains the list of protein coding genes (DDB_G to Uniprot).
	* This version does not have modules and does not print the bpi file 
	* There are a total of 12,201 DDB_G ids with a Uniprot ID.
	* Two genes do not have a Uniprot ID. These are: 
	
		```
		dictyBase:DDB_G0278875	NCBI_GP:EAL68039.1 ---> do not have an Uniprot id in dictyweb
		dictyBase:DDB_G0271556	NCBI_GP:EAL71642.2 ---> do have a uniprot id in dictyweb:V9H176 
		```
### Stats 

The script gets:
	
```
February, 2015 02 09

> Getting ddb_g and Uniprot from gp2protein file...
	Number of DDB_G to Uniprot: 12201
> Getting gene name...  done!
> Getting gene product...
	with Gene Product: 7925
	without gene product: 4276
	Total: 12201
> Getting gene synonyms...
	With syn: 1833
	Without syn  : 10368
	Total DDB_G ids: 12201

Double checking numbers
	- Has products: 7925
	- Has synonyms: 1833
```




