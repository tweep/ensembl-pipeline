#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

Bio::EnsEMBL::Pipeline::Runnable::BlastMiniGenewise

=head1 SYNOPSIS

    my $obj = Bio::EnsEMBL::Pipeline::Runnable::BlastMiniGenewise->new
    ('-genomic'        => $genseq,
     '-features'       => $features,
     '-protein'        => $protein,
     '-seqfetcher'     => $seqfetcher,
     '-check_repeated' => 1);

    
    $obj->run

    my @newfeatures = $obj->output;

(where $protein and $genseq are Bio::Seq objects, 
 $features are X objects and $seqfetcher is a 
 SeqFetcher object.)


=head1 DESCRIPTION

=head1 CONTACT

Describe contact details here

=head1 APPENDIX

The rest of the documentation details each of the object methods. 
Internal methods are usually preceded with a _

=cut

# Let the code begin...

package Bio::EnsEMBL::Pipeline::Runnable::BlastMiniGenewise;

use vars qw(@ISA);
use strict;

use Bio::EnsEMBL::Pipeline::Runnable::BlastMiniBuilder;
use Bio::EnsEMBL::Pipeline::Runnable::MultiMiniGenewise;
use Bio::EnsEMBL::Pipeline::Runnable::Blast;
use Bio::EnsEMBL::Pipeline::Runnable::BlastDB;
use Bio::EnsEMBL::Pipeline::RunnableI;
use Bio::PrimarySeqI;
use Bio::SeqIO;
use Bio::DB::RandomAccessI;

use Bio::EnsEMBL::Pipeline::Config::GeneBuild::General qw (
							   GB_INPUTID_REGEX
							   GB_BMG_FILTER
							   GB_BMG_SCORE_CUTOFF
							  );
use Bio::EnsEMBL::Pipeline::Config::Blast;

@ISA = qw(Bio::EnsEMBL::Pipeline::RunnableI Bio::EnsEMBL::Pipeline::Runnable::BlastMiniBuilder);

sub new {
  my ($class,@args) = @_;

  my $self = $class->SUPER::new(@args);
  
  my( $genomic, $ids, $seqfetcher, $endbias, $gap, $extension, $matrix, $terminal_padding, $exon_padding, $minimum_intron, $check_repeated) = 
    $self->_rearrange([qw(GENOMIC
			  IDS
			  SEQFETCHER
			  ENDBIAS
			  GAP
			  EXTENSION
			  MATRIX
			  TERMINAL_PADDING
			  EXON_PADDING
			  MINIMUM_INTRON
			  CHECK_REPEATED)],
		      @args);
  
  $self->throw("No genomic sequence input")            unless defined($genomic);
  $self->throw("No seqfetcher provided")               unless defined($seqfetcher);
  $self->throw("No ids arrary ref provided")           unless defined($ids);

  $self->throw("[$genomic] is not a Bio::PrimarySeqI") 
    unless $genomic->isa("Bio::PrimarySeqI");
	
  $self->ids($ids)                                     if defined($ids);
  $self->genomic_sequence($genomic)                    if defined($genomic);
  $self->endbias($endbias)                             if defined($endbias);
  $self->gap($gap)                                 if defined($gap);
  $self->extension($extension)                           if defined($extension);
  $self->matrix($matrix)                              if defined($matrix);
  $self->terminal_padding($terminal_padding)           if defined($terminal_padding);
  $self->exon_padding($exon_padding)                   if defined($exon_padding);
  $self->minimum_intron($minimum_intron)               if defined($minimum_intron);
  $self->seqfetcher($seqfetcher)                       if defined($seqfetcher);

  # Repeated genes are checked by default.
  if (defined $check_repeated){
    $self->check_repeated($check_repeated);
  }else {
    $self->check_repeated(1);
  }

  return $self;
}

sub ids {
  my ($self,$ids) = @_;

	if (!defined($self->{_idlist})) {
		$self->{_idlist} = [];
	}
	if (defined($ids)) {
    if (ref($ids) eq "ARRAY") {
      push(@{$self->{'_idlist'}},@$ids);
    } else {
      $self->throw("[$ids] is not an array ref.");
    }
  }
	return @{$self->{_idlist}};
}

=head2 genomic_sequence

    Title   :   genomic_sequence
    Usage   :   $self->genomic_sequence($seq)
    Function:   Get/set method for genomic sequence
    Returns :   Bio::Seq object
    Args    :   Bio::Seq object

=cut

sub genomic_sequence {
    my( $self, $value ) = @_;    
    if ($value) {
        #need to check if passed sequence is Bio::Seq object
        $value->isa("Bio::PrimarySeqI") || $self->throw("Input isn't a Bio::PrimarySeqI");
        $self->{'_genomic_sequence'} = $value;
    }
    return $self->{'_genomic_sequence'};
}

=head2 endbias

    Title   :   endbias
    Usage   :   $self->endbias($endbias)
    Function:   Get/set method for genewise endbias
    Returns :   
    Args    :   

=cut

sub endbias {
    my ($self,$arg) = @_;

    if (defined($arg)) {
        $self->{'_endbias'} = $arg;
    }

    if (!defined($self->{'_endbias'})) {
      $self->{'_endbias'} = 0;
    }    

    return $self->{'_endbias'};
}

=head2 gap

    Title   :   gap
    Usage   :   $self->gap($gap)
    Function:   Get/set method for genewise gap
    Returns :   
    Args    :   

=cut

sub gap {
    my ($self,$arg) = @_;

    if (defined($arg)) {
        $self->{'_gap'} = $arg;
    }

    if (!defined($self->{'_gap'})) {
      $self->{'_gap'} = 0;
    }    

    return $self->{'_gap'};
}

=head2 extension

    Title   :   extension
    Usage   :   $self->extension($extension)
    Function:   Get/set method for genewise extension
    Returns :   
    Args    :   

=cut

sub extension {
    my ($self,$arg) = @_;

    if (defined($arg)) {
        $self->{'_extension'} = $arg;
    }

    if (!defined($self->{'_extension'})) {
      $self->{'_extension'} = 0;
    }    

    return $self->{'_extension'};
}

=head2 matrix

    Title   :   matrix
    Usage   :   $self->matrix($matrix)
    Function:   Get/set method for genewise matrix
    Returns :   
    Args    :   

=cut

sub matrix {
    my ($self,$arg) = @_;

    if (defined($arg)) {
        $self->{'_matrix'} = $arg;
    }

    if (!defined($self->{'_matrix'})) {
      $self->{'_matrix'} = 0;
    }    

    return $self->{'_matrix'};
}


=head2 terminal_padding

    Title   :   terminal_padding
    Usage   :   $self->terminal_padding($terminal_padding)
    Function:   Get/set method for padding level for miniseqs
    Returns :   
    Args    :   

=cut

sub terminal_padding {
    my ($self,$arg) = @_;

    if (defined($arg)) {
        $self->{'_terminal_padding'} = $arg;
    }

    if (!defined($self->{'_terminal_padding'})) {
      $self->{'_terminal_padding'} = 0;
    }    

    return $self->{'_terminal_padding'};
}


=head2 exon_padding

    Title   :   exon_padding
    Usage   :   $self->exon_padding($exon_padding)
    Function:   Get/set method for padding level for miniseqs
    Returns :   
    Args    :   

=cut

sub exon_padding {
    my ($self,$arg) = @_;

    if (defined($arg)) {
        $self->{'_exon_padding'} = $arg;
    }

    if (!defined($self->{'_exon_padding'})) {
      $self->{'_exon_padding'} = 0;
    }    

    return $self->{'_exon_padding'};
}

=head2 minimum_intron

    Title   :   minimum_intron
    Usage   :   $self->minimum_intron($minimum_intron)
    Function:   Get/set method for padding level for miniseqs
    Returns :   
    Args    :   

=cut

sub minimum_intron {
    my ($self,$arg) = @_;

    if (defined($arg)) {
        $self->{'_minimum_intron'} = $arg;
    }

    if (!defined($self->{'_minimum_intron'})) {
      $self->{'_minimum_intron'} = 0;
    }    

    return $self->{'_minimum_intron'};
}


=head2 seqfetcher

    Title   :   seqfetcher
    Usage   :   $self->seqfetcher($seqfetcher)
    Function:   Get/set method for SeqFetcher
    Returns :   Bio::EnsEMBL::Pipeline::SeqFetcher object
    Args    :   Bio::EnsEMBL::Pipeline::SeqFetcher object

=cut

sub seqfetcher {
  my( $self, $value ) = @_;    
  if ($value) {
    $self->{'_seqfetcher'} = $value;
  }
  return $self->{'_seqfetcher'};
}


=head2 check_repeated

    Title   :   check_repeated
    Usage   :   $self->check_repeated(1)
    Function:   Get/Set method for check_repeated
    Returns :   0 (False) or 1 (True)
    Args    :   0 (False) or 1 (True)

=cut

sub check_repeated {
  my( $self, $value ) = @_;    

  if ($value) {
    $self->{'_check_repeated'} = $value;
  }

  return $self->{'_check_repeated'};
}


=head2 run

  Title   : run
  Usage   : $self->run()
  Function: 
  Returns : none
  Args    : 

=cut

sub run {
  my ($self) = @_;
  
  my @blast_features = $self->run_blast;
  
  unless (@blast_features) {
    print STDERR "Contig has no associated features.  Finishing run.\n";
    return;
  }

  my $mg_runnables;
  
  my @feature_pairs;
  foreach my $f (@blast_features){
    $f->invert($self->genomic_sequence);
  }

  @blast_features = sort{$a->start <=> $b->start  
			   || $a->end <=> $b->end} @blast_features; 

  if ($self->check_repeated > 0){ 
    $mg_runnables = $self->build_runnables(@blast_features);
  } else {
    my $runnable = $self->make_object($self->genomic_sequence, \@blast_features);
    push (@$mg_runnables, $runnable); 
  }

  foreach my $mg (@$mg_runnables){
    $mg->run;
    my @f = $mg->output;
    #print STDERR "There were " . scalar @f . " $f[0]  " 
    #  . " features after the MiniGenewise run.\n";
    push(@{$self->{'_output'}},@f);
  }

  return 1;

}

sub run_blast {
  my ($self) = @_;
  
  my @seq         = $self->get_Sequences;
  if (@seq != $self->ids) {
    $self->warn("Managed to get only " . scalar(@seq) . "  of ".
                scalar($self->ids) ."for BLAST run; check indices\n");
  }
  my @valid_seq   = $self->validate_sequence(@seq);
  #print STDERR "there are ".@valid_seq." valid sequences\n";

  my $blastdb     = new Bio::EnsEMBL::Pipeline::Runnable::BlastDB
    (
     -sequences => [$self->genomic_sequence],
     -type      => 'DNA');
  #print STDERR "\n";
  $blastdb->run;

  #print STDERR "\n";
  my @blast_features;
  my $dbname = $blastdb->dbfile;
  if($dbname =~/\/tmp\//){
    $dbname =~ s/\/tmp\///g;
  } 

  my @sorted_seqs = sort {$a->id cmp $b->id} @valid_seq;
  foreach my $seq (@sorted_seqs) {
    # First sort out the header parsing. Blergh! cb25.NA_057.31208-61441 Slice, no descrtipion 
     my $regex;
     #print STDERR "ID ".$self->genomic_sequence->name."\n";
     if($self->genomic_sequence->name =~ /^\S+\:\S*\:(\S+)\:\S*:\S*\:\S*/){
       $regex = '^\S+\:\S*\:(\S+)\:\S*:\S*\:\S*';
     }elsif ($self->genomic_sequence->name =~ /^(.*)\|(.*)\|(.*)/) {
       $regex = '^.*\|(.*)\|.*';
     } elsif ($self->genomic_sequence->name =~ /^..\:(.*)/) {
       $regex = '^..\:(.*)';
     }else {
       $regex = '^(\w+)';
     }
    
     
     my $run = new Bio::EnsEMBL::Pipeline::Runnable::Blast
       (
        -query    => $seq,
        -program  => 'wutblastn',
        -database => $blastdb->dbfile,
        -filter   => 1,
	-coverage => 100,
       );
#     print STDERR "Adding ".$dbname." ".$regex."\n";
     $run->add_regex($dbname, $regex);
     $run->run;
     
     push(@blast_features,$run->output);
   }
  
  $blastdb->remove_index_files;
  unlink $blastdb->dbfile;
  if($GB_BMG_FILTER){
    #print STDERR "Filtering blast results\n";
    #this code will through out any sets of features where
    #none of the blast scores are higher than score set in config 
    #on the grounds its unlikely in that case that it will produce 
    #a good gene if a gene at all
    my @fs;
    my %feature_hash;
    while(my $f = shift(@blast_features)){
      if(!$feature_hash{$f->seqname}){
	$feature_hash{$f->seqname} = [];
	push(@{$feature_hash{$f->seqname}}, $f);
      }else{
	push(@{$feature_hash{$f->seqname}}, $f);
      }
    }
  HIT: foreach my $hid(keys(%feature_hash)){
      my @hit_features = @{$feature_hash{$hid}};
      foreach my $f (@hit_features){
        if($f->score > $GB_BMG_SCORE_CUTOFF){
          push(@fs, @hit_features);
          next HIT;
        }
      }
    }
    foreach my $f(@fs){
      #print STDERR "run_blast ".$f->seqname." ".$f->hseqname."\n";
    }
    return @fs;
  }else{
    foreach my $f(@blast_features){
      #print STDERR "run_blast ".$f->seqname." ".$f->hseqname."\n";
    }
    return @blast_features;
  }
  
}

#=head2 make_mmgw
=head2 make_object

  Args [1]   : $miniseq - a Bio::Seq object representing the
               target sequence for the genewise run.
  Args [2]   : $features - reference to a list of 
               FeaturePairs generated by a blast run.
  Example    : $self->make_object($miniseq, $features);
  Description: Takes a genomic sequence and builds a
               MultiMiniGenewise runnable object using the 
               list of FeaturePairs.
  Returntype : A list of 
               Bio::EnsEMBL::Pipeline::Runnable::MultiMiniGenewise
  Exceptions : none
  Caller     : $self->build_runnables

=cut


#sub make_mmgw {
sub make_object {
  my ($self, $miniseq, $features) = @_;

#  # Before we pass our blast generated features to 
#  # MultiMiniGenewise we must first convert them from 
#  # PepDnaAlignFeatures to FeaturePairs.
#
#  my @newf;
#  foreach my $f (@$features){
#    my $newf = new Bio::EnsEMBL::FeaturePair(-feature1 => $f->feature2,
#					     -feature2 => $f->feature1);
#    push(@newf,$newf);
#  }

  # Create a MultiMiniGenewise object with the features weve
  # just converted.
  my $mg      = new Bio::EnsEMBL::Pipeline::Runnable::MultiMiniGenewise(
                                                                        '-genomic'    => $miniseq,
									'-features'   => $features,
									'-seqfetcher' => $self->seqfetcher,
									'-terminal_padding' => $self->terminal_padding,
									'-exon_padding'     => $self->exon_padding,
									'-minimum_intron'   => $self->minimum_intron,
									'-endbias'    => $self->endbias,
									'-gap'        => $self->gap,
									'-extension'  => $self->extension,
									'-matrix'     => $self->matrix,
				      );

  return $mg;
}

sub get_Sequences {
    my ($self) = @_;

    my @seq;

    foreach my $id ($self->ids) {
      #print STDERR "Fetching ".$id." sequence\n";
        my $seq = $self->get_Sequence($id);

        if ($seq && $seq->length > 0) {
            push(@seq,$seq);
        } else {
            print STDERR "Invalid sequence for $id - skipping\n";
        }
    }

    return @seq;

}

sub validate_sequence {
    my ($self,@seq) = @_;
    my @validated;

    foreach my $seq (@seq) {

        my $sequence = $seq->seq;

        if ($sequence !~ /[^acgtn]/i) {
            push (@validated, $seq);
        } else {
            $_ = $sequence;
            my $len = length ($_);
            my $invalidCharCount = tr/bB/xX/;

            if ($invalidCharCount / $len > 0.05) {
                $self->warn("Ignoring ".$seq->display_id()
                    ." contains more than 5% ($invalidCharCount) "
                    ."odd nucleotide codes ($sequence)\n Type returns "
                    .$seq->moltype().")\n");
            } else {
                $seq->seq($_);
                push (@validated, $seq);
            }
        }
    } 
    return @validated;  
}

=head2 get_Sequence

  Title   : get_Sequence
  Usage   : my $seq = get_Sequence($id)
  Function: Fetches sequences with id $id
  Returns : Bio::PrimarySeq
  Args    : none

=cut
    
sub get_Sequence {
    my ($self,$id) = @_;
    my $seqfetcher = $self->seqfetcher;
    my $seq;
    my $name;
    if($seqfetcher->can('db')){
    my @dbs = $seqfetcher->db;
    $name = $dbs[0];
    }
    my ($p, $f, $l) = caller;
    if (!defined($id)) {
      $self->warn("No id input to get_Sequence");
    }  
    
    eval {
      $seq = $seqfetcher->get_Seq_by_acc($id);
    };

    if($@) {
      $self->warn("Problem fetching sequence for id [$id] with $seqfetcher $name  $@\n");
      return undef;
    }
    
    if(!defined($seq)){
      $self->warn("Could not find sequence for [$id] with $seqfetcher $name called by $f:$l");
    }

    return $seq;
	}

1;
