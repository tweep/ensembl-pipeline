#!/usr/local/ensembl/bin/perl -w


=head1 NAME

run_EST_RunnableDB

=head1 SYNOPSIS
 
  test_RunnableDB

=head1 DESCRIPTION


=head1 OPTIONS

    -host      host name for database (gets put as host= in locator)

    -port      For RDBs, what port to connect to (port= in locator)

    -dbname    For RDBs, what name to connect to (dbname= in locator)

    -dbuser    For RDBs, what username to connect as (dbuser= in locator)

    -dbpass    For RDBs, what password to use (dbpass= in locator)

    -input_id  The input id for the RunnableDB

    -runnable  The name of the runnable module we want to run

    -analysis  The number of the analysisprocess we want to run
=cut

use strict;
use Getopt::Long;

# this script connects to the db it is going to write to
use Bio::EnsEMBL::Pipeline::Config::cDNAs_ESTs::EST_GeneBuilder_Conf qw (
						     EST_GENE_DBNAME
						     EST_GENE_DBUSER
						     EST_GENE_DBPASS
						     EST_GENE_DBHOST
						     );


use Bio::EnsEMBL::DBSQL::DBAdaptor;
#use Bio::EnsEMBL::DBLoader;
my $dbtype = 'rdb';
my $port   = undef;
my $dbname = $EST_GENE_DBNAME;
my $dbuser = $EST_GENE_DBUSER;
my $dbpass = $EST_GENE_DBPASS;
my $host   = $EST_GENE_DBHOST;


my $runnable;
my $input_id;
my $write  = 0;
my $check  = 0;
my $params;
my $pepfile;
my $acc;
my $analysis;

# can override db options on command line
&GetOptions( 
	     'input_id:s'    => \$input_id,
	     'runnable:s'    => \$runnable,
             'analysis:s'    => \$analysis,
	     'write'         => \$write,
             'check'         => \$check,
             'parameters:s'  => \$params,
             'dbname:s'      => \$dbname,
             'dbhost:s'      => \$host,
             'dbuser:s'      => \$dbuser,
             'dbpass:s'      => \$dbpass,
	     );

$| = 1;

die "No runnable entered" unless defined ($runnable);
(my $file = $runnable) =~ s/::/\//g;
require "$file.pm";

if ($check) {
   exit(0);
}

print STDERR "args: $host : $dbuser : $dbpass : $dbname\n";

my $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
    -host             => $host,
    -user             => $dbuser,
    -dbname           => $dbname,
    -pass             => $dbpass,
    );

die "No input id entered" unless defined ($input_id);


my $analysis_obj = $db->get_AnalysisAdaptor->fetch_by_logic_name($analysis);

my %hparams;
# eg -parameters param1=value1,param2=value2
if (defined $params){
  foreach my $p(split /,/, $params){
    my @sp = split /=/, $p;
    $sp[0] = '-' . $sp[0];
    $hparams{$sp[0]} =  $sp[1];
  }
}


my $runobj = "$runnable"->new(-db       => $db,
			      -input_id => $input_id,
			      -analysis => $analysis_obj,
                              %hparams,
			     );


$runobj->fetch_input;
$runobj->run;

 
my @out = $runobj->output;

if ($write) {
  $runobj->write_output;
}

