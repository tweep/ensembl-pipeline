#!/usr/local/bin/perl

#
#
# Cared for by Michele Clamp  <michele@sanger.ac.uk>
#
# Copyright Michele Clamp
#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

Bio::EnsEMBL::Pipeline::Runnable::MiniGenewise

=head1 SYNOPSIS

    my $obj = Bio::EnsEMBL::Pipeline::Runnable::MiniGenewise->new(-genomic  => $genseq,
								  -features => $features)

    $obj->run

    my @newfeatures = $obj->output;


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

# Object preamble - inherits from Bio::Root::Object;
use Bio::EnsEMBL::Pipeline::Runnable::MiniGenewise;

#compile time check for executable
use Bio::EnsEMBL::Analysis::Programs qw(pfetch efetch); 
use Bio::EnsEMBL::Analysis::MSPcrunch;
use Bio::PrimarySeqI;
use Bio::Tools::Blast;
use Bio::SeqIO;

use Data::Dumper;

@ISA = qw(Bio::EnsEMBL::Pipeline::RunnableI Bio::Root::Object );

sub _initialize {
    my ($self,@args) = @_;
    my $make = $self->SUPER::_initialize(@_);    
           
    $self->{'_idlist'} = []; #create key to an array of feature pairs
    
    my( $genomic, $ids) = $self->_rearrange(['GENOMIC',
					     'IDS',
					     ], @args);
       
    $self->throw("No genomic sequence input")           unless defined($genomic);
    $self->throw("[$genomic] is not a Bio::PrimarySeqI") unless $genomic->isa("Bio::PrimarySeqI");

    $self->genomic_sequence($genomic) if defined($genomic);

    if (defined($ids)) {
	if (ref($ids) eq "ARRAY") {
	    push(@{$self->{_idlist}},@$ids);
	} else {
	    $self->throw("[$ids] is not an array ref.");
	}
    }
    
    return $self; # success - we hope!
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


=head2 get_all_FeatureIds

  Title   : get_all_FeatureIds
  Usage   : my @ids = get_all_FeatureIds
  Function: Returns an array of all distinct feature hids 
  Returns : @string
  Args    : none

=cut

sub get_Ids {
    my ($self) = @_;

    if (!defined($self->{_idlist})) {
	$self->{_idlist} = [];
    }
    return @{$self->{_idlist}};
}


=head2 parse_Header

  Title   : parse_Header
  Usage   : my $newid = $self->parse_Header($id);
  Function: Parses different sequence headers
  Returns : string
  Args    : none

=cut

sub parse_Header {
    my ($self,$id) = @_;

    if (!defined($id)) {
	$self->throw("No id input to parse_Header");
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


=head2 run

  Title   : run
  Usage   : $self->run()
  Function: Runs est2genome on each distinct feature id
  Returns : none
  Args    : 

=cut

sub run {
    my ($self) = @_;

    my @ids = $self->get_Ids;

    my @features = $self->blast_ids(@ids);
    my @newfeatures;

    my %scorehash;
    my %idhash;

    unless (@features) {
        print STDERR "Contig has no associated features\n";
        return;
    }

    foreach my $f (@features) {

	if (!defined($idhash{$f->hseqname})) { 
	    push(@newfeatures,$f);
	    $idhash{$f->hseqname} =1;
	}
	if ($f->score > $scorehash{$f->hseqname})  {
	    $scorehash{$f->hseqname} = $f->score;
	}
    }

    my @forder = sort { $scorehash{$b} <=> $scorehash{$a}} keys %scorehash;

    my $mg = new Bio::EnsEMBL::Pipeline::Runnable::MiniGenewise(-genomic  => $self->genomic_sequence,
								-features => \@features,
								-forder   => \@forder);

    $mg->minirun;

    my @f = $mg->output;

    foreach my $f (@f) {
	print(STDERR "PogAligned output is " . $f->start . "\t" . $f->end . "\t" . $f->score . "\n");
	print $f;
    }

    push(@{$self->{_output}},@f);

}

sub blast_ids {
    my ($self,@ids) = @_;

    my @seq         = $self->get_Sequences(@ids);
    my @valid_seq   = $self->validate_sequence(@seq);
    
    my @blastseqs   = ($self->genomic_sequence);
    
    my $blastdb     = $self->make_blast_db(@blastseqs);
    my @newfeatures;

    foreach my $seq (@valid_seq) {
	my @tmp = $self->run_blast($seq,$blastdb);
	push(@newfeatures,@tmp);
    }

    unlink $blastdb;
    unlink $blastdb.".csq";
    unlink $blastdb.".nhd";
    unlink $blastdb.".ntb";

    return @newfeatures;
}

sub run_blast {

    my ($self,$seq,$db) = @_;

    my $blastout = $self->get_tmp_file("/tmp/","blast","swir.msptmp");
    my $seqfile  = $self->get_tmp_file("/tmp/","seq","fa");

    my $seqio = Bio::SeqIO->new(-format => 'Fasta',
				-file   => ">$seqfile");

    $seqio->write_seq($seq);
    close($seqio->_filehandle);

    my $command  = "tblast2n $db $seqfile B=500 -hspmax 1000  2> /dev/null |MSPcrunch -d - >  $blastout";

    print (STDERR "Running command $command\n");
    my $status = system($command );

    print("Exit status of blast is $status\n");
    open (BLAST, "<$blastout") 
        or $self->throw ("Unable to open Blast output $blastout: $!");    
    if (<BLAST> =~ /BLAST ERROR: FATAL:  Nothing in the database to search!?/)
    {
        print "nothing found\n";
        return;
    }

    my @pairs;

    eval {
	my $msp = new Bio::EnsEMBL::Analysis::MSPcrunch(-file => $blastout,
							-type => 'PEP-DNA',
							-source_tag => 'genewise',
							-contig_id => $self->genomic_sequence->id,
							);


	@pairs = $msp->each_Homol;
	
	foreach my $pair (@pairs) {
	    my $strand1 = $pair->feature1->strand;
	    my $strand2 = $pair->feature2->strand;
	    
	    $pair->invert;
	    $pair->feature2->strand($strand2);
	    $pair->feature1->strand($strand1);
	    $pair->hseqname($seq->id);
	    $self->print_FeaturePair($pair);
	}
    };
    if ($@) {
	$self->warn("Error processing msp file for " . $seq->id . " [$@]\n");
    }

    unlink $blastout;
    unlink $seqfile;

    return @pairs;
}

sub print_FeaturePair {
    my ($self,$pair) = @_;

    print STDERR $pair->seqname . "\t" . $pair->start . "\t" . $pair->end . "\t" . $pair->score . "\t" .
	$pair->strand . "\t" . $pair->hseqname . "\t" . $pair->hstart . "\t" . $pair->hend . "\t" . $pair->hstrand . "\n";
}

sub make_blast_db {
    my ($self,@seq) = @_;

    my $blastfile = $self->get_tmp_file('/tmp/','blast','fa');
    my $seqio = Bio::SeqIO->new('-format' => 'Fasta',
			       -file   => ">$blastfile");
    print STDERR "Blast db file is $blastfile\n";
    foreach my $seq (@seq) {
	print STDERR "Writing seq " . $seq->id ."\n";
	$seqio->write_seq($seq);
    }

    close($seqio->_filehandle);

    my $status = system("pressdb $blastfile");
    print (STDERR "Status from pressdb $status\n");

    return $blastfile;
}

sub get_tmp_file {
    my ($self,$dir,$stub,$ext) = @_;

    
    if ($dir !~ /\/$/) {
	$dir = $dir . "/";
    }

#    $self->check_disk_space($dir);

    my $num = int(rand(10000));
    my $file = $dir . $stub . "." . $num . "." . $ext;

    while (-e $file) {
	$num = int(rand(10000));
	$file = $stub . "." . $num . "." . $ext;
    }			
    
    return $file;
}
    
sub get_Sequences {
    my ($self,@ids) = @_;

    my @seq;

    foreach my $id (@ids) {
	my $seq = $self->get_Sequence($id);

	if (defined($seq) && $seq->length > 0) {
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
    foreach my $seq (@seq)
    {
        print STDERR ("mrna feature $seq is not a Bio::PrimarySeq or Bio::Seq\n") 
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
            my $invalidCharCount = tr/bB/xX/;

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
                   ." for blast : $invalidCharCount invalid chars \n");
                $seq->seq($_);
                push (@validated, $seq);
            }
        }
    } 
    return @validated;  
}
    
sub get_Sequence {
    my ($self,$id) = @_;


    next ID unless defined($id);

    print(STDERR "Sequence id :  is [$id]\n");

    open(IN,"pfetch -q $id |") || $self->throw("Error fetching sequence for id [$id]");
	
    my $seqstr;
	
    while (<IN>) {
	chomp;
	$seqstr .= $_;
    }
    
    

    if (!defined($seqstr) || $seqstr eq "no match") {
	$self->warn("Couldn't find sequence for [$id]");
	return;
    }

    my $seq = new Bio::Seq(-id  => $id,
			   -seq => $seqstr);
    

    print (STDERR "Found sequence for $id [" . $seq->length() . "]\n");

    return $seq;
}

=head2 output

  Title   : output
  Usage   : $self->output
  Function: Returns results of est2genome as array of FeaturePair
  Returns : An array of Bio::EnsEMBL::FeaturePair
  Args    : none

=cut

sub output {
    my ($self) = @_;
    if (!defined($self->{_output})) {
	$self->{_output} = [];
    }
    return @{$self->{'_output'}};
}

1;


