#
# Ensembl module for Bio::EnsEMBL::Pipeline::RunnableDB::TargettedGeneWise.pm
#
# Cared for by Ewan Birney <birney@ebi.ac.uk>
#
# Copyright GRL and EBI
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::Pipeline::RunnableDB::TargettedGeneWise.pm - Targetted genewise Runnable DB

=head1 SYNOPSIS

my $tgw = new Bio::EnsEMBL::Pipeline::RunnableDB::TargettedGeneWise
    (  -dbobj => $dbobj,
       -input_id => $input_id);

  $tgw->fetch_input;
  $tgw->run();
  $tgw->output();
  $tgw->write_output(); # write to db

=head1 DESCRIPTION

This object manages the data fetching, running, output parsing, and data storing of Targetted Genewise in the Ensembl pipeline.

=head1 CONTACT

Ensembl - ensembl-dev@ebi.ac.uk

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are usually preceded with a _

=cut


# Let the code begin...


package Bio::EnsEMBL::Pipeline::RunnableDB::TargettedGeneWise;

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::Pipeline::GeneConf qw (EXON_ID_SUBSCRIPT
					 TRANSCRIPT_ID_SUBSCRIPT
					 GENE_ID_SUBSCRIPT
					 PROTEIN_ID_SUBSCRIPT
					 );
# Object preamble - inheriets from Bio::Root::RootI
use Bio::EnsEMBL::Pipeline::RunnableDB;
use Bio::EnsEMBL::Pipeline::Runnable::BlastMiniGenewise;
use Bio::EnsEMBL::Pipeline::SeqFetcher::Pfetch;
use Bio::EnsEMBL::Gene;

BEGIN { print STDERR "\n\n***I'm here!***\n"; };

@ISA = qw(Bio::EnsEMBL::Pipeline::RunnableDB);


=head2 new

    Title   :   new
    Usage   :   $self->new(-DBOBJ       => $db
                           -INPUT_ID    => $id
			   -SEQFETCHER  => $sf);
                           
    Function:   creates a Bio::EnsEMBL::Pipeline::RunnableDB::TargettedGeneWise object
    Returns :   A Bio::EnsEMBL::Pipeline::RunnableDB::TargettedGeneWise object
    Args    :   -dbobj:      A Bio::EnsEMBL::DB::Obj (required), 
                -input_id:   Contig input id (required), 
                -seqfetcher: A Bio::DB::RandomAccessI Object (required)
=cut

sub new {
    my ($class,@args) = @_;
    my $self = $class->SUPER::new(@args);

    $self->{'_fplist'} = [];	#create key to an array of feature pairs

    # dbobj, input_id, seqfetcher, and analysis objects are all set in
    # in superclass constructor (RunnableDB.pm)

    # force to static golden path
    $self->dbobj->static_golden_path_type('UCSC');

    return $self;
}


=head2 fetch_input

 Title   : fetch_input
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :

=cut

sub fetch_input{
  my ($self,@args) = @_;

  my $input_id = $self->input_id;
  my $input;

  # is it an array ref or just a string?
  if (ref($input_id) eq "ARRAY") {
    $input = $input_id;
  }
  else {
    my @tmp;
    push (@tmp,$input_id);
    $input = \@tmp;
  }

  my @fps;
  my $fpc;
  my $pid; 
  
  my $start;
  my $end;
  
  foreach my $entry(@$input) {
    # input format: chr22:10602496,10603128;Q9UGV6:1,105
    # changed to use : as field separator - for bsub
#    if( !($entry =~ /(\S+):(\d+),(\d+);(\S+):(\d+),(\d+)/) ) {
    if( !($entry =~ /(\S+):(\d+),(\d+):(\S+):(\d+),(\d+)/) ) {
      $self->throw("Not a valid input id... $entry");
    }
    
    print STDERR "input: ".$entry . "\n";

    if ($fpc) { $self->throw("mixed fpc contigs") unless $fpc = $1; }
    if ($pid) { $self->throw("mixed protein hits") unless $pid = $4; }
    $fpc = $1;
    $pid = $4;
    my $fpcstart   = $2;
    my $fpcend     = $3;
    my $fpcstrand  = 1;
    
    if ($2 > $3) { # let blast sort it out
      $fpcstart  = $3;
      $fpcend    = $2;
      $fpcstrand = -1;
    }
    
    if ($5 > $6) { 
      # there's something seriously amiss
      $self->throw("Proteins only have one strand!!!\n");
    }
    
    $start = $fpcstart unless (defined $start && $start < $fpcstart);
    $end = $fpcend unless (defined $end && $end > $fpcend);

  }
  
  push (@fps,$pid);
  
  my $sgpa = $self->dbobj->get_StaticGoldenPathAdaptor();

  print STDERR "$fpc $start $end\n";


  my ($chrname,$chrstart,$chrend) = $sgpa->convert_fpc_to_chromosome($fpc,$start-10000,$end+10000);
  print STDERR "$chrname $chrstart $chrend\n";
  my $vc = $sgpa->fetch_VirtualContig_by_chr_start_end($chrname,$chrstart,$chrend);
  
  $self->vcontig($vc);
  my $r = Bio::EnsEMBL::Pipeline::Runnable::BlastMiniGenewise->new( '-genomic'    => $vc->primary_seq,
								    '-ids'        => \@fps,
								    '-seqfetcher' => $self->seqfetcher,
                                                                    '-endbias'    => 1);
  
  
  
  $self->runnable($r);
}


=head2 run

 Title   : run
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub run{
   my ($self,@args) = @_;

   $self->runnable->run();
   $self->convert_output();

}

=head2 Bio::EnsEMBL::Pipeline::RunnableDB methods 

=head2 dbobj

    Title   :   dbobj
    Usage   :   $self->dbobj($obj);
    Function:   Gets or sets the value of dbobj
    Returns :   A Bio::EnsEMBL::Pipeline::DB::ObjI compliant object
                (which extends Bio::EnsEMBL::DB::ObjI)
    Args    :   A Bio::EnsEMBL::Pipeline::DB::ObjI compliant object

=head2 input_id

    Title   :   input_id
    Usage   :   $self->input_id($input_id);
    Function:   Gets or sets the value of input_id
    Returns :   valid input id for this analysis (if set) 
    Args    :   input id for this analysis 

=head2 output

    Title   :   output
    Usage   :   $self->output()
    Function:   
    Returns :   Array of Bio::EnsEMBL::FeaturePair
    Args    :   None

=head2 vcontig

 Title   : vcontig
 Usage   : $obj->vcontig($newval)
 Function: 
 Returns : value of vcontig
 Args    : newvalue (optional)

=head2 TargettedGeneWise implemented methods
 
=head2 write_output

    Title   :   write_output
    Usage   :   $self->write_output
    Function:   Writes output data to db
    Returns :   array of exons (with start and end)
    Args    :   none

=cut

sub write_output {
  my($self) = @_;

  #$self->throw("exiting bfore write");
  
  my $db = $self->dbobj;
  
  if( !defined $db ) {
    $self->throw("unable to make write db");
  }
  
  my $gene_obj = $db->gene_Obj;
  my @newgenes = $self->output;
  return unless ($#newgenes >= 0);
  
  # get new ids
  eval {
    
    my $genecount  = 0;
    my $transcount = 0;
    my $translcount = 0;
    my $exoncount  = 0;
    
    # get counts of each type of ID we need.
    
    foreach my $gene ( @newgenes ) {
      $genecount++;
      foreach my $trans ( $gene->each_Transcript ) {
	$transcount++;
	$translcount++;
      }
      foreach my $exon ( $gene->each_unique_Exon() ) {
	$exoncount++;
	foreach my $sf($exon->each_Supporting_Feature) {
	  print STDERR "***sub_align: " . 
                       $sf->seqname     . "\t" .
		       $sf->start       . "\t" .
		       $sf->end         . "\t" .
		       $sf->strand      . "\t" .
		       $sf->hseqname    . "\t" .
		       $sf->hstart      . "\t" .
		       $sf->hend        . "\n";
	}
	
      }
    }
    
    # get that number of ids. This locks the database
    
    my @geneids  =  $gene_obj->get_New_external_id('gene',$GENE_ID_SUBSCRIPT,$genecount);
    my @transids =  $gene_obj->get_New_external_id('transcript',$TRANSCRIPT_ID_SUBSCRIPT,$transcount);
    my @translids =  $gene_obj->get_New_external_id('translation',$PROTEIN_ID_SUBSCRIPT,$translcount);
    my @exonsid  =  $gene_obj->get_New_external_id('exon',$EXON_ID_SUBSCRIPT,$exoncount);
    
    # database locks are over.
    
    # now assign ids. gene and transcripts are easy. Exons are harder.
    # the code currently assummes that there is one Exon object per unique
    # exon id. This might not always be the case.
    
    foreach my $gene ( @newgenes ) {
      $gene->id(shift(@geneids));
      my %exonhash;
      foreach my $exon ( $gene->each_unique_Exon() ) {
	my $tempid = $exon->id;
	$exon->id(shift(@exonsid));
	$exonhash{$tempid} = $exon->id;
      }
      foreach my $trans ( $gene->each_Transcript ) {
	$trans->id(shift(@transids));
	$trans->translation->id(shift(@translids));
	$trans->translation->start_exon_id($exonhash{$trans->translation->start_exon_id});
	$trans->translation->end_exon_id($exonhash{$trans->translation->end_exon_id});
      }
      
    }
    
    # paranoia!
    if( scalar(@geneids) != 0 || scalar(@exonsid) != 0 || scalar(@transids) != 0 || scalar (@translids) != 0 ) {
      $self->throw("In id assignment, left with unassigned ids ".scalar(@geneids)." ".scalar(@transids)." ".scalar(@translids)." ".scalar(@exonsid));
    }
    
  };
  if( $@ ) {
    $self->throw("Exception in getting new ids. Exiting befor write\n\n$@" );
  }
  
  
  # this now assummes that we are building on a single VC.
  
#      $self->throw("Bailing before real write\n");
  
 GENE: foreach my $gene (@newgenes) {	
    # do a per gene eval...
    eval {
      
      $gene_obj->write($gene);
    }; 
    if( $@ ) {
      print STDERR "UNABLE TO WRITE GENE\n\n$@\n\nSkipping this gene\n";
    }
    
  }
}


sub convert_output {
    my ($self) =@_;
    my $count = 1;
    my $time  = time; chomp($time);
    my @genes = $self->make_genes($count,$time,$self->runnable);
    my @remapped = $self->remap_genes($self->runnable,@genes);

   print STDERR "gere! " . scalar(@remapped)  . "\n";

    # check translations
    foreach my $gene(@remapped){
      foreach my $trans ( $gene->each_Transcript ) {
	eval {
	  print STDERR "translation: \n";
	  my $seqio = Bio::SeqIO->new(-fh => \*STDERR);
	  print STDERR "remapped: ";
	  $seqio->write_seq($trans->translate); 
	  print STDERR "\n ";
	};
	
	if ($@) {
	  print STDERR "Couldn't translate: " . $gene->id . "[$@]\n";
	} 
      }
    }    
    
    $self->{'_output'} = \@remapped;
}

sub make_genes {

  my ($self,$count,$time,$runnable) = @_;
  my $contig = $self->vcontig;
  my $genetype;
  if ($runnable->isa("Bio::EnsEMBL::Pipeline::Runnable::BlastMiniGenewise")){
    $genetype = "TGW";
  }
  else{
    $self->throw("I don't know what to do with $runnable");
  }
  my @tmpf   = $runnable->output;
  
  my @genes;

  print "***tmpf: " . scalar(@tmpf) ."\n";
  
  foreach my $tmpf (@tmpf) {
    my $gene   = new Bio::EnsEMBL::Gene;
    my $tran   = new Bio::EnsEMBL::Transcript;
    my $transl = new Bio::EnsEMBL::Translation;
    
    $gene->type($genetype);
    $gene->id($self->input_id . ".$genetype.$count");
    $gene->created($time);
    $gene->modified($time);
    $gene->version(1);
    
    $tran->id($self->input_id . ".$genetype.$count");
    $tran->created($time);
    $tran->modified($time);
    $tran->version(1);
    
    $transl->id($self->input_id . ".$genetype.$count");
    $transl->version(1);
    
    $count++;
    
    $gene->add_Transcript($tran);
    $tran->translation($transl);
    
    my $excount = 1;
    my @exons;
    
    foreach my $exon_pred ($tmpf->sub_SeqFeature) {
      # make an exon
      my $exon = new Bio::EnsEMBL::Exon;
      
      $exon->id($self->input_id . ".$genetype.$count.$excount");
      $exon->contig_id($contig->id);
      $exon->created($time);
      $exon->modified($time);
      $exon->version(1);
      $exon->seqname($contig->id);
      $exon->start($exon_pred->start);
      $exon->end  ($exon_pred->end);
      $exon->strand($exon_pred->strand);
      
#      print STDERR "***Exon_pred " . $exon_pred->gffstring . "\n";
      
      #	$exon->phase($subf->feature1->{_phase});

      $exon->phase($exon_pred->phase);
      $exon->attach_seq($self->vcontig->primary_seq);
      # fix source tag and primary tag for $exon_pred - this isn;t the right place to do this.
      $exon_pred->source_tag('TGW');
      $exon_pred->primary_tag('TGW');
      $exon_pred->score(100);

      # sort out supporting evidence for this exon prediction
      foreach my $subf($exon_pred->sub_SeqFeature){
	$subf->feature1->source_tag($genetype);
	$subf->feature1->primary_tag('similarity');
	$subf->feature1->score(100);
	$subf->feature1->analysis($exon_pred->analysis);
	
	$subf->feature2->source_tag($genetype);
	$subf->feature2->primary_tag('similarity');
	$subf->feature2->score(100);
	$subf->feature2->analysis($exon_pred->analysis);
	
#	print STDERR "*subf " . $subf->gffstring . "\n";
	$exon->add_Supporting_Feature($subf);
      }
      
      push(@exons,$exon);
      
      $excount++;
    }
    
    if ($#exons < 0) {
      print STDERR "Odd.  No exons found\n";
    } else {
      
      push(@genes,$gene);
      
      if ($exons[0]->strand == -1) {
	@exons = sort {$b->start <=> $a->start} @exons;
      } else {
	@exons = sort {$a->start <=> $b->start} @exons;
      }
      
      foreach my $exon (@exons) {
	$tran->add_Exon($exon);
      }
      
      $transl->start_exon_id($exons[0]->id);
      $transl->end_exon_id  ($exons[$#exons]->id);
      
      if ($exons[0]->phase == 0) {
	$transl->start(1);
      } elsif ($exons[0]->phase == 1) {
	$transl->start(3);
      } elsif ($exons[0]->phase == 2) {
	$transl->start(2);
      }
      
      my $endexon = $exons[$#exons];
      
      if( $endexon->end_phase == 1 ) {
	$transl->end($endexon->length -1 );
      } elsif ( $endexon->end_phase == 2 ) {
	$transl->end($endexon->length -2 );
      } else {
	$transl->end($endexon->length);
      }
      #$transl->end  ($exons[$#exons]->end - $exons[$#exons]->start + 1);

    }
  }

  foreach my $gene(@genes){
    foreach my $trans($gene->each_Transcript){
      my $seqio = Bio::SeqIO->new(-fh => \*STDERR);
      print STDERR "grargh: ";
      $seqio->write_seq($trans->translate);
      print STDERR "\n ";
    }
  }
  return @genes;
}

sub remap_genes {
  my ($self,$runnable,@genes) = @_;
  
  my $contig = $self->vcontig;
  my $genetype;
  if ($runnable->isa("Bio::EnsEMBL::Pipeline::Runnable::BlastMiniGenewise")){
    $genetype = "TGW";
  }
  else{
    $self->throw("I don't know what to do with $runnable");
  }

  my @newf;
  my $trancount=1;

  # check translations:
  foreach my $gene(@genes){
    foreach my $trans ( $gene->each_Transcript ) {
      eval {
	print STDERR "translation: \n";
	my $seqio = Bio::SeqIO->new(-fh => \*STDERR);
	print STDERR "before remap: ";
	$seqio->write_seq($trans->translate); 
	print STDERR "\n ";
      };
      
      if ($@) {
	print STDERR "Couldn't translate: " . $gene->id . "[$@]\n";
      } 
    }
  }

  foreach my $gene (@genes) {
    eval {
      my $newgene = $contig->convert_Gene_to_raw_contig($gene);
      $newgene->type($genetype);
      foreach my $tran ($newgene->each_Transcript) {
	foreach my $exon($tran->each_Exon) {
	  print STDERR $exon->contig_id . "\tgenewise\texon\t" . $exon->start . "\t" . $exon->end . "\t100\t" . $exon->phase . "\n";
	  }
	}
      push(@newf,$newgene);
    };
    if ($@) {
      print STDERR "contig: $contig\n";
      foreach my $tran ($gene->each_Transcript) {
	foreach my $exon($tran->each_Exon) {
	  foreach my $sf($exon->each_Supporting_Feature) {
	    print STDERR "hid: " . $sf->hseqname . "\n";
	  }
	}
      }
      print STDERR "Couldn't reverse map gene " . $gene->id . " [$@]\n";
    }
  }

  return @newf;
}


=head2 runnable

 Title   : runnable
 Usage   : $obj->runnable($newval)
 Function: 
 Returns : value of runnable
 Args    : newvalue (optional)


=cut

sub runnable{
   my $obj = shift;
   if( @_ ) {
      my $value = shift;
      $obj->{'_runnable'} = $value;
    }
    return $obj->{'_runnable'};
}

1;
