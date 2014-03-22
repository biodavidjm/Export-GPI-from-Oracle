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

##### Installation of DBD::Oracle 

I need to first install the 64 bits instant client for Mac, which traditionally has been very problematic. After a lot of difficulties, I made it work. And these are the steps adapted from [here](http://blog.caseylucas.com/tag/oracle-sqlplus/) (the sh script is the essential part) and specially [here](http://blog.g14n.info/2013/07/how-to-install-dbdoracle.html). Since I combined both, I am going to rewrite the steps:

Folder: ``$HOME:/opt/Oracle/packages/`` where I [downloaded](http://www.oracle.com/technetwork/topics/intel-macsoft-096467.html):

```
ls opt/Oracle/packages/
instantclient-basic-macos.x64-11.2.0.3.0.zip   
instantclient-sdk-macos.x64-11.2.0.3.0.zip     
instantclient-sqlplus-macos.x64-11.2.0.3.0.zip
```

Next unzip them:

```
$ cd $HOME/opt/Oracle
$ unzip packages/basic-10.2.0.5.0-linux-x64.zip
$ unzip packages/sdk-10.2.0.5.0-linux-x64.zip
$ unzip packages/sqlplus-10.2.0.5.0-linux-x64.zip
```

Then, go to $HOME and create a ``.oracle_profile`` file with the environment variables 

```
more .oracle_profile
export ORACLE_BASE=$HOME/opt/Oracle
export ORACLE_HOME=$ORACLE_BASE/instantclient_11_2
export PATH=$ORACLE_HOME:$PATH
export TNS_ADMIN=$HOME/etc
export NLS_LANG=AMERICAN_AMERICA.WE8ISO8859P15
export LD_LIBRARY_PATH=$ORACLE_HOME
export DYLD_LIBRARY_PATH=$ORACLE_HOME
```

...which has to be source from ``.bash_profile``. At this point, the test ``sqlplus /nolog`` should give errors. To solve the problem, I cd to the folder ``/opt/Oracle/instantclient_11_2`` and run the script ``changeOracleLibs.sh`` (it should be available in this github project, folder ``/bin``).

After running the script, testing sqlplus should work:

```
$ sqlplus /nolog

SQLPlus: Release 11.2.0.3.0 Production on Fri Mar 21 13:49:34 2014

Copyright (c) 1982, 2012, Oracle.  All rights reserved.

SQL>

```

Finally, install the DBI module ``cpanm PERL::DBI``, which was installed WITH SUCCESS!!

The testing script ``connect2oracle.pl`` was tested to connect to the Oracle database at the VM on nubic with SUCCESS!

The preliminary conclusion is that now it is possible to develop perl DBI scripts from a Mac OS X (64 bits).




