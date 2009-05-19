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

Bio::EnsEMBL::Pipeline::RunnableDB::Scan

=head1 SYNOPSIS

my $db      = Bio::EnsEMBL::DBLoader->new($locator);
my $repmask = Bio::EnsEMBL::Pipeline::RunnableDB::Scan->new ( 
                                                    -dbobj      => $db,
			                                        -input_id   => $input_id
                                                    -analysis   => $analysis );
$repmask->fetch_input();
$repmask->run();
$repmask->output();
$repmask->write_output(); #writes to DB

=head1 DESCRIPTION

This object wraps Bio::EnsEMBL::Pipeline::Runnable::Scan to add
functionality to read and write to databases.
The appropriate Bio::EnsEMBL::Analysis object must be passed for
extraction of appropriate parameters. A Bio::EnsEMBL::Pipeline::DBSQL::Obj is
required for databse access.

=head1 CONTACT

Describe contact details here

=head1 APPENDIX

The rest of the documentation details each of the object methods. 
Internal methods are usually preceded with a _

=cut

package Bio::EnsEMBL::Pipeline::RunnableDB::Scan;

use strict;
use Bio::EnsEMBL::Pipeline::RunnableDB;
use Bio::EnsEMBL::Pipeline::Runnable::Scan;
use vars qw(@ISA);
@ISA = qw(Bio::EnsEMBL::Pipeline::RunnableDB);

=head2 new

    Title   :   new
    Usage   :   $self->new(-DBOBJ       => $db
                           -INPUT_ID    => $id
                           -ANALYSIS    => $analysis);
                           
    Function:   creates a Bio::EnsEMBL::Pipeline::RunnableDB::Scan object
    Returns :   A Bio::EnsEMBL::Pipeline::RunnableDB::Scan object
    Args    :    -dbobj:     A Bio::EnsEMBL::DBSQL::DBAdaptor, 
                input_id:   Contig input id , 
                -analysis:  A Bio::EnsEMBL::Analysis

=cut

sub new {
    my ($class, @args) = @_;
    my $self = $class->SUPER::new(@args);
    
    $self->{'_fplist'}      = [];
    $self->{'_genseq'}      = undef;
    $self->{'_runnable'}    = undef;
    
    # dbobj input_id mandatory and read in by BlastableDB
    # anlaysis not mandatory for BlastableDB, so we check here 
    $self->throw("Analysis object required") unless ($self->analysis);
    
    &Bio::EnsEMBL::Pipeline::RunnableDB::Scan::runnable($self,'Bio::EnsEMBL::Pipeline::Runnable::Scan');
    return $self;
}

=head2 fetch_input

    Title   :   fetch_input
    Usage   :   $self->fetch_input
    Function:   Fetches input data for Scan from the database
    Returns :   none
    Args    :   none

=cut

sub fetch_input {
    my( $self) = @_;
    
    $self->throw("No input id") unless defined($self->input_id);
    
    my $contigid  = $self->input_id;
    my $contig    = $self->db->get_Contig($contigid);
    my $genseq    = $contig->primary_seq() or $self->throw("Unable to fetch contig");
    $self->genseq($genseq);
}

#get/set for runnable and args
sub runnable {
    my ($self, $runnable) = @_;
    my $arguments = "";
    
    if ($runnable)
    {
        #extract parameters into a hash
        my ($parameter_string) = $self->parameters() ;
        my %parameters;
        if ($parameter_string)
        {
#            $parameter_string =~ s/\s+//g;
            my @pairs = split (/,/, $parameter_string);
            
            foreach my $pair (@pairs)
            {
                my ($key, $value) = split (/=>/, $pair);
		if ($key && $value) {
		    $parameters{$key} = $value;
		}
		else {
		    $arguments .= " $key ";
		}
            }
        }
        $parameters{'-scan'} = $self->analysis->program_file || undef;
        $parameters{'-args'} = $arguments;
        #creates empty Bio::EnsEMBL::Runnable::Scan object
        $self->{'_runnable'} = $runnable->new(%parameters);;
    }
    return $self->{'_runnable'};
}

1;