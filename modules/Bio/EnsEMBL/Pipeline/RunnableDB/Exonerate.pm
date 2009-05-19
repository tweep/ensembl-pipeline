#
#
# Cared for by EnsEMBL  <ensembl-dev@ebi.ac.uk>
#
# Copyright GRL & EBI
#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

Bio::EnsEMBL::Pipeline::RunnableDB::Exonerate

=head1 SYNOPSIS

    my $obj = Bio::EnsEMBL::Pipeline::RunnableDB::Exonerate->new(
					     -dbobj     => $db,
					     -input_id  => $id,
					     -analysis   => $analysis 		 
                                             );
    $obj->fetch_input();
    $obj->run();

    my @newfeatures = $obj->output();
    
    $obj->write_output();

=head1 DESCRIPTION

=head1 CONTACT

Describe contact details here

=head1 APPENDIX

The rest of the documentation details each of the object methods. 
Internal methods are usually preceded with a _

=cut

# Let the code begin...

package Bio::EnsEMBL::Pipeline::RunnableDB::Exonerate;

use vars qw(@ISA);
use strict;

# Object preamble - inherits from Bio::EnsEMBL::Root;
use Bio::EnsEMBL::Pipeline::RunnableDB;
use Bio::EnsEMBL::Pipeline::Runnable::Exonerate;
use Bio::EnsEMBL::Pipeline::SeqFetcher;
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::FeaturePair;
use Bio::EnsEMBL::Gene;
use Bio::SeqIO;
use Bio::EnsEMBL::Root;
use Data::Dumper;

@ISA = qw(Bio::EnsEMBL::Pipeline::RunnableDB);

sub new {
  my ($class, @args) = @_;
  my $self = $class->SUPER::new(@args);  
  
  if(!defined $self->seqfetcher) {
    # will look for pfetch in $PATH - change this once PipeConf up to date
    my $seqfetcher = new Bio::EnsEMBL::Pipeline::SeqFetcher::Pfetch; 
    $self->seqfetcher($seqfetcher);
  }  
  
  return $self; 
}

=head2 fetch_input

    Title   :   fetch_input
    Usage   :   $self->fetch_input
    Function:   Fetches input data for exonerate from the database
    Returns :   nothing
    Args    :   none

=cut

sub fetch_input {
  my( $self) = @_; 
  print STDERR "Fetching input \n";
  
  $self->throw("No input id") unless defined($self->input_id);
  my $contigid  = $self->input_id;
  my $contig    = $self->dbobj->get_Contig($contigid);
  #   my $genseq   = $contig->primary_seq;
  my $genseq = $contig->get_repeatmasked_seq();
#  my @features = $contig->get_all_SimilarityFeatures;
  $self->{_genseq} = $genseq;
  
  # set up sequence arrays
  my @ests = $self->_get_ests();
  
  # prepare runnable
  $self->throw("Can't run Exonerate without both genomic and EST sequences") 
    unless (scalar(@ests) && defined($genseq));
  
  my $executable =  $self->analysis->program_file();
  my $exonerate = new Bio::EnsEMBL::Pipeline::Runnable::Exonerate('-genomic'  => $genseq,
								  '-est'      => \@ests,
								  '-exonerate' => $executable);
  $self->runnable($exonerate);
  
}


=head2 run

    Title   :   run
    Usage   :   $self->run()
    Function:   Runs the exonerate analysis, producing Bio::EnsEMBL::Gene predictions
    Returns :   Nothing, but $self{_output} contains the predicted genes.
    Args    :   None

=cut

sub run {
  my ($self) = @_;
  
  $self->throw("Can't run - no runnable objects") unless defined($self->runnable);
  
  $self->runnable->run();

  # sort out predicted genes
  $self->_convert_output();
}

=head2 _convert_output

    Title   :   _convert_output
    Usage   :   $self->_convert_output
    Function:   converts exons found by exonerate into Bio::EnsEMBL::Gene 
                ready to be stored in the database
    Returns :   Nothing, but  $self->{_output} contains the Gene objects
    Args    :   None

=cut

# not presently doing anything with gene, intron & splice site features. Quite possibly 
# we ought to ...

sub _convert_output {
  
  my ($self) = @_;
  my $count  = 1;
  
  # make an array of genes, one per hid
  my @features = $self->runnable->output();
  my %homols   = ();
  my @genes    = ();
  
  # sort the hits into a hash keyed by hid
  foreach my $f(@features) {
    push (@{$homols{$f->hseqname()}}, $f);
  }
  
  # make one gene per hid, using the exons predicted by exonerate
  foreach my $id (keys %homols) {
    my @exonfeat;
    foreach my $ft( @{$homols{$id}}) {
      if($ft->primary_tag eq 'exon') {
	push(@exonfeat, $ft);
      }
    }

    my $gene = $self->_make_gene($count,@exonfeat);
    if(defined($gene)) {
      push (@genes, $gene);
      $count++;
    }
  }
   
  if (!defined($self->{_output})) {
    $self->{_output} = [];
  }
  
  push(@{$self->{_output}},@genes);
}

=head2 output

    Title   :   output
    Usage   :   $self->output()
    Function:   Returns the contents of $self->{_output}, which holds predicted genes.
    Returns :   Array of Bio::EnsEMBL::Gene
    Args    :   None

=cut

=head2 write_output

    Title   :   write_output
    Usage   :   $self->write_output()
    Function:   Writes contents of $self->{_output} into $self->dbobj
    Returns :   1
    Args    :   None

=cut

sub write_output {

  my($self) = @_;
  
  my @features = $self->output();
  my $db = $self->dbobj();
  my $gene_obj = $db->gene_Obj;
  
  my $EXON_ID_SUBSCRIPT       = "EXOE";
  my $TRANSCRIPT_ID_SUBSCRIPT = "EXOT";
  my $GENE_ID_SUBSCRIPT       = "EXOG";
  my $PROTEIN_ID_SUBSCRIPT    = "EXOP";
  
  my $sth = $db->prepare("lock tables gene write, genetype write, exon write, transcript write, exon_transcript write, translation write,dna read,contig read,clone read,feature read,analysis write");

  $sth->execute;
  
  eval {
    (my $gcount = $gene_obj->get_new_GeneID($GENE_ID_SUBSCRIPT))
      =~ s/$GENE_ID_SUBSCRIPT//;
    (my $tcount = $gene_obj->get_new_TranscriptID($TRANSCRIPT_ID_SUBSCRIPT))
      =~ s/$TRANSCRIPT_ID_SUBSCRIPT//;
    (my $pcount = $gene_obj->get_new_TranslationID($PROTEIN_ID_SUBSCRIPT))
      =~ s/$PROTEIN_ID_SUBSCRIPT//;
    (my $ecount = $gene_obj->get_new_ExonID($EXON_ID_SUBSCRIPT))
      =~ s/$EXON_ID_SUBSCRIPT//;
    
    
    foreach my $gene (@features) {
      $gene->id($GENE_ID_SUBSCRIPT . $gcount);
      $gcount++;
      
      # Convert all exon ids and save in a hash
      my %namehash;
      
      foreach my $ex ($gene->each_unique_Exon) {
	$namehash{$ex->id} = $EXON_ID_SUBSCRIPT.$ecount;
	$ex->id($EXON_ID_SUBSCRIPT.$ecount);
	$ecount++;
      }
      
      foreach my $tran ($gene->each_Transcript) {
	$tran->id($TRANSCRIPT_ID_SUBSCRIPT . $tcount);
	$tran->translation->id($PROTEIN_ID_SUBSCRIPT . $pcount);
	
	my $translation = $tran->translation;
	
	$tcount++;
	$pcount++;
	
	foreach my $ex ($tran->each_Exon) {
	  my @sf = $ex->each_Supporting_Feature;

	  if (defined($namehash{$translation->start_exon_id}) && $namehash{$translation->start_exon_id} ne "") {
	    $translation->start_exon_id($namehash{$translation->start_exon_id});
	  }
	  if (defined($namehash{$translation->end_exon_id}) &&$namehash{$translation->end_exon_id} ne "") {
	    $translation->end_exon_id  ($namehash{$translation->end_exon_id});
	  }
	}
	
      }
      
      $gene_obj->write($gene);
    }
  };

  if ($@) {
    $sth = $db->prepare("unlock tables");
    $sth->execute;
    
    $self->throw("Error writing gene for " . $self->input_id . " [$@]\n");
  } 
  else {
    $sth = $db->prepare("unlock tables");
    $sth->execute;
  }
  return 1;
}


sub _make_gene {
  my ($self, $count, @exonfeat) = @_;
  my $contig   = $self->dbobj->get_Contig($self->input_id);
  my $excount = 1;
  my @exons = ();
  my $time   = time; 
  chomp($time); 

  my $gene   = new Bio::EnsEMBL::Gene;
  $gene->type('exonerate');
  $gene->id($self->input_id . ".exo.$count");
  $gene->created($time);
  $gene->modified($time);
  $gene->version(1);
  
  # make a transcript
  my $tran   = new Bio::EnsEMBL::Transcript;
  $tran->id($self->input_id . ".exo.$count");
  $tran->created($time);
  $tran->modified($time);
  $tran->version(1);
  
  my $transl = new Bio::EnsEMBL::Translation;
  $transl->id($self->input_id . ".exo.$count");
  $transl->version(1);
  
  # add transcript to gene
  $gene->add_Transcript($tran);
  $tran->translation($transl);
  
  foreach my $fp(@exonfeat) {
    # make an exon
    
    my $exon = new Bio::EnsEMBL::Exon;
    $exon->id($self->input_id . ".exo.$count.$excount");
    $exon->contig_id($contig->id);
    $exon->created($time);
    $exon->modified($time);
    $exon->version(1);
    
    $exon->start($fp->start);
    $exon->end  ($fp->end);
    
    if($fp->strand == $fp->hstrand) {
      $fp->strand(1);
      $fp->hstrand(1);
    }
    else {
      $fp->strand(-1);
      $fp->hstrand(-1);
    }
    
    $exon->strand($fp->strand);
    $exon->phase(0);
    $exon->attach_seq($contig->primary_seq);
    $exon->add_Supporting_Feature($fp);
    
    push(@exons,$exon);
    $excount++;
  }

  if ($#exons < 0) {
    print STDERR "Odd.  No exons found\n";
    return;
  } 
  else {
    # assemble exons
    if ($exons[0]->strand == -1) {
      @exons = sort {$b->start <=> $a->start} @exons;
    } 
    else {
      @exons = sort {$a->start <=> $b->start} @exons;
    }
    
    foreach my $exon(@exons){
      $tran->add_Exon($exon);
    }
    
    $transl->start_exon_id($exons[0]->id);
    $transl->end_exon_id  ($exons[$#exons]->id);
    
    if ($exons[0]->strand == 1) {
      $transl->start($exons[0]->start);
      $transl->end  ($exons[$#exons]->end);
    } else {
      $transl->start($exons[0]->end);
      $transl->end  ($exons[$#exons]->start);
    }
    return $gene;
  }
}

# routines for sequence fetching; much of this is in common with eg Vert_Est2Genome so should be
# inherited from a common parent ...

=head2 _get_ests

    Title   :   _get_ests
    Usage   :   $self->_get_ests(@features)
    Function:   Screens FeaturePairs in @features for vert EST blast hits, retrieves 
                and validates sequences and makes them into an array of Bio::Seq
    Returns :   Array of Bio::EnsEMBL::Seq
    Args    :   None

=cut

sub _get_ests {
  my ($self) = @_;
  my $contig = $self->dbobj->get_Contig($self->input_id);
  my @mrnafeatures = ();
  my %idhash = ();
  
  foreach my $f ($contig->get_all_SimilarityFeatures()) {
    if (defined($f->analysis)      && defined($f->score) && 
	defined($f->analysis->db)  && $f->analysis->db eq "vert") {
      
      if (!defined($idhash{$f->hseqname})) { 
	push(@mrnafeatures,$f);
	$idhash{$f->hseqname} =1;
      } 
      else {
	# feature pair on this sequence already seen
	print STDERR ("Ignoring feature " . $f->hseqname . "\n");
      }
    }
  }
  
  unless (@mrnafeatures)
    {
      print STDERR ("No EST hits\n");
      return;
    }
  my @seq = $self->_get_Sequences(@mrnafeatures);

  return @seq;

}

=head2 _get_Sequences

    Title   :   _get_Sequences
    Usage   :   $self->_get_Sequences(@features)
    Function:   Gets a Bio::Seq for each of the hit sequences in @features
    Returns :   Array of Bio::Seq
    Args    :   Array of Bio::EnsEMBL::FeaturePair

=cut
  
sub _get_Sequences {
  my ($self,@pairs) = @_;
  
  my @seq;
  
  foreach my $pair (@pairs) {
    my $id = $pair->hseqname;
    if ($pair->analysis->db eq "vert") {
      
      eval {
	my $seq = $self->_get_Sequence($id);
	push(@seq,$seq);
      };
      if ($@) {
	$self->warn("Couldn't fetch sequence for $id [$@]");
      } 
    }
  }
  return @seq;
}

=head2 _parse_Header

    Title   : _parse_Header
    Usage   : my $newid = $self->_parse_Header($id);
    Function: Parses different sequence headers
    Returns : string
    Args    : ID string

=cut

sub _parse_Header {
    my ($self,$id) = @_;

    if (!defined($id)) {
	$self->throw("No id input to _parse_Header");
    }

    my $newid = $id;

    if ($id =~ /^(.*)\|(.*)\|(.*)/) {
	$newid = $2;
	$newid =~ s/(.*)\..*/$1/;
	
    } elsif ($id =~ /^..\:(.*)/) {
	$newid = $1;
    }
    $newid =~ s/ //g;
    return $newid;
}
    
=head2 _get_Sequence

  Title   : _get_Sequence
  Usage   : my $seq = _get_Sequence($id);
  Function: Fetches sequence that has ID $id. Tries a variety of methods for 
            fetching sequence. If sequence found, it is cached.
  Returns : Bio::PrimarySeq
  Args    : ID string 

=cut

sub _get_Sequence {
  my ($self,$id) = @_;

  if (!defined($id)) {
    $self->warn("No id input to _get_Sequence");
  } 

  if (defined($self->{_seq_cache}{$id})) {
    return $self->{_seq_cache}{$id};
  } 
  
  my $seq;
  eval {
    $seq = $self->seqfetcher->get_Seq_by_acc($id);
  };
  
  if($@) {
    $self->throw("Problem fetching sequence for id [$id]\n");
  }  
  
  if(!defined $seq) {
    $self->throw("Couldn't find sequence for [$id]");
  }
  
  print (STDERR "Found sequence for $id [" . $seq->length() . "]\n");
  $self->{_seq_cache}{$id} = $seq;
  
  return $seq;
  
}

=head2 _validate_sequence

    Title   :   _validate_sequence
    Usage   :   $self->_validate_sequence(@seq)
    Function:   Takes an array of Seq or PrimarySeq objects and 
                returns valid ones, removing invalid characters 
                for nucleic acid sequences and rejecting sequences 
                that are not nucleic acid
    Returns :   Array of Bio::Seq
    Args    :   Array of Bio::Seq

=cut

sub _validate_sequence {
  my ($self, @seq) = @_;
  my @validated;
  foreach my $seq (@seq)
    {
      print STDERR ("$seq is not a Bio::PrimarySeq or Bio::Seq\n") 
	unless ($seq->isa("Bio::PrimarySeq") ||
		$seq->isa("Bio::Seq"));
      my $sequence = $seq->seq;
      if ($sequence !~ /[^acgtn]/i)
        {
	  push (@validated, $seq);
        }
      else 
        {
	  $_ = $sequence;
	  my $len = length ($_);
	  my $invalidCharCount = tr/mrwsykvhdbxMRWSYKVHDBX/n/;
	  #extract invalid characters
	  $sequence =~ s/[ACGTN]//ig;
	  if ($invalidCharCount / $len > 0.05)
            {
	      $self->warn("Ignoring ".$seq->display_id()
			  ." contains more than 5% ($invalidCharCount) "
			  ."odd nucleotide codes ($sequence)\n Type returns "
			  .$seq->moltype().")\n");
            }
	  else
            {
	      $self->warn ("Cleaned up ".$seq->display_id
			   ." for blast : $invalidCharCount invalid chars ($sequence)\n");
	      $seq->seq($_);
	      push (@validated, $seq);
            }
        }
    } 
  return @validated;  
}

1;