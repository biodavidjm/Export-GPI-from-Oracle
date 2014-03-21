Export-GPI-from-Oracle
======================

Dump a gp_information (GPI) file from our Oracle database according to the GO specifications


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

### The Plan / challenges

I will test my scripts on oracle-vm of nubic. I will write scripts that will connect to the oracle database and dump the data. These are the challenges ahead:

* Keep synchronized this github working directory between my computer and the nubic-vm
* Write Perl scripts to interact with the database. These scripts will basically take the required data from sql queries and store it in perl data structure, to further save it in a file.

### Steps completed


#### On the Mac
The Instant client for Mac has traditionally very problematic. However, I am going to try to see if I can make it work and be able to connect to Oracle using DBD::Oracle with Perl. This is what I tried:

* [Instant Client](http://www.oracle.com/technetwork/topics/intel-macsoft-096467.html) for Mac OS X (Intel x86) Version 11.2.0.3.0 (64-bit): Instant Client Package Basic: All files required to run OCI, OCCI, and JDBC-OCI applications: 
	* Download instantclient-basic-macos.x64-11.2.0.3.0.zip (62,342,264 bytes) - This alone gave errors
	* Download  SQLPlus: Additional libraries and executable for running SQLPlus with Instant Client
Download instantclient-sqlplus-macos.x64-11.2.0.3.0.zip (888,991 bytes)
* I found similar problems described [here](http://blog.caseylucas.com/tag/oracle-sqlplus/). It solves most of the problem except one: ``./Oracle.h:37:10: fatal error: 'oci.h' file not found``





