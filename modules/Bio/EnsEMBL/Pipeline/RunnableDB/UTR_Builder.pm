#
# Ensembl module for Bio::EnsEMBL::Pipeline::RunnableDB::UTR_Builder
#
# Cared for by EnsEMBL  <ensembl-dev@ebi.ac.uk>
#
# Copyright GRL and EBI
#
# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::Pipeline::RunnableDB::UTR_Builder

=head1 SYNOPSIS

my $t_e2g = new Bio::EnsEMBL::Pipeline::RunnableDB::UTR_Builder(
								 -db        => $db,
							         -input_id  => $input_id
								);

$t_e2g->fetch_input();
$t_e2g->run();
$t_e2g->output();
$t_e2g->write_output(); #writes to DB

=head1 DESCRIPTION

Combines predictions from proteins with predictions from cDNA alignments:


TODO:
>GB_UTR_BUILD_LEVEL 2 & 3
>For EST-bases elongation:
 filter for ESTs with best ditag coverage.



=head1 CONTACT

Ensembl - ensembl-dev@ebi.ac.uk

=head1 APPENDIX

The rest of the documentation details each of the object methods. Internal methods are 
usually preceded with a '_'

=cut


# Let the code begin...


package Bio::EnsEMBL::Pipeline::RunnableDB::UTR_Builder;

use vars qw(@ISA);
use strict;

use Bio::EnsEMBL::Pipeline::RunnableDB;
use Bio::EnsEMBL::Gene;
use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::Translation;
use Bio::EnsEMBL::Exon;
use Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils;
use Bio::EnsEMBL::Pipeline::Tools::TranslationUtils;
use Bio::EnsEMBL::Pipeline::Tools::ExonUtils;
use Bio::EnsEMBL::Pipeline::Tools::GeneUtils;
use Bio::EnsEMBL::Pipeline::Runnable::MiniGenomewise;
use Bio::EnsEMBL::Pipeline::GeneComparison::TranscriptComparator;
use Bio::SeqIO;
#use Bio::EnsEMBL::Map::DBSQL::DitagFeatureAdaptor;


# all the parameters are read from GeneBuild config files
use Bio::EnsEMBL::Pipeline::Config::GeneBuild::General    qw (
							      GB_INPUTID_REGEX
							     );

use Bio::EnsEMBL::Pipeline::Config::GeneBuild::Databases  qw (
							      GB_GW_DBHOST
							      GB_GW_DBUSER
							      GB_GW_DBPASS
							      GB_GW_DBNAME
							      GB_GW_DBPORT
							      GB_BLESSED_DBHOST
							      GB_BLESSED_DBUSER
							      GB_BLESSED_DBPASS
							      GB_BLESSED_DBNAME
							      GB_BLESSED_DBPORT
							      GB_cDNA_DBHOST
							      GB_cDNA_DBUSER
							      GB_cDNA_DBNAME
							      GB_cDNA_DBPASS
							      GB_cDNA_DBPORT
							      GB_EST_DBHOST
							      GB_EST_DBUSER
							      GB_EST_DBNAME
							      GB_EST_DBPASS
							      GB_EST_DBPORT
							      DITAG_DBHOST
							      DITAG_DBUSER
							      DITAG_DBNAME
							      DITAG_DBPASS
							      DITAG_DBPORT
							      GB_COMB_DBHOST
							      GB_COMB_DBUSER
							      GB_COMB_DBNAME
							      GB_COMB_DBPASS
							      GB_COMB_DBPORT
							     );

use Bio::EnsEMBL::Pipeline::Config::GeneBuild::Targetted qw  (
							      GB_TARGETTED_GW_GENETYPE
							     );

use Bio::EnsEMBL::Pipeline::Config::GeneBuild::Similarity  qw (
							      GB_SIMILARITY_GENETYPE
							      );

use Bio::EnsEMBL::Pipeline::Config::GeneBuild::Blessed     qw (
							      GB_BLESSED_GENETYPES
							      );

use Bio::EnsEMBL::Pipeline::Config::GeneBuild::UTR_Builder qw (
							      GB_cDNA_GENETYPE
							      GB_EST_GENETYPE
							      GB_COMBINED_MAX_INTRON
							      GB_GENEWISE_COMBINED_GENETYPE
							      GB_BLESSED_COMBINED_GENETYPE
							      GB_UTR_BUILD_LEVEL
							      OTHER_GENETYPES
							      DITAG_LOGIC_NAME
							      );

@ISA = qw(Bio::EnsEMBL::Pipeline::RunnableDB);

=head2 fetch_input
  Arg [1]    : 
  Description: 
  Returntype : 
  Exceptions : 
  Example    : 

=cut

sub fetch_input{
  my ($self,@args) = @_;

  # do not proceed unless build level has been set
  if(!$GB_UTR_BUILD_LEVEL){
    $self->throw("No GB_UTR_BUILD_LEVEL set in UTR_Builder config. Cannot build UTRs\n");
  }

  $self->fetch_sequence([], $self->genewise_db);

  # get genewise genes
  my $similarity_genes = $self->query->get_all_Genes_by_type($GB_SIMILARITY_GENETYPE);
  my $targetted_genes  = $self->query->get_all_Genes_by_type($GB_TARGETTED_GW_GENETYPE);

  print STDERR "got " . scalar(@{$targetted_genes}) . " targetted genewise genes\n";
  print STDERR "got " . scalar(@{$similarity_genes}) . " similarity genewise genes\n";

  $self->gw_genes( $similarity_genes);
  $self->gw_genes( $targetted_genes );

  # add user-defined gene-types in the same way
  foreach my $other_genetype (@{$OTHER_GENETYPES}) {
    my $other_genes = $self->query->get_all_Genes_by_type($other_genetype);
    print STDERR "got " . scalar(@{$other_genes}) . " $other_genetype genes\n;";
    $self->gw_genes( $other_genes );
  }

  # get blessed genes
  my $blessed_slice = $self->blessed_db->get_SliceAdaptor->fetch_by_name($self->input_id)
    if ($self->blessed_db);

  my @blessed_genes;
  foreach my $bgt(@{$GB_BLESSED_GENETYPES}){
    push(@blessed_genes, @{$blessed_slice->get_all_Genes_by_type($bgt->{'type'})});
  }

  print STDERR "got " . scalar(@blessed_genes) . " blessed genes\n";

  $self->blessed_genes( $blessed_slice, \@blessed_genes );

  print STDERR "converted to " . scalar(@{$self->blessed_genes}) . " blessed genes\n";

  # use GB_UTR_BUILD_LEVEL to determine which sequences to fetch
  my @cdna_genes;
  my @ditags;

  if($GB_UTR_BUILD_LEVEL <=2){
    # cDNA build
    my $cdna_vc = $self->cdna_db->get_SliceAdaptor->fetch_by_name($self->input_id);
    @cdna_genes = @{$cdna_vc->get_all_Genes_by_type($GB_cDNA_GENETYPE)};
    print STDERR "got " . scalar(@cdna_genes) . " cdnas ($GB_cDNA_GENETYPE)\n";
    $self->cdna_db->dbc->disconnect_when_inactive(1);
  }
  else{
    # EST build
    my $est_vc  = $self->est_db->get_SliceAdaptor->fetch_by_name($self->input_id);
    @cdna_genes = @{$est_vc->get_all_Genes_by_type($GB_EST_GENETYPE)};
    print STDERR "got " . scalar(@cdna_genes) . " ests ($GB_EST_GENETYPE)\n";
    $self->est_db->dbc->disconnect_when_inactive(1);
  }

  #get ditags for support [fsk]
  foreach my $ditag_type (@{$DITAG_LOGIC_NAME}) {
    #$self->throw($ditag_type);
    my $ditag_vc = $self->ditag_db->get_SliceAdaptor->fetch_by_name($self->input_id);
    push(@ditags, @{$ditag_vc->get_all_DitagFeatures($ditag_type)});
    print STDERR "got " . scalar(@ditags) . " ".$ditag_type." ditags\n";
    $self->ditag_db->dbc->disconnect_when_inactive(1);
  }
  if(scalar @ditags){
    @ditags = sort {$a->start <=> $b->start} @ditags;
    $self->ditags(\@ditags);
  }
  else{
    print STDERR "not using Ditags\n";
  }

  # filter cdnas
  my $filtered_cdna = $self->_filter_cdnas(\@cdna_genes);
  $self->cdna_genes($filtered_cdna);
  print STDERR "got " . scalar(@{$filtered_cdna}) . " cdnas or ESTs after filtering\n";
  $self->genewise_db->dbc->disconnect_when_inactive(1);
  $self->blessed_db->dbc->disconnect_when_inactive(1) if ($self->blessed_db);
}

=head2 run
  Arg [1]    : 
  Description: 
  Returntype : 
  Exceptions : 
  Example    : 

=cut

sub run {
  my ($self,@args) = @_;

  # first filter the genewise predictions to remove fragments from
  # the equation. Make sure we keep the fragments to let the
  # genebuilder do the final sorting out, but don't add UTRs to them.
  my $filtered_genes = $self->filter_genes($self->gw_genes);

  if($GB_UTR_BUILD_LEVEL == 1){
    $self->run_basic_cdna_matching($self->blessed_genes, $GB_BLESSED_COMBINED_GENETYPE);
    $self->run_basic_cdna_matching($filtered_genes, $GB_GENEWISE_COMBINED_GENETYPE);
  }
  elsif($GB_UTR_BUILD_LEVEL == 2){
    $self->run_stringent_cdna_matching($self->blessed_genes, $GB_BLESSED_COMBINED_GENETYPE);
    $self->run_stringent_cdna_matching($filtered_genes, $GB_GENEWISE_COMBINED_GENETYPE);
  }
  elsif($GB_UTR_BUILD_LEVEL == 3){
    $self->run_stringent_est_matching($self->blessed_genes, $GB_BLESSED_COMBINED_GENETYPE);
    $self->run_stringent_est_matching($filtered_genes, $GB_GENEWISE_COMBINED_GENETYPE);
  }
  else{
    $self->throw("Build level " . $GB_UTR_BUILD_LEVEL . " is not one I recognise\n");
  }

  # remap to raw contig coords
  my @remapped = $self->remap_genes();
  $self->output(@remapped);
}

=head2 filter_genes
  Arg [1]    : ref to array of Bio::EnsEMBL::Gene
  Description: We do not want to add UTRs to fragments of genes
  otherwise they get boosted in importance during the final gene build
  and produce rubbish alternative transcripts and in the worst cases
  can misjoin clusters especially if there is some
  misassembled/duplicated sequence. One solution is to cluster the
  genewises at this stage in much the same way as we do during the
  GeneBuilder run, and attempt to add UTRs ony to the best ones eg
  fullest genomic extent.
  Returntype : ref to array of Bio::EnsEMBL::Gene
  Exceptions : 
  Example    : 
 
=cut

sub filter_genes{
  my ($self, $genesref) = @_;

  # all the genes are single transcript at this stage
  my $clustered_genes = $self->cluster_CDS($genesref);

  my $pruned_CDS = $self->prune_CDS($clustered_genes);

  return $pruned_CDS;
}

=head2 cluster_CDS
  Arg [1]    : ref to array of Bio::EnsEMBL::Gene
  Description: Separates CDSs according to strand and then clusters
               each set by calling _cluster_CDS_by_genomic_range()
  Returntype : ref to array of Bio::EnsEMBL::Pipeline::GeneComparison::GeneCluster
  Exceptions : 
  Example    : 
 
=cut

sub cluster_CDS {
  my ($self,$CDSref) = @_;

  my @forward_CDS;
  my @reverse_CDS;

  foreach my $gene (@$CDSref){
    my @exons = @{ $gene->get_all_Exons };
    if ( $exons[0]->strand == 1 ){
      push( @forward_CDS, $gene );
    }
    else{
      push( @reverse_CDS, $gene );
    }
  }

  my @forward_clusters;
  my @reverse_clusters;

  if ( @forward_CDS ){
    @forward_clusters = @{$self->_cluster_CDS_by_genomic_range( \@forward_CDS )};
  }
  if ( @reverse_CDS ){
    @reverse_clusters = @{$self->_cluster_CDS_by_genomic_range( \@reverse_CDS )};
  }

  my @clusters;
  if ( @forward_clusters ){
    $self->forward_genewise_clusters(\@forward_clusters);
    push( @clusters, @forward_clusters);
  }
  if ( @reverse_clusters ){
    $self->reverse_genewise_clusters(\@reverse_clusters);
    push( @clusters, @reverse_clusters);
  }

  return \@clusters;
}


=head2 _cluster_CDS_by_genomic_range
  Arg [1]    : ref to array of Bio::EnsEMBL::Gene
  Description: Clusters CDSs according to genomic overlap
  Returntype : ref to array of Bio::EnsEMBL::Pipeline::GeneComparison::GeneCluster
  Exceptions : 
  Example    : 
 
=cut

sub _cluster_CDS_by_genomic_range{
  my ($self, $genesref) = @_;

  my @genes = @$genesref;
  my %genetypes;
  foreach my $gene(@genes){
    $genetypes{$gene->biotype} = 1;
  }
  my @genetypes = keys %genetypes;
  my @empty= ('');

  # first sort the genes

  @genes = sort { $a->get_all_Transcripts->[0]->start <=> $b->get_all_Transcripts->[0]->start 
		    ? $a->get_all_Transcripts->[0]->start <=> $b->get_all_Transcripts->[0]->start 
		      : $b->get_all_Transcripts->[0]->end <=> $a->get_all_Transcripts->[0]->end } @genes;


  # create a new cluster 
  my $cluster=Bio::EnsEMBL::Pipeline::GeneComparison::GeneCluster->new();
  $cluster->gene_Types(\@genetypes, \@empty);
  my $count = 0;
  my @cluster_starts;
  my @cluster_ends;
  my @clusters;

  # put the first gene into these cluster
  $cluster->put_Genes( $genes[0] );

  $cluster_starts[$count] = $genes[0]->get_all_Transcripts->[0]->start;
  $cluster_ends[$count]   = $genes[0]->get_all_Transcripts->[0]->end;

  # store the list of clusters
  push( @clusters, $cluster );

  # loop over the rest of the genes
 LOOP1:
  for (my $c=1; $c<=$#genes; $c++){

    if ( !( $genes[$c]->get_all_Transcripts->[0]->end < $cluster_starts[$count] ||
	    $genes[$c]->get_all_Transcripts->[0]->start > $cluster_ends[$count] ) ){
      $cluster->put_Genes( $genes[$c] );

      # re-adjust size of cluster
      if ($genes[$c]->get_all_Transcripts->[0]->start < $cluster_starts[$count]) {
	$cluster_starts[$count] = $genes[$c]->get_all_Transcripts->[0]->start;
      }
      if ( $genes[$c]->get_all_Transcripts->[0]->end > $cluster_ends[$count]) {
	$cluster_ends[$count] =  $genes[$c]->get_all_Transcripts->[0]->end;
      }
    }
    else{
      # else, create a new cluster with this feature
      $count++;
      $cluster = Bio::EnsEMBL::Pipeline::GeneComparison::GeneCluster->new();
      $cluster->gene_Types(\@genetypes, \@empty);
      $cluster->put_Genes( $genes[$c] );
      $cluster_starts[$count] = $genes[$c]->get_all_Transcripts->[0]->start;
      $cluster_ends[$count]   = $genes[$c]->get_all_Transcripts->[0]->end;
      
      # store it in the list of clusters
      push(@clusters,$cluster);
    }
  }
  return \@clusters;
}


=head2 prune_CDS
  Arg [1]    : ref to array of Bio::EnsEMBL::Pipeline::GeneComparison::GeneCluster 
  Description: rejects duplicate CDS, makes sure they are kept on
               unmatched_geens or they (and their supporting evidence)
               will be lost for the rest of the build

  Returntype : ref to array of Bio::EnsEMBL::Gene 
  Exceptions : 
  Example    : my @pruned_CDS = $self->prune_CDS($CDS_clusters) 
 
=cut

sub prune_CDS {
  my ($self, $gene_cluster_ref) = @_;
  my $cluster_count = 0;
  my @pruned_transcripts;
  my @pruned_genes;

 CLUSTER:
  foreach my $gene_cluster ( @$gene_cluster_ref ){
    $cluster_count++;
    my @unpruned_genes;

    foreach my $unpruned_gene($gene_cluster->get_Genes){
      if(scalar(@{$unpruned_gene->get_all_Transcripts}) > 1){
        print "VAC: " . $unpruned_gene->dbID . " has >1 transcript - can't handle it yet \n";
        next;
      }
      push(@unpruned_genes, $unpruned_gene);
    }

    # sort the unpruned_genes by total exon length of their single transcripts - there are no UTRs to worry about yet
    @unpruned_genes = sort{$b->get_all_Transcripts->[0]->length <=> $a->get_all_Transcripts->[0]->length} @unpruned_genes;

    ##############################
    #
    # deal with single exon genes
    #
    ##############################

    # do we really just want to take the first transcript only?
    # If there's a very long single exon gene we will lose any underlying multi-exon transcripts
    # this may increase problems with the loss of valid single exon genes as mentioned below. 
    # it's a balance between keeping multi exon transcripts and losing single exon ones
    my $maxexon_number = 0;

    foreach my $gene (@unpruned_genes){
      my $exon_number = scalar(@{$gene->get_all_Transcripts->[0]->get_all_Exons});
      if ( $exon_number > $maxexon_number ){
	$maxexon_number = $exon_number;
      }
    }

    if ($maxexon_number == 1){ # ie the longest transcript is a single exon one
      # take the longest:
      push (@pruned_genes, $unpruned_genes[0]);
      print STDERR "VAC: found single_exon_transcript: " .$unpruned_genes[0]->dbID. "\n";
      shift @unpruned_genes;
      $self->unmatched_genes(@unpruned_genes);
      next CLUSTER;
    }

    # otherwise we need to deal with multi exon transcripts and reject duplicates.
    # links each exon in the transcripts of this cluster with a hash of other exons it is paired with
    my %pairhash;

    # allows retrieval of exon objects by exon->id - convenience
    my %exonhash;

    ##############################
    #
    # prune redundant transcripts
    #
    ##############################
  GENE:
    foreach my $gene (@unpruned_genes) {

      my @exons = @{$gene->get_all_Transcripts->[0]->get_all_Exons};

      my $i     = 0;
      my $found = 1;

      # 10.1.2002 VAC we know there's a potential problem here - single exon transcripts which are in a
      # cluster where the longest transcript has > 1 exon are not going to be considered in
      # this loop, so they'll always be marked "transcript already seen"
      # How to sort them out? If the single exon overlaps an exon in a multi exon transcript then
      # by our rules it probably ought to be rejected the same way transcripts with shared exon-pairs are.
      # Tough one.

    EXONS:
      for ($i = 0; $i < $#exons; $i++) {
	my $foundpair = 0;
	my $exon1 = $exons[$i];
	my $exon2 = $exons[$i+1];

        # go through the exon pairs already stored in %pairhash. 
        # If there is a pair whose exon1 overlaps this exon1, and 
        # whose exon2 overlaps this exon2, then these two transcripts are paired
	
        foreach my $first_exon_id (keys %pairhash) {
          my $first_exon = $exonhash{$first_exon_id};

          foreach my $second_exon_id (keys %{$pairhash{$first_exon}}) {
            my $second_exon = $exonhash{$second_exon_id};

            if ( $exon1->overlaps($first_exon) && $exon2->overlaps($second_exon) ) {
              $foundpair = 1;
		
              # eae: this method allows a transcript to be covered by exon pairs
              # from different transcripts, rejecting possible
              # splicing variants. Needs rethinking
		
            }
          }
        }

	
	if ($foundpair == 0) {	# ie this exon pair does not overlap with a pair yet found in another transcript
	  $found = 0;		# ie currently this transcript is not paired with another

	  # store the exons so they can be retrieved by id
	  $exonhash{$exon1} = $exon1;
	  $exonhash{$exon2} = $exon2;

	  # store the pairing between these 2 exons
	  $pairhash{$exon1}{$exon2} = 1;
	}
      }				# end of EXONS

      # decide whether this is a new transcript or whether it has already been seen

      if ($found == 0) {
	push(@pruned_genes, $gene);
      }
      elsif ($found == 1 && $#exons == 0){
        $self->unmatched_genes($gene);
      }
      else {
        $self->unmatched_genes($gene);
	if ( $gene == $unpruned_genes[0] ){
	}
      }
    } # end of this gene
  } #end CLUSTER

  return \@pruned_genes;
}


=head2 run_basic_cdna_matching 
  Arg [1]    : ref to array of Bio::EnsEMBL::Gene
  Arg [2]    : string representing genetype to be associated with UTR-modified genes
  Description: matches CDS (genewise) predictions to cDNA alignments
               considering only terminal CDS exons
  Returntype : none
  Exceptions : 
  Example    : 

=cut

sub run_basic_cdna_matching{
  my ($self, $genesref, $combined_genetype) = @_;

  # merge exons with frameshifts into a big exon
  my @merged_genes = $self->_merge_genes($genesref);
  print STDERR "got " . scalar(@merged_genes) . " merged " . $combined_genetype . " genes\n";  

  # first of all, sort genewises by exonic length and genomic length  
  @merged_genes = sort { my $result = (  $self->_transcript_length_in_gene($b) <=>
					 $self->_transcript_length_in_gene($a) );
			 unless ($result){
			   return ( $self->_transcript_exonic_length_in_gene($b) <=>
				    $self->_transcript_exonic_length_in_gene($a) );
			 }
			 return $result;
		       } @merged_genes;

  print STDERR "now have " . scalar(@merged_genes) . " merged genes\n";

  # find one-2-one matching between proteins and cdnas
 CDS:
  foreach my $cds (@merged_genes){
    # should be only 1 transcript
    my @cds_tran  = @{$cds->get_all_Transcripts};			
    my @cds_exons = @{$cds_tran[0]->get_all_Exons}; # ordered array of exons
    my $strand    = $cds_exons[0]->strand;

    if($cds_exons[$#cds_exons]->strand != $strand){
      $self->warn("first and last cds exons have different strands - can't make a sensible combined gene\n");
      # get and store unmerged version of cds
      my $unmerged_cds = $self->retrieve_unmerged_gene($cds);
      $self->unmatched_genes($unmerged_cds);
      next CDS;
    }

    # find the matching cdna
    my ($matching_cdnas, $utr_length_hash) = $self->match_protein_to_cdna($cds);
    my @matching_cdnas                     = @{$matching_cdnas};
    my %utr_length_hash                    = %$utr_length_hash;

    ##############################
    # now we can sort by length of the added UTR
    # using %utr_length_hash
    # not yet in use
    ##############################

    if(!@matching_cdnas){
      # store non matched genewise
      #print STDERR "no matching cDNA for " . $gw->dbID ."\n";
      my $unmerged_cds = $self->retrieve_unmerged_gene($cds);
      $self->unmatched_genes($unmerged_cds);
      next CDS;
    }

    # from the matching ones, take the best fit

    my @list;
    foreach my $cdna ( @matching_cdnas ){
      # we check exon_overlap and fraction of overlap in cdna and e2g:
      my @cds_trans  = @{$cds->get_all_Transcripts};
      my @cdna_trans = @{$cdna->get_all_Transcripts};
      my ($exon_overlap, $extent_overlap) =
	Bio::EnsEMBL::Pipeline::GeneComparison::TranscriptComparator->
	    _compare_Transcripts( $cds_trans[0], $cdna_trans[0] );
      #[fsk]
      #use ditags if avaliable, find the ones matching the cDNA within X bases
      my $ditag_verificaction = undef;
      if(scalar @{$DITAG_LOGIC_NAME}){
	$ditag_verificaction = $self->look_for_ditags($cdna_trans[0]);
      }
      push (@list, [$exon_overlap, $extent_overlap, $cdna, $ditag_verificaction]);
    }

    # sort them
    @list = sort{
      # by number of exon overlap
      my $result = ( $$b[0] <=> $$a[0] );
      unless ($result){
	# else, by extent of the overlap
	$result =  ( $$b[1] <=> $$a[1] );
      }
      if(scalar @{$DITAG_LOGIC_NAME}){
	unless ($result){
	  # else, by supporting ditags
	  $result = ( $$b[3] <=> $$a[3] );
	}
	#print STDERR "\nditagfiltered $result";
      }
      unless ($result){
	# else, by genomic length of the cdna
	$result = (  $self->_transcript_length_in_gene($$b[2]) <=>
		     $self->_transcript_length_in_gene($$a[2]) );
      }
      unless ($result){
	# else, by exonic extent of the cdna
	$result = (  $self->_transcript_exonic_length_in_gene($$b[2]) <=>
		     $self->_transcript_exonic_length_in_gene($$a[2]) );
      }
    } @list;

    my $howmany = scalar(@list);
    my $cdna_match;
    my $this    = shift @list;
    $cdna_match = $$this[2];

    unless ( $cdna_match){
      print STDERR "No cdna found for cds_gene ".$cds->dbID." ";
      if ( $howmany == 0 ){
	print STDERR "(no cdna matched this cds gene)\n";
      }

      my $unmerged_cds = $self->retrieve_unmerged_gene($cds);
      $self->unmatched_genes($unmerged_cds);
      next CDS;
    }

  #  print STDERR "combining cds gene : " . $cds->dbID.":\n";
  #  Bio::EnsEMBL::Pipeline::Tools::GeneUtils->_print_Gene($cds);
  #  print STDERR "with cdna gene " . $cdna_match->dbID . ":\n";
  #  Bio::EnsEMBL::Pipeline::Tools::GeneUtils->_print_Gene($cdna_match);

    my $combined_transcript = $self->combine_genes($cds, $cdna_match);
    # just check combined transcript works before throwing away the original  transcript
    unless (  $combined_transcript && Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->
	          _check_Transcript($combined_transcript,$self->query)
	      && Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->
	           _check_introns($combined_transcript,$self->query)){
      $combined_transcript = undef;
    }

    # make sure combined transcript doesn't misjoin any genewise clusters
    if ($combined_transcript){
      print STDERR "About to check for cluster joiners\n";
        if($self->find_cluster_joiners($combined_transcript)){
          # revert to unmodified
          $combined_transcript = undef;
        }
      }

    if ( $combined_transcript ){
      #transfer evidence and make the new gene
      $combined_transcript = $self->_transfer_evidence($combined_transcript, $cdna_match);
      $self->make_gene($combined_genetype, $combined_transcript);
    }
    else{
      #print STDERR "no combined gene built from " . $gw->dbID ."\n";
      my $unmerged_cds = $self->retrieve_unmerged_gene($cds);
      $self->unmatched_genes($unmerged_cds);
      next CDS;
    }
  }
}


=head2 look_for_ditags
  Arg [1]    : cdna_transcript
  Description: look for ditags in the region of the transcripts
               that might support it
  Returntype : int score: high value indicates many/well matching ditags
  Exceptions : none

=cut

sub look_for_ditags{
  my ($self, $cdna_transcript) = @_;

  my $ditag_score = 0;
  my $cdna_start  = $cdna_transcript->start;
  my $cdna_end    = $cdna_transcript->end;
  my $ditag_distance = 5; #will need to go into CONFIG

  foreach my $ditag ($self->ditags){
    if((abs($ditag->start - $cdna_start) < $ditag_distance)
       && (abs($ditag->end - $cdna_end) < $ditag_distance)){
      #matching ditag; produce a score favoring those transcripts,
      #that have many ditags &/| perfectly positioned ditags.
      $ditag_score += $ditag_distance - (abs($ditag->start - $cdna_start)) +
                      $ditag_distance - (abs($ditag->end - $cdna_end));
    }
    if($ditag->start > $cdna_end){ last; }
  }

  return $ditag_score;
}


=head2 run stringent_cdna_matching
  Arg [1]    : ref to array of Bio::EnsEMBL::Gene
  Arg [2]    : string representing genetype to be associated with UTR-modified genes
  Description: 
  Returntype : none
  Exceptions : 
  Example    : 
 
=cut

sub run_stringent_cdna_matching{

  self->throw("UTR-BUILDING 2: not implemented yet!");

}

=head2 run_stringent_est_matching
 
  Arg [1]    : ref to array of Bio::EnsEMBL::Gene
  Arg [2]    : string representing genetype to be associated with UTR-modified genes
  Description: 
  Returntype : none
  Exceptions : 
  Example    : 
 
=cut

sub run_stringent_est_matching{

  self->throw("UTR-BUILDING 3: not implemented yet!");

}

=head2 find_cluster_joiners
  Arg [1]    : ref to array of Bio::EnsEMBL::Pipeline::GeneComparison::GeneCluster 
  Description: screens UTR modified transcripts for those that
               potentially misjoin genewise clusters, and removes them


  Returntype : ref to array of Bio::EnsEMBL::Gene 
  Exceptions : 
  Example    : 
 
=cut

sub find_cluster_joiners{
  my ($self, $transcript) = @_;

  my @clusters;
  my $transcript_start;
  my $transcript_end;
  my $overlaps_previous_cluster = 0;

  if ($transcript->get_all_Exons->[0]->strand == 1){
    @clusters = @{$self->forward_genewise_clusters};
    $transcript_start = $transcript->start_Exon->start;
    $transcript_end = $transcript->end_Exon->end;
  }
  else{
    @clusters = @{$self->reverse_genewise_clusters()};
    $transcript_start = $transcript->end_Exon->start;
    $transcript_end = $transcript->start_Exon->end;
  }

  if(!scalar(@clusters)){
    print STDERR "VAC: odd, no clusters\n";
    return 0;
  }

  print STDERR "VAC: strand: " . $transcript->get_all_Exons->[0]->strand  . "\n";
  print "transcript spans $transcript_start - $transcript_end\n";
  print "clusters span: \n";

  # clusters are stored sorted so that $a->start <= $b->start regardless of strand
  CLUSTER:
  foreach my $cluster(@clusters){
    print "\n" . $cluster->start . " - " . $cluster->end . "\n";
    if($transcript_start <= $cluster->start
       && $transcript_end >= $cluster->start
       && $transcript_end <= $cluster->end){
      print "transcript ends in this cluster\n";
      if($overlaps_previous_cluster){
        print "transcript joins clusters - discard it\n";
        return 1;
      }
      # else not a problem
      last CLUSTER;
    }
    elsif($transcript_start <= $cluster->end
	  && $transcript_start >= $cluster->start
	  && $transcript_end >= $cluster->end){
      print STDERR "VAC: transcript starts in this cluster\n";
      $overlaps_previous_cluster = 1;
    }
    elsif($transcript_start <= $cluster->start
	  && $transcript->end >= $cluster->end){
      print STDERR "VAC: transcript spans this cluster\n";
      $overlaps_previous_cluster = 1;
    }
  }

  return 0;
}

=head2 _filter_cdnas
  Arg [1]    : ref to array of Bio::EnsEMBL::Gene
  Description: This method checks the cDNAs. ( see
               Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils::_check_transcript()
               and _check_introns for more details ) ImportantNote:
               translation is not checked as these cdnas come without
               translation
  Returntype : ref to array of Bio::EnsEMBL::Gene
  Exceptions : 
  Example    : 
 
=cut

sub _filter_cdnas{
  my ($self,$cdna_arrayref) = @_;
  my @newcdna;

  #print STDERR "filtering ".scalar(@{$cdna_arrayref})." cdnas\n";
 cDNA_GENE:
  foreach my $cdna (@{$cdna_arrayref}) {

  cDNA_TRANSCRIPT:
    foreach my $tran (@{$cdna->get_all_Transcripts}) {

      # rejecting on basis of intron length may not be valid here
      # - it may not be that simple in the same way as it isn;t that simple in Targetted & Similarity builds

      next cDNA_TRANSCRIPT unless (
				   Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->
				   _check_Transcript($tran,$self->query)
				   && Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->
				   _check_introns($tran,$self->query)
				  );

      #print STDERR "keeping trans_dbID:" . $tran->dbID . "\n";
      push(@newcdna,$cdna);
    }
  }
  return \@newcdna;
}

=head2  _transcript_exonic_length_in_gene
  Arg [1]    : Bio::EnsEMBL::Gene
  Description: method to calculate the exonic length of a transcript
               which is inside a gene; this assumes that these
               genewise genes contain one transcript each

  Returntype : integer - total length of exons
  Exceptions : 
  Example    : 
 
=cut

sub _transcript_exonic_length_in_gene{
  my ($self, $gene) = @_;
  my @trans = @{$gene->get_all_Transcripts};
  my $tran = $trans[0];
  my $exonic_length = 0;
  foreach my $exon ( @{$tran->get_all_Exons} ){
    $exonic_length += ($exon->end - $exon->start + 1);
  }
  return $exonic_length;
}

=head2  _transcript_length_in_gene
  Arg [1]    : Bio::EnsEMBL::Gene
  Description: method to calculate the length of a transcript in
               genomic extent; this assumes that these genewise genes
               contain one transcript each
  Returntype : integer - length of genome covered by transcript
  Exceptions : 
  Example    : 
 
=cut 

sub _transcript_length_in_gene{
  my ($self, $gene) = @_;
  my @trans = @{$gene->get_all_Transcripts};
  my @exons= @{$trans[0]->get_all_Exons};
  my $genomic_extent = 0;
  if ( $exons[0]->strand == -1 ){
    @exons = sort{ $b->start <=> $a->start } @exons;
    $genomic_extent = $exons[0]->end - $exons[$#exons]->start + 1;
  }
  elsif( $exons[0]->strand == 1 ){
    @exons = sort{ $a->start <=> $b->start } @exons;
    $genomic_extent = $exons[$#exons]->end - $exons[0]->start + 1;
  }
  return $genomic_extent;
}

=head2  write_output
  Arg [1]    : none
  Description: 
  Returntype : none
  Exceptions : 
  Example    : 
 
=cut 

sub write_output {
  my($self) = @_;

  # write genes in the database: GB_COMB_DBNAME@GB_COMB_DBHOST
  my $gene_adaptor = $self->output_db->get_GeneAdaptor;

print STDERR "Have " . scalar ($self->output) . "genes to write\n";

 GENE:
  foreach my $gene ($self->output) {	
    if(!$gene->analysis ||
       $gene->analysis->logic_name ne $self->analysis->logic_name){
      $gene->analysis($self->analysis);
    }

    # double check gene coordinates
    $gene->recalculate_coordinates;

    #As all genes/exons are stored as new in the target db
    #it's save to remove the old adaptor & old dbID here,
    #to avoid warnings from the store function.
    foreach my $exon (@{$gene->get_all_Exons}) {
      $exon->adaptor(undef);
      $exon->dbID(undef);
    }

    eval {
      $gene_adaptor->store($gene);
      print STDERR "wrote gene dbID " . $gene->dbID . "\n";
      #      foreach my $t ( @{$gene->get_all_Transcripts} ){
      #	Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_print_Evidence($t);
      #      }
    };
    if( $@ ) {
      print STDERR "UNABLE TO WRITE GENE " . $gene->dbID. "of type " . $gene->type  . "\n\n$@\n\nSkipping this gene\n";
      #      foreach my $t ( @{$gene->get_all_Transcripts} ){
      #	Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_print_Evidence($t);
      #      }
    }
  }
}

=head2 make_gene 
  Arg [1]    : string representing genetyoe to be associated with genes
  Arg [1]    : array of Bio::EnsEMBL::Transcript
  Description: Constructs Bio::EnsEMBL::Gene objects from UTR-modified transcripts
  Returntype : none; new genes are stored in self->combined_genes
  Exceptions : 
  Example    : 
 
=cut

sub make_gene{
  my ($self, $genetype, @transcripts) = @_;

  unless ( $genetype ){
    $self->throw("You must define GB_GENEWISE_COMBINED_GENETYPE in Bio::EnsEMBL::Pipeline::Conf::GeneBuild::Combined");
  }

  # an analysis should be passed in via the RunnableDB.m parent class:
  my $analysis = $self->analysis;
  unless ($analysis){
    $self->throw("You have to pass an analysis to this RunnableDB through new()");
  }

  my @genes;
  my $count=0;

  foreach my $trans(@transcripts){

    unless ( Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_check_Transcript( $trans ) ){
      print STDERR "rejecting transcript\n";
      return;
    }

    my $gene = new Bio::EnsEMBL::Gene;
    $gene->type($genetype);
    $gene->add_Transcript($trans);
    $gene->analysis($analysis);

    # do not modify the analysis of the supporting features
    # they should be the original ones: cdna, targetted_genewise or similarity_genewise

    if($self->validate_gene($gene)){
      push (@genes,$gene);
      $count++;
    }
  }

  $self->combined_genes(\@genes);

}

=head2 match_protein_to_cdna
  Arg [1]    : Bio::EnsEMBL::Gene
  Description: this method tries to find the cdnas that can be merged with the genewise genes.
             Basically it checks for exact internal splice matching in the 5' and 3' exons of the genewise gene.
             In order to match a starting genewise exon with an cDNA exon, we need to have 
             a. exactly coinciding exon boundaries
             b. either cdna exon has start <= genewise exon start, 
             OR cdna exon start lies within $exon_slop bp of genewise exon start AND 
             the cdna transcript will add extra UTR exons. 
             Substitute "end" for "start" for 3prime ends of transcripts  
             BUT do not allow through any cDNA that will result just in a 
             shortened peptide without additional UTR exons.
  Returntype :  ref to array of Bio::EnsEMBL::Gene, ref to hash relating Bio::EnsEMBL::Gene to UTR length
  Exceptions : 
  Example    : 
 
=cut

sub match_protein_to_cdna{
  my ($self, $gw) = @_;

  my %UTR_hash;

  #print STDERR "\nSearching cDNA for gw gene dbID: ".$gw->dbID."\n";
  my @matching_e2g;
  my @gw_tran = @{$gw->get_all_Transcripts};

  my @gw_exons = @{$gw_tran[0]->get_all_Exons};
  my $strand   = $gw_exons[0]->strand;
  if($gw_exons[$#gw_exons]->strand != $strand){
    $self->warn("first and last gw exons have different strands ".
		"- can't make a sensible combined gene\n with ".$gw_tran[0]->dbId );
      return;
  }
  if ( @gw_exons ){
    if ($strand == 1 ){
      @gw_exons = sort { $a->start <=> $b->start } @gw_exons;
    }
    else{
      @gw_exons = sort { $b->start <=> $a->start } @gw_exons;
    }
  }
  else{
    $self->warn("gw gene without exons: ".$gw->dbID.", skipping it");
    return undef;
  }

  my $exon_slop = 20;

 cDNA:
  foreach my $e2g($self->cdna_genes){
    my @egtran  = @{$e2g->get_all_Transcripts};
    my @eg_exons = @{$egtran[0]->get_all_Exons};

    $strand   = $eg_exons[0]->strand;
    if($eg_exons[$#eg_exons]->strand != $strand){
	$self->warn("first and last e2g exons have different strands - skipping transcript ".$egtran[0]->dbID);
	next cDNA;
    }
    if ($strand == 1 ){
      @eg_exons = sort { $a->start <=> $b->start } @eg_exons;
    }
    else{
      @eg_exons = sort { $b->start <=> $a->start } @eg_exons;
    }

    my $fiveprime_match  = 0;
    my $threeprime_match = 0;
    my $left_exon;
    my $right_exon;
    my $left_diff  = 0;
    my $right_diff = 0;
    my $UTR_length;


    # Lets deal with single exon genes first
    if ($#gw_exons == 0) {
      foreach my $current_exon (@eg_exons) {
	
	if($current_exon->strand != $gw_exons[0]->strand){
	  next cDNA;
	}
	
	# don't yet deal with genewise leakage for single exon genes
	if ($gw_exons[0]->end   <= $current_exon->end &&
	    $gw_exons[0]->start >= $current_exon->start){
	  $fiveprime_match  = 1;
	  $threeprime_match = 1;
	
	  $left_exon   = $current_exon;
	  $right_exon  = $current_exon; 
	  $left_diff   = $gw_exons[0]->start - $current_exon->start;
	  $right_diff  = $current_exon->end  - $gw_exons[0]->end;
	}
      }
      # can match either end, or both
      if($fiveprime_match || $threeprime_match){
	$UTR_length = $self->_compute_UTRlength($egtran[0],$left_exon,$left_diff,$right_exon,$right_diff);
	$UTR_hash{$e2g} = $UTR_length;
	push(@matching_e2g, $e2g);
      }

      # Now the multi exon genewises
    }
    else {

    cDNA_EXONS:
      foreach my $current_exon (@eg_exons) {
	
	if($current_exon->strand != $gw_exons[0]->strand){
	  next cDNA;
	}
	
	if($gw_exons[0]->strand == 1){
	
	  #FORWARD:

	  # 5prime
	  if ($gw_exons[0]->end == $current_exon->end &&
	      # either e2g exon starts before genewise exon
	      ($current_exon->start <= $gw_exons[0]->start ||
	       # or e2g exon is a bit shorter but there are spliced UTR exons as well
	       (abs($current_exon->start - $gw_exons[0]->start) <= $exon_slop && $current_exon != $eg_exons[0]))){
	
	    $fiveprime_match = 1;
	    $left_exon = $current_exon;
	    $left_diff = $gw_exons[0]->start - $current_exon->start;
	  }
	  # 3prime
	  elsif($gw_exons[$#gw_exons]->start == $current_exon->start &&
		# either e2g exon ends after genewise exon
		($current_exon->end >= $gw_exons[$#gw_exons]->end ||
		 # or there are UTR exons to be added
		 (abs($current_exon->end - $gw_exons[$#gw_exons]->end) <= $exon_slop &&
		  $current_exon != $eg_exons[$#eg_exons]))){
	
	    $threeprime_match = 1;
	    $right_exon = $current_exon;
	    $right_diff  = $current_exon->end - $gw_exons[0]->end;
	  }
	}
	elsif($gw_exons[0]->strand == -1){
	
	  #REVERSE:

	  # 5prime
	  if ($gw_exons[0]->start == $current_exon->start &&
	      # either e2g exon ends after gw exon
	      ($current_exon->end >= $gw_exons[0]->end ||
	       # or there are UTR exons to be added
	       (abs($current_exon->end - $gw_exons[0]->end) <= $exon_slop &&
		$current_exon != $eg_exons[0]))){
	    #print STDERR "fiveprime reverse match\n";
	
	    $fiveprime_match = 1;
	    $right_exon  = $current_exon;
	    $right_diff  = $current_exon->end  - $gw_exons[0]->end;
	  }
	  #3prime
	  elsif ($gw_exons[$#gw_exons]->end == $current_exon->end &&
		 # either e2g exon starts before gw exon
		 ($current_exon->start <= $gw_exons[$#gw_exons]->start ||
		  # or there are UTR exons to be added
		  (abs($current_exon->start - $gw_exons[$#gw_exons]->start) <= $exon_slop &&
		   $current_exon != $eg_exons[$#eg_exons]))){
	    #print STDERR "threeprime reverse match\n";

	    $threeprime_match = 1;
	    $left_exon = $current_exon;
	    $left_diff = $gw_exons[0]->start - $current_exon->start;
	  }
	}
      }
      if($fiveprime_match || $threeprime_match){
	$UTR_length = $self->_compute_UTRlength($egtran[0],$left_exon,$left_diff,$right_exon,$right_diff);
	$UTR_hash{$e2g} = $UTR_length;
	push(@matching_e2g, $e2g);
	
	# test
	foreach my $egtran ( @{$e2g->get_all_Transcripts} ){
	  #print STDERR "Found cDNA match trans_dbID:".$egtran->dbID."\n";
	}
      }
    }
  }
  return (\@matching_e2g,\%UTR_hash);
}

=head2 _compute_UTRlength
  Arg [1]    : 
  Description: 
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub _compute_UTRlength{
 my ($self, $transcript, $left_exon, $left_diff, $right_exon, $right_diff) = @_;
 my $strand = $transcript->start_Exon->strand;
 my @exons  = sort { $a->start <=> $b->start } @{ $transcript->get_all_Exons };

 my $UTRlength = 0;
 my $in_UTR = 1;

 foreach my $exon ( @exons ){
   if ( defined $left_exon && $exon == $left_exon ){
     $UTRlength += $left_diff;
     $in_UTR     = 0;
   }
   elsif( defined $right_exon && $exon == $right_exon ){
     $UTRlength += $right_diff;
     $in_UTR     = 1;
   }
   elsif( $in_UTR == 1 ){
     $UTRlength += $exon->length;
   }
 }
 return $UTRlength;

}

=head2 _merge_genes
  Arg [1]    :
  Description: merges adjacent exons if they are frameshifted; stores
               component exons as subSeqFeatures of the merged exon
  Returntype :
  Exceptions :
  Example    :

=cut

sub _merge_genes {
  my ($self, $genesref) = @_;
  my @merged;
  my $count = 1;

 UNMERGED_GENE:
  foreach my $unmerged (@{$genesref}){

    my $gene = new Bio::EnsEMBL::Gene;
    $gene->type('combined');
    $gene->dbID($unmerged->dbID);
    my @pred_exons;
    my $ecount = 0;

    # order is crucial
    my @trans = @{$unmerged->get_all_Transcripts};
    if(scalar(@trans) != 1) { 
      $self->throw("Gene with dbID " . $unmerged->dbID . " has NO or more than one related transcript, where a 1-gene-to-1-transcript-relation is assumed. Check preceding analysis \n"); 
    }

    # check the sanity of the transcript
    next UNMERGED_GENE unless ( Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_check_Transcript($trans[0],$self->query));

    ### we follow here 5' -> 3' orientation ###
#    $trans[0]->sort;

    #print STDERR "checking for merge: ".$trans[0]->dbID."\n";
    #print STDERR "translation:\n";
    #Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_print_Transcript($trans[0]);

    my $cloned_translation = new Bio::EnsEMBL::Translation;

    my @unmerged_exons = @{$trans[0]->get_all_Exons};
    my $strand   = $unmerged_exons[0]->strand; 
    my $previous_exon;

  EXON:
    foreach my $exon(@unmerged_exons){
	
	## genewise frameshift? we merge here two exons separated by max 10 bases into a single exon
	#if ($ecount && $pred_exons[$ecount-1]){
	#  $previous_exon = $pred_exons[$ecount-1];
	#}
	
	$ecount++;
	
	my $separation = 0;
	my $merge_it   = 0;
	
	## we put every exon following a frameshift into the first exon before the frameshift
	## following the ordering 5' -> 3'
	if (defined($previous_exon)){
	
	  #print STDERR "previous exon: ".$previous_exon->start."-".$previous_exon->end."\n";
	  #print STDERR "current exon : ".$exon->start."-".$exon->end."\n";
	  if ($strand == 1){
	    $separation = $exon->start - $previous_exon->end - 1;
	  }
	  elsif( $strand == -1 ){
	    $separation = $previous_exon->end - $exon->start - 1;
	  }
	  if ($separation <=10){
	    $merge_it = 1;
	  }	
	}
	
	if ( defined($previous_exon) && $merge_it == 1){
	  # combine the two
	
	  # the first exon (5'->3' orientation always) is the containing exon,
	  # which gets expanded and the other exons are added into it
	  #print STDERR "merging $exon into $previous_exon\n";
	  #print STDERR $exon->start."-".$exon->end." into ".$previous_exon->start."-".$previous_exon->end."\n";

          if ($strand == 1) {
            $previous_exon->end($exon->end);
          } else {
            $previous_exon->start($exon->start);
          }

	  $previous_exon->add_sub_SeqFeature($exon,'');
	
	  # if this is end of translation, keep that info:
	  if ( $exon == $trans[0]->translation->end_Exon ){
	    $cloned_translation->end_Exon( $previous_exon );
	    $cloned_translation->end($trans[0]->translation->end);
	  }
	
	  my %evidence_hash;
	  foreach my $sf( @{$exon->get_all_supporting_features}){
	    if ( $evidence_hash{$sf->hseqname}{$sf->hstart}{$sf->hend}{$sf->start}{$sf->end} ){
	      next;
	    }
	    #print STDERR $sf->start."-".$sf->end."  ".$sf->hstart."-".$sf->hend."  ".$sf->hseqname."\n";
	    $evidence_hash{$sf->hseqname}{$sf->hstart}{$sf->hend}{$sf->start}{$sf->end} = 1;
	    $previous_exon->add_supporting_features($sf);
	  }
	  next EXON;
	}
	else{
	  # make a new Exon - clone $exon
	  my $cloned_exon = Bio::EnsEMBL::Pipeline::Tools::ExonUtils->_clone_Exon($exon);
	  $cloned_exon->add_sub_SeqFeature($exon,'');
	
	  # if this is start/end of translation, keep that info:
	  if ( $exon == $trans[0]->translation->start_Exon ){
	    $cloned_translation->start_Exon( $cloned_exon );
	    $cloned_translation->start($trans[0]->translation->start);
	  }
	  if ( $exon == $trans[0]->translation->end_Exon ){
	    $cloned_translation->end_Exon( $cloned_exon );
	    $cloned_translation->end($trans[0]->translation->end);
	  }
	
	  $previous_exon = $cloned_exon;
	  push(@pred_exons, $cloned_exon);
	}
      }

    # transcript
    my $merged_transcript   = new Bio::EnsEMBL::Transcript;
    $merged_transcript->dbID($trans[0]->dbID);
    foreach my $pe(@pred_exons){
	$merged_transcript->add_Exon($pe);
    }

    $merged_transcript->sort;
    $merged_transcript->translation($cloned_translation);

  my @seqeds = @{$trans[0]->translation->get_all_SeqEdits};
  if (scalar(@seqeds)) {
    print "Copying sequence edits\n"; 
    foreach my $se (@seqeds) {
      my $new_se =
              Bio::EnsEMBL::SeqEdit->new(
                -CODE    => $se->code,
                -NAME    => $se->name,
                -DESC    => $se->description,
                -START   => $se->start,
                -END     => $se->end,
                -ALT_SEQ => $se->alt_seq
              );
      my $attribute = $new_se->get_Attribute();
      $cloned_translation->add_Attributes($attribute);
    }
  }
  my @support = @{$trans[0]->get_all_supporting_features};
  if (scalar(@support)) {
    $merged_transcript->add_supporting_features(@support);
  }
  $merged_transcript->add_Attributes(@{$trans[0]->get_all_Attributes});
    
    #print STDERR "merged_transcript:\n";
    #Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_print_Transcript($merged_transcript);

    # and gene
    $gene->add_Transcript($merged_transcript);
    push(@merged, $gene);
    $count++;

    # store match between merged and original gene so we can easily retrieve the latter if we need to
    $self->merged_unmerged_pairs($gene,$unmerged);
  } # end UNMERGED_GENE

  return @merged;
}

=head2 combine_genes
  Arg [1]    :
  Description:
  Returntype :
  Exceptions :
  Example    :

=cut

sub combine_genes{
  my ($self, $gw, $e2g) = @_;

  my $modified_peptide = 0;
  my @combined_transcripts  = ();

  # should be only 1 transcript
  my @gw_tran  = @{$gw->get_all_Transcripts};
  $gw_tran[0]->sort;
  my @gw_exons = @{$gw_tran[0]->get_all_Exons}; # ordered array of exons
  my @egtran = @{$e2g->get_all_Transcripts};
  $egtran[0]->sort;
  my @e2g_exons  = @{$egtran[0]->get_all_Exons}; # ordered array of exons

  # OK, let's see if we need a new gene
  # base it on the existing genewise one
  my $newtranscript = new Bio::EnsEMBL::Transcript;
  foreach my $exon(@gw_exons){
    $newtranscript->add_Exon($exon);
  }

  my @support = @{$gw_tran[0]->get_all_supporting_features};
  if (scalar(@support)) {
    $newtranscript->add_supporting_features(@support);
  }
  $newtranscript->add_Attributes(@{$gw_tran[0]->get_all_Attributes});

  my $translation   = new Bio::EnsEMBL::Translation;
  $translation->start($gw_tran[0]->translation->start);
  $translation->end($gw_tran[0]->translation->end);
  $translation->start_Exon($gw_tran[0]->translation->start_Exon);
  $translation->end_Exon($gw_tran[0]->translation->end_Exon);

  my @seqeds = @{$gw_tran[0]->translation->get_all_SeqEdits};
  if (scalar(@seqeds)) {
    print "Copying sequence edits\n"; 
    foreach my $se (@seqeds) {
      my $new_se =
              Bio::EnsEMBL::SeqEdit->new(
                -CODE    => $se->code,
                -NAME    => $se->name,
                -DESC    => $se->description,
                -START   => $se->start,
                -END     => $se->end,
                -ALT_SEQ => $se->alt_seq
              );
      my $attribute = $new_se->get_Attribute();
      $translation->add_Attributes($attribute);
    }
  }

  $newtranscript->translation($translation);
  $newtranscript->translation->start_Exon($newtranscript->start_Exon);
  $newtranscript->translation->end_Exon($newtranscript->end_Exon);

  my $eecount = 0;
  my $modified_peptide_flag;

 EACH_E2G_EXON:
  foreach my $ee (@e2g_exons){

      # check strands are consistent
      if ($ee->strand != $gw_exons[0]->strand){
	  $self->warn("gw and e2g exons have different strands - can't combine genes\n") ;
	  next GENEWISE;
      }

      # single exon genewise prediction?
      if(scalar(@gw_exons) == 1) {
	
	  ($newtranscript, $modified_peptide_flag) = $self->transcript_from_single_exon_genewise( $ee,
												  $gw_exons[0],
												  $newtranscript,
												  $translation,
												  $eecount,
												  @e2g_exons);
      }

      else {
	  ($newtranscript, $modified_peptide_flag) = $self->transcript_from_multi_exon_genewise($ee,
												$newtranscript,
												$translation,
												$eecount,
												$gw,
												$e2g)
	  }
      if ( $modified_peptide_flag ){
	$modified_peptide = 1;
      }

      # increment the exon
      $eecount++;

  } # end of EACH_E2G_EXON

  ##############################
  # expand merged exons
  ##############################

  # the new transcript is made from a merged genewise gene
  # check the transcript and expand frameshifts in all but original 3' gw_exon
  # (the sub_SeqFeatures have been flushed for this exon)
  if (defined($newtranscript)){

      # test
      #print STDERR "before expanding exons, newtranscript: $newtranscript\n"; 
      #$self->_print_Transcript($newtranscript);

      foreach my $ex (@{$newtranscript->get_all_Exons}){

        if($ex->sub_SeqFeature && scalar($ex->sub_SeqFeature) > 1 ){
          my @sf    = sort {$a->start <=> $b->start} $ex->sub_SeqFeature;

          my $first = shift(@sf);

          $ex->end($first->end);

          # add back the remaining component exons
          foreach my $s(@sf){
            $newtranscript->add_Exon($s);
	    $newtranscript->sort;
          }
          # flush the sub_SeqFeatures
          $ex->flush_sub_SeqFeature;
        }
      }

     # unless($self->compare_translations($gw_tran[0], $newtranscript) ){
     #   print STDERR "translation has been modified\n";
     # }

      # check that the result is fine
      unless( Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_check_Transcript($newtranscript, $self->query) ){
        print STDERR "problems with this combined transcript, return undef";
        return undef;
      }
      unless( Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_check_Translation($newtranscript) ){
        print STDERR "problems with this combined translation, return undef";
        return undef;
      }

      # check translation is the same as for the genewise gene we built from
      my $foundtrans = 0;

      # the genewise translation can be modified due to a disagreement in a
      # splice site with cdnas. This can happen as neither blast nor genewise can
      # always find very tiny exons.
      # we then recalculate the translation using genomewise:

      my $newtrans;
      if ( $modified_peptide ){
        my $strand = $newtranscript->start_Exon->strand;

        #print STDERR "before genomewise:\n";
        #      Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_print_Transcript($newtranscript);

        $newtrans = $self->_recalculate_translation($newtranscript, $strand);

        #print STDERR "after genomewise:\n";
        #    Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_print_Transcript($newtrans);
        #      unless($self->compare_translations($gw_tran[0], $newtrans) ){
        #      	print STDERR "translation has been modified\n";
        #      }

        # if the genomewise results gets stop codons, return the original transcript:
        unless( Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_check_Translation($newtrans) ){
          print STDERR "Arrgh, stop codons, returning the original transcript\n";
          $newtrans = $newtranscript;
        }
      }
      else{
        $newtrans = $newtranscript;
      }
      return $newtrans;
    }
  else{
    $self->warn("No combination could be built\n");
    return undef;
  }
}

=head2 transcript_from_single_exon_genewise
  Arg [1]    :
  Description: This method will actually do the combination of both
               cdna and genewise gene.  Note that if there is a match
               on one end but not on the other, the code will extend
               one end, but will leave the other as it is in the
               genewise genes. This will explit cdna matches that look
               fine on one end and we disregard the mismatching part.
  Returntype :
  Exceptions :
  Example    :

=cut

sub transcript_from_single_exon_genewise {
  my ($self, $eg_exon, $gw_exon, $transcript, $translation, $exoncount, @e2g_exons) = @_;

  # save out current translation end - we will need this if we have to unmerge frameshifted exons later
  my $orig_tend = $translation->end;

  # stay with being strict about gw vs e2g coords - may change this later ...
  # the overlapping e2g exon must at least cover the entire gw_exon
  if ($gw_exon->start >= $eg_exon->start && $gw_exon->end <= $eg_exon->end){
	
    my $egstart = $eg_exon->start;
    my $egend   = $eg_exon->end;
    my $gwstart = $gw_exon->start;
    my $gwend   = $gw_exon->end;

    # print STDERR "single exon gene, " . $gw_exon->strand  .  " strand\n";	    
	
    # modify the coordinates of the first exon in $newtranscript
    my $ex = $transcript->start_Exon;
	
    $ex->start($eg_exon->start);
    $ex->end($eg_exon->end);
	
    # need to explicitly set the translation start & end exons here.
    $translation->start_Exon($ex);
	
    # end_exon may be adjusted by 3' coding exon frameshift expansion. Ouch.
    $translation->end_Exon($ex);

    # need to deal with translation start and end this time - varies depending on strand
	
    #FORWARD:
    if($gw_exon->strand == 1){
      my $diff = $gwstart - $egstart;
      my $tstart = $translation->start;
      my $tend = $translation->end;

      #print STDERR "diff: ".$diff." translation start : ".$tstart." end: ".$tend."\n";
      #print STDERR "setting new translation to start: ".($tstart+$diff)." end: ".($tend+$diff)."\n";
      $translation->start($tstart + $diff);
      $translation->end($tend + $diff);

      $self->throw("Forward strand: setting very dodgy translation start: " . $translation->start.  "\n") unless $translation->start > 0;
      $self->throw("Forward strand: setting dodgy translation end: " . $translation->end . " exon_length: " . $translation->end_Exon->length . "\n") unless $translation->end <= $translation->end_Exon->length;
    }

    #REVERSE:
    elsif($gw_exon->strand == -1){
      my $diff   = $egend - $gwend;
      my $tstart = $translation->start;
      my $tend   = $translation->end;
      $translation->start($tstart+$diff);
      $translation->end($tend + $diff);

      $self->throw("Reverse strand: setting very dodgy translation start: " . $translation->start.  "\n") unless $translation->start > 0;
      $self->throw("Reverse strand: setting dodgy translation end: " . $translation->end . " exon_length: " . $translation->end_Exon->length . "\n") unless $translation->end <= $translation->end_Exon->length;
    }
	
    # expand frameshifted single exon genewises back from one exon to multiple exons
    if(scalar($ex->sub_SeqFeature) > 1){
      #print STDERR "frameshift in a single exon genewise\n";
      my @sf = $ex->sub_SeqFeature;
	
      # save current start and end of modified exon
      my $cstart = $ex->start;
      my $cend   = $ex->end;
      my $exlength = $ex->length;
	
      # get first exon - this has same id as $ex
      my $first = shift(@sf);
      $ex->end($first->end); # NB end has changed!!!
      # don't touch start.
      # no need to modify translation start
	
      # get last exon
      my $last = pop(@sf);
      $last->end($cend);
      $transcript->add_Exon($last);
      # and adjust translation end - the end is still relative to the merged gw exon
      $translation->end_Exon($last);
      # put back the original end translation
      $translation->end($orig_tend);
	
      # get any remaining exons
      foreach my $s(@sf){
        $transcript->add_Exon($s);
      }
      $transcript->sort;
      # flush the sub_SeqFeatures
      $ex->flush_sub_SeqFeature;
    }
	
    # need to add back exons, both 5' and 3'
    $self->add_5prime_exons($transcript, $exoncount, @e2g_exons);
    $self->add_3prime_exons($transcript, $exoncount, @e2g_exons);
  }
  return ($transcript,0);
}


=head2 transcript_from_multi_exon_genewise
  Arg [1]    : 
  Description: This method will actually do the combination of both
               cdna and genewise gene.  Note that if there is a match
               on one end but not on the other, the code will extend
               one end, but will leave the other as it is in the
               genewise genes. This will explit cdna matches that look
               fine on one end and we disregard the mismatching part.
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub transcript_from_multi_exon_genewise {
  my ($self, $current_exon, $transcript, $translation, $exoncount, $gw_gene, $eg_gene) = @_;

  # $current_exon is the exon one the e2g_transcript we are in at the moment
  # $exoncount is the position of the e2g exon in the array

  # save out current translation->end - we'll need it if we have to expand 3prime exon later
  # my $orig_tend = $translation->end;

  my @gwtran  = @{$gw_gene->get_all_Transcripts};
  $gwtran[0]->sort;
  my @gwexons = @{$gwtran[0]->get_all_Exons};

  my @egtran  = @{$eg_gene->get_all_Transcripts};
  $egtran[0]->sort;
  my @egexons = @{$egtran[0]->get_all_Exons};

  # in order to match a starting genewise exon with an e2g exon, we need to have
  # a. exactly coinciding exon ends
  # b. exon starts lying within $exon_slop bp of each other.
  # previously we had required e2g start to be strictly <= gw start, but this will lose us some valid UTRs
  # substitute "end" for "start" for 3' ends of transcripts

  # compare to the first genewise exon

  if($gwexons[0]->strand == 1){
    return $self->transcript_from_multi_exon_genewise_forward($current_exon, $transcript, $translation, $exoncount, $gw_gene, $eg_gene);
  }
  elsif( $gwexons[0]->strand == -1 ){
    return $self->transcript_from_multi_exon_genewise_reverse($current_exon, $transcript, $translation, $exoncount, $gw_gene, $eg_gene);
  }
}

=head2 
  Arg [1]    : 
  Description: 
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub transcript_from_multi_exon_genewise_forward{
  my ($self, $current_exon, $transcript, $translation, $exoncount, $gw_gene, $eg_gene) = @_;

  my $modified_peptide = 0;

  my @gwtran  = @{$gw_gene->get_all_Transcripts};
  $gwtran[0]->sort;
  my @gwexons = @{$gwtran[0]->get_all_Exons};

  my @egtran  = @{$eg_gene->get_all_Transcripts};
  $egtran[0]->sort;
  my @egexons = @{$egtran[0]->get_all_Exons};

  # save out current translation->end - we'll need it if we have to expand 3prime exon later
  my $orig_tend = $translation->end;

  my $exon_slop = 20;

  #5_PRIME:
  if (#they have a coincident end
      $gwexons[0]->end == $current_exon->end &&

      # either e2g exon starts before genewise exon
      ($current_exon->start <= $gwexons[0]->start ||

       # or e2g exon is a bit shorter but there are spliced UTR exons as well
       (abs($current_exon->start - $gwexons[0]->start) <= $exon_slop &&
	$current_exon != $egexons[0]))){

    my $current_start = $current_exon->start;
    my $gwstart       = $gwexons[0]->start;

    # this exon will be the start of translation, convention: phase = -1
    my $ex = $transcript->start_Exon;
    $ex->phase(-1);

    # modify the coordinates of the first exon in $newtranscript if
    # e2g is larger on this end than gw.
    if ( $current_exon->start < $gwexons[0]->start ){
      $ex->start($current_exon->start);
    }
    elsif( $current_exon->start == $gwexons[0]->start ){
      $ex->start($gwstart);
      $ex->phase($gwexons[0]->phase);
    }
    # if the e2g exon starts after the gw exon,
    # modify the start only if this e2g exon is not the first of the transcript
    elsif(  $current_start > $gwstart && $exoncount != 0 ) {
      $ex->start($current_exon->start);
    }

    # add all the exons from the est2genome transcript, previous to this one
    Bio::EnsEMBL::Pipeline::Tools::ExonUtils->_transfer_supporting_evidence($current_exon, $ex);
    $self->add_5prime_exons($transcript, $exoncount, @egexons);

    # fix translation start
    if($gwstart >= $current_start){
      # take what it was for the gw gene, and add on the extra
      my $tstart = $translation->start;
      #print STDERR "Forward 5': original translation start: $tstart ";
      $tstart += ($gwstart - $current_start);
      $translation->start($tstart);
      #print STDERR "re-setting translation start to: $tstart\n";
    }

    # only trust a smaller cdna exon if it is not the first of the transcript
    # (it could be a truncated cdna)
    elsif($gwstart < $current_start && $exoncount != 0){

      $modified_peptide = 1;
      #print STDERR "SHORTENING GENEWISE TRANSLATION\n";
      # genewise has leaked over the start. Tougher call - we need to take into account the 
      # frame here as well
      #print STDERR "gw exon starts: $gwstart < new start: $current_start\n";
      #print STDERR "modifying exon, as cdna exon is not the first of transcript-> exoncount = $exoncount\n";

      # $diff is the number of bases we chop from the genewise exon
      my $diff   = $current_start - $gwstart;
      my $tstart = $translation->start;
      $self->warn("this is a case where gw translation starts at $tstart > 1") if ($tstart>1);
      #print STDERR "gw translation start: ".$tstart."\n";
      #print STDERR "start_exon: ".$translation->start_Exon->start.
      #"-".$translation->start_Exon->end.
      #" length: ".($translation->start_Exon->end - $translation->start_Exon->start + 1).
      #" phase: ".$translation->start_Exon->phase.
      #" end_phase: ".$translation->start_Exon->end_phase."\n";

      if($diff % 3 == 0) {
	# we chop exactily N codons from the beginning of translation
	$translation->start(1);
      }
      elsif ($diff % 3 == 1) {
	# we chop N codons plus one base
	$translation->start(3);
      }
      elsif ($diff % 3 == 2) {
	# we chop N codons plus 2 bases
	$translation->start(2);
      }
      else {
	$translation->start(1);
	$self->warn("very odd - $diff mod 3 = " . $diff % 3 . "\n");
      }
    }

    else{
      #print STDERR "gw exon starts: $gwstart > new start: $current_start";
      #print STDERR "but cdna exon is the first of transcript-> exoncount = $exoncount, so we don't modify it\n";
    }
    $self->throw("setting very dodgy translation start: " . $translation->start.  "\n") unless $translation->start > 0;

  } # end 5' exon

  # 3_PRIME:
  elsif (# they have coincident start
	 $gwexons[$#gwexons]->start == $current_exon->start &&
	
	 # either e2g exon ends after genewise exon
	 ($current_exon->end >= $gwexons[$#gwexons]->end ||
	
	  # or we allow to end before if there are UTR exons to be added
	  (abs($current_exon->end - $gwexons[$#gwexons]->end) <= $exon_slop &&
	   $current_exon != $egexons[$#egexons]))){

    my $end_translation_shift = 0;

    # modify the coordinates of the last exon in $newtranscript
    # e2g is larger on this end than gw.
    my $ex = $transcript->end_Exon;

    # this exon is the end of translation, convention: end_phase = -1
    $ex->end_phase(-1);

    if ( $current_exon->end > $gwexons[$#gwexons]->end ){
      $ex->end($current_exon->end);
    }
    elsif( $current_exon->end == $gwexons[$#gwexons]->end ){
      $ex->end($gwexons[$#gwexons]->end);
      $ex->end_phase($gwexons[$#gwexons]->end_phase);
    }
    # if the e2g exon ends before the gw exon,
    # modify the end only if this e2g exon is not the last of the transcript
    elsif ( $current_exon->end < $gwexons[$#gwexons]->end && $exoncount != $#egexons ){
	
      $modified_peptide = 1;
      #print STDERR "SHORTENING GENEWISE TRANSLATION\n";
      ## fix translation end iff genewise has leaked over - will need truncating
      my $diff   = $gwexons[$#gwexons]->end - $current_exon->end;
      #print STDERR "diff: $diff\n";
      my $tend   = $translation->end;

      my $gw_exon_length   = $gwexons[$#gwexons]->end - $gwexons[$#gwexons]->start + 1;
      my $cdna_exon_length = $current_exon->end - $current_exon->start + 1;
      #print STDERR "gw exon length  : $gw_exon_length\n";
      #print STDERR "cdna exon length: $cdna_exon_length\n";

      my $length_diff = $gw_exon_length - $cdna_exon_length;
      #print STDERR "length diff: ".$length_diff."\n"; # should be == diff

      $ex->end($current_exon->end);

      if($diff % 3 == 0) {
	# we chop exactily N codons from the end of the translation
	# so it can end where the cdna exon ends
	$translation->end($cdna_exon_length);
	$end_translation_shift = $length_diff;
      }
      elsif ($diff % 3 == 1) {
	# we chop N codons plus one base
	# it should end on a full codon, so we need to end translation 2 bases earlier:
	$translation->end($cdna_exon_length - 2);
	$end_translation_shift = $length_diff + 2;
      }
      elsif ($diff % 3 == 2) {
	# we chop N codons plus 2 bases
	# it should end on a full codon, so we need to end translation 1 bases earlier:
	$translation->end($cdna_exon_length - 1);
	$end_translation_shift = $length_diff + 1;
      }
      else {
	# absolute genebuild paranoia 8-)
	$translation->end($cdna_exon_length);
	$self->warn("very odd - $diff mod 3 = " . $diff % 3 . "\n");
      }
      #print STDERR "Forward: translation end set to : ".$translation->end."\n";

    }
    # need to explicitly set the translation end exon for translation to work out
    my $end_ex = $transcript->end_Exon;
    $translation->end_Exon($end_ex);

    # strand = 1
    my $expanded = $self->expand_3prime_exon($ex, $transcript, 1);

    if($expanded){
      # set translation end to what it originally was in the unmerged genewise gene
      # taking into account the diff
      #print STDERR "Forward: expanded 3' exon, re-setting end of translation from ".$translation->end." to orig_end ($orig_tend)- ( length_diff + shift_due_to_phases ) ($end_translation_shift)".($orig_tend - $end_translation_shift)."\n";
      $translation->end($orig_tend - $end_translation_shift);
    }

    # finally add any 3 prime e2g exons
    Bio::EnsEMBL::Pipeline::Tools::ExonUtils->_transfer_supporting_evidence($current_exon, $ex);
    $self->add_3prime_exons($transcript, $exoncount, @egexons);

  } # end 3' exon

  return ($transcript,$modified_peptide);
}

=head2 
  Arg [1]    : 
  Description: 
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub transcript_from_multi_exon_genewise_reverse{
  my ($self, $current_exon, $transcript, $translation, $exoncount, $gw_gene, $eg_gene) = @_;

  my $modified_peptide = 0;

  my @gwtran  = @{$gw_gene->get_all_Transcripts};
  $gwtran[0]->sort;
  my @gwexons = @{$gwtran[0]->get_all_Exons};

  my @egtran  = @{$eg_gene->get_all_Transcripts};
  $egtran[0]->sort;
  my @egexons = @{$egtran[0]->get_all_Exons};

  # save out current translation->end - we'll need it if we have to expand 3prime exon later
  my $orig_tend = $translation->end;


  my $exon_slop = 20;

  # 5_PRIME:
  if ($gwexons[0]->start == $current_exon->start &&
      # either e2g exon ends after gw exon
      ($current_exon->end >= $gwexons[0]->end ||
       # or there are UTR exons to be added
       (abs($current_exon->end - $gwexons[0]->end) <= $exon_slop &&
	$current_exon != $egexons[0]))){

    # sort out translation start
    my $tstart = $translation->start;
    if($current_exon->end >= $gwexons[0]->end){
      # take what it was for the gw gene, and add on the extra
      $tstart += $current_exon->end - $gwexons[0]->end;
      $translation->start($tstart);
    }
    elsif( $current_exon->end < $gwexons[0]->end && $current_exon != $egexons[0] ){
      # genewise has leaked over the start. Tougher call - we need to take into account the
      # frame here as well
      $modified_peptide = 1;
      #print STDERR "SHORTENING GENEWISE TRANSLATION\n";
      #print STDERR "In Reverse strand. gw exon ends: ".$gwexons[0]->end." > cdna exon end: ".$current_exon->end."\n";
      #print STDERR "modifying exon, as cdna exon is not the first of transcript-> exoncount = $exoncount\n";

      my $diff = $gwexons[0]->end - $current_exon->end;
      my $gwstart = $gwexons[0]->end;
      my $current_start = $current_exon->end;
      my $tstart = $translation->start;

      #print STDERR "before the modification:\n";
      #print STDERR "start_exon: ".$translation->start_Exon."\n";
      #print STDERR "gw translation start: ".$tstart."\n";
      #print STDERR "start_exon: ".$translation->start_Exon->start.
      #  "-".$translation->start_Exon->end.
      #    " length: ".($translation->start_Exon->end - $translation->start_Exon->start + 1).
      #      " phase: ".$translation->start_Exon->phase.
      #	" end_phase: ".$translation->start_Exon->end_phase."\n";

      if    ($diff % 3 == 0) { $translation->start(1); }
      elsif ($diff % 3 == 1) { $translation->start(3); }
      elsif ($diff % 3 == 2) { $translation->start(2); }
      else {
	$translation->start(1);
	$self->warn("very odd - $diff mod 3 = " . $diff % 3 . "\n");}
    }

    $self->throw("setting very dodgy translation start: " . $translation->start.  "\n") unless $translation->start > 0;

    # this exon is the start of translation, convention: phase = -1
    my $ex = $transcript->start_Exon;
    $ex->phase(-1);

    # modify the coordinates of the first exon in $newtranscript
    if ( $current_exon->end > $gwexons[0]->end){
      $ex->end($current_exon->end);
      $ex->phase(-1);
    }
    elsif (  $current_exon->end == $gwexons[0]->end){
      $ex->end($gwexons[0]->end);
      $ex->phase($gwexons[0]->phase);
    }
    elsif (  $current_exon->end < $gwexons[0]->end && $current_exon != $egexons[0] ){
      $ex->end($current_exon->end);
    }

    # need to explicitly set the translation start exon for translation to work out
    $translation->start_Exon($ex);

    #print STDERR "after the modification:\n";
    #print STDERR "start_Exon: ".$translation->start_Exon."\n";
    #print STDERR "gw translation start: ".$translation->start."\n";
    #print STDERR "start_exon: ".$translation->start_Exon->start.
    #	"-".$translation->start_Exon->end.
    #  " length: ".($translation->start_Exon->end - $translation->start_Exon->start + 1).
    #  " phase: ".$translation->start_Exon->phase.
    #      " end_phase: ".$translation->start_Exon->end_phase."\n";

    Bio::EnsEMBL::Pipeline::Tools::ExonUtils->_transfer_supporting_evidence($current_exon, $ex);
    $self->add_5prime_exons($transcript, $exoncount, @egexons);

  }
  # end 5' exon

  # 3_PRIME:
  elsif ($gwexons[$#gwexons]->end == $current_exon->end &&
	 # either e2g exon starts before gw exon
	 ($current_exon->start <= $gwexons[$#gwexons]->start ||
	  # or there are UTR exons to be added
	  (abs($current_exon->start - $gwexons[$#gwexons]->start) <= $exon_slop &&
	   $current_exon != $egexons[$#egexons]))){
    my $end_translation_shift = 0;

    # this exon is the end of translation, convention: end_phase = -1
    my $ex = $transcript->end_Exon;
    $ex->end_phase(-1);

    # modify the coordinates of the last exon in $newtranscript
    if ( $current_exon->start < $gwexons[$#gwexons]->start ){
      # no need to modify translation->end as the 'end' of this exon has not changed
      $ex->start($current_exon->start);
      $ex->end_phase(-1);
    }
    elsif( $current_exon->start == $gwexons[$#gwexons]->start){
      $ex->start($gwexons[$#gwexons]->start);
      $ex->end_phase($gwexons[$#gwexons]->end_phase);
    }

    # if the e2g exon starts after the gw exon,
    # modify the end only if this e2g exon is not the last of the transcript
    elsif ( $current_exon->start > $gwexons[$#gwexons]->start && $exoncount != $#egexons ){

      $modified_peptide = 1;
      #print STDERR "SHORTENING GENEWISE TRANSLATION\n";
      #print STDERR "In Reverse strand: gw exon start: ".$gwexons[$#gwexons]->start." < cdna exon start: ".$current_exon->start."\n";
      #print STDERR "modifying exon, as cdna exon is not the last of transcript-> exoncount = $exoncount, and #egexons = $#egexons\n";

      ## adjust translation
      my $diff   = $current_exon->start - $gwexons[$#gwexons]->start;
      #print STDERR "diff: $diff\n";
      my $tend   = $translation->end;
	
      my $gw_exon_length   = $gwexons[$#gwexons]->end - $gwexons[$#gwexons]->start + 1;
      my $cdna_exon_length = $current_exon->end - $current_exon->start + 1;
      #print STDERR "gw exon length  : $gw_exon_length\n";
      #print STDERR "cdna exon length: $cdna_exon_length\n";
	
      my $length_diff = $gw_exon_length - $cdna_exon_length;

      # modify the combined exon coordinate to be that of the cdna
      $ex->start($current_exon->start);

      if($diff % 3 == 0) {
	# we chop exactily N codons from the end of the translation
	# so it can end where the cdna exon ends
	$translation->end($cdna_exon_length);
	$end_translation_shift = $length_diff;
      }
      elsif ($diff % 3 == 1) {
	# we chop N codons plus one base
	# it should end on a full codon, so we need to end translation 2 bases earlier:
	$translation->end($cdna_exon_length - 2);
	$end_translation_shift = $length_diff + 2;
      }
      elsif ($diff % 3 == 2) {
	# we chop N codons plus 2 bases
	# it should end on a full codon, so we need to end translation 1 bases earlier:
	$translation->end($cdna_exon_length - 1);
	$end_translation_shift = $length_diff + 1;
      }
      else {
	# absolute genebuild paranoia 8-)
	$translation->end($cdna_exon_length);
	$self->warn("very odd - $diff mod 3 = " . $diff % 3 . "\n");
      }
      #print STDERR "Reverse: translation end set to : ".$translation->end."\n";

      }	
      # strand = -1
      my $expanded = $self->expand_3prime_exon($ex, $transcript, -1);

      # need to explicitly set the translation end exon for translation to work out
      my $end_ex = $transcript->end_Exon;
      $translation->end_Exon($end_ex);

      if($expanded){
	# set translation end to what it originally was in the unmerged genewise gene
	#print STDERR "Reverse: expanded 3' exon, re-setting translation exon ".$translation->end." to original end( $orig_tend ) - shifts_due_to_phases_etc ( $end_translation_shift ) :".($orig_tend - $end_translation_shift)."\n";
	$translation->end($orig_tend - $end_translation_shift);
      }
      Bio::EnsEMBL::Pipeline::Tools::ExonUtils->_transfer_supporting_evidence($current_exon, $ex);
      $self->add_3prime_exons($transcript, $exoncount, @egexons);

    } # end 3' exon

  return ($transcript,$modified_peptide);
}

=head2 
  Arg [1]    : 
  Description: 
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub add_5prime_exons{
  my ($self, $transcript, $exoncount, @e2g_exons) = @_;

  # add all the exons from the est2genome transcript, previous to this one
  # db handle will be screwed up, need to mak new exons from these
  my $c = 0;
  my $modified = 0;
  while($c < $exoncount){
    my $newexon = new Bio::EnsEMBL::Exon;
    my $oldexon = $e2g_exons[$c];
    $newexon->start($oldexon->start);
    $newexon->end($oldexon->end);
    $newexon->strand($oldexon->strand);

    # these are all 5prime UTR exons
    $newexon->phase(-1);
    $newexon->end_phase(-1);
    $newexon->slice($oldexon->slice);
    my %evidence_hash;
    #print STDERR "adding evidence at 5':\n";
    foreach my $sf( @{$oldexon->get_all_supporting_features} ){
      if ( $evidence_hash{$sf->hseqname}{$sf->hstart}{$sf->hend}{$sf->start}{$sf->end} ){
	next;
      }
      $evidence_hash{$sf->hseqname}{$sf->hstart}{$sf->hend}{$sf->start}{$sf->end} = 1;
      #print STDERR $sf->start."-".$sf->end."  ".$sf->hstart."-".$sf->hend."  ".$sf->hseqname."\n";
      $newexon->add_supporting_features($sf);
    }
    #	print STDERR "Adding 5prime exon " . $newexon->start . " " . $newexon->end . "\n";
    $transcript->add_Exon($newexon);
    $modified = 1;
    $c++;
  }

  if ($modified == 1){
    $transcript->translation->start_Exon->phase(-1);
  }
}

# $exon is the terminal exon in the genewise transcript, $transcript. We need
# to expand any frameshifts we merged in the terminal genewise exon. 
# The expansion is made by putting $exon to be the last (3' end) component, so we modify its
# start but not its end. The rest of the components are added. The translation end will have to be modified,
# this happens in the method _transcript_from_multi_exon....

=head2 
  Arg [1]    : 
  Description: $exon is the terminal exon in the genewise transcript,
               $transcript. We need to expand any frameshifts we
               merged in the terminal genewise exon.  The expansion is
               made by putting $exon to be the last (3 end)
               component, so we modify its start but not its end. The
               rest of the components are added. The translation end
               will have to be modified, this happens in the method
               _transcript_from_multi_exon....


  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub expand_3prime_exon{
  my ($self, $exon, $transcript, $strand) = @_;

  if(scalar($exon->sub_SeqFeature) > 1){
    #print STDERR "expanding 3'prime frameshifted exon $exon in strand $strand: ".
    #$exon->start."-".$exon->end." phase: ".$exon->phase." end_phase: ".$exon->end_phase."\n";
    my @sf = $exon->sub_SeqFeature;

    my $last = pop(@sf);
    #print STDERR "last component: ".$last->start."-".$last->end." phase ".$last->phase." end_phase ".$last->end_phase."\n";

    #print STDERR "setting exon $exon start: ".$last->start." phase: ".$last->phase."\n";  
    $exon->start($last->start); # but don't you dare touch the end!
    $exon->dbID($last->dbID);
    $exon->phase($last->phase);

    # add back the remaining component exons
    foreach my $s(@sf){
      #print STDERR "adding exon: ".$s->start."-".$s->end."\n";
      $transcript->add_Exon($s);
      $transcript->sort;
    }
    # flush the sub_SeqFeatures so we don't try to re-expand later
    $exon->flush_sub_SeqFeature;
    return 1;
  }

  # else, no expansion
  return 0;
}

=head2 
  Arg [1]    : 
  Description: $exoncount tells us which position in the array of e2g
               exons corresponds to the end of the genewise transcript
               so we add back exons 3 to that position.  $exon and
               $transcript are references to Exon and Transcript
               objects.

  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub add_3prime_exons {
  my ($self, $transcript, $exoncount, @e2g_exons) = @_;
  # need to deal with frameshifts - 3' exon is a special case as its end might have changed

  # add all the exons from the est2genome transcript, subsequent to this one
  my $c = $#e2g_exons;
  my $modified = 0;
  while($c > $exoncount){
    my $newexon = new Bio::EnsEMBL::Exon;
    my $oldexon = $e2g_exons[$c];
    $newexon->start($oldexon->start);
    $newexon->end($oldexon->end);
    $newexon->strand($oldexon->strand);
	
    # these are all exons with UTR:
    $newexon->phase(-1);
    $newexon->end_phase(-1);
    $newexon->slice($oldexon->slice);
    #print STDERR "adding evidence in 3':\n";
    my %evidence_hash;
    foreach my $sf( @{$oldexon->get_all_supporting_features }){
      if ( $evidence_hash{$sf->hseqname}{$sf->hstart}{$sf->hend}{$sf->start}{$sf->end} ){
	next;
      }
      $evidence_hash{$sf->hseqname}{$sf->hstart}{$sf->hend}{$sf->start}{$sf->end} = 1;
      #print STDERR $sf->start."-".$sf->end."  ".$sf->hstart."-".$sf->hend."  ".$sf->hseqname."\n";
      $newexon->add_supporting_features($sf);
    }
    #	print STDERR "Adding 3prime exon " . $newexon->start . " " . $newexon->end . "\n";
    $transcript->add_Exon($newexon);
    $modified = 1;
    $c--;
  }

  if ($modified == 1){
    $transcript->translation->end_Exon->end_phase(-1);
  }
}

=head2 compare_translations

  Arg [1]    : 
  Description: it compares the peptides from two transcripts.
               It returns 1 if both translations are the same or when
               one is a truncated version of the other. It returns 0 otherwise.
               Also returns 0 if either of the transcripts has stops.
  ReturnType : BOOLEAN
  Exceptions : 
  Example    : 
 
=cut

sub compare_translations{
  my ($self, $genewise_transcript, $combined_transcript) = @_;

  my $seqout = new Bio::SeqIO->new(-fh => \*STDERR);

  my $genewise_translation;
  my $combined_translation;

  eval {
    $genewise_translation = $genewise_transcript->translate;
  };
  if ($@) {
    print STDERR "Couldn't translate genewise gene\n";
  }
  else{
    #print STDERR "genewise: \n";             
    $seqout->write_seq($genewise_translation);
    #Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_print_Translation($genewise_transcripts[0]);
  }

  $@ = '';

  eval{
    $combined_translation = $combined_transcript->translate;
  };

  if ($@) {
    print STDERR "Couldn't translate combined gene:[$@]\n";
    return 0;
  }
  else{
    $seqout->write_seq($combined_translation);
  }

  if ( $genewise_translation && $combined_translation ){
    my $gwseq  = $genewise_translation->seq;
    my $comseq = $combined_translation->seq;

    if($gwseq eq $comseq) {
      #print STDERR "combined translation is identical to genewise translation\n";
      return 1;
    }
    elsif($gwseq =~ /$comseq/){
      #print STDERR "combined translation is a truncated version of genewise translation\n";
      return 1;
    }
    elsif($comseq =~ /$gwseq/){
      #print STDERR "interesting: genewise translation is a truncated version of the combined-gene translation\n";
      return 1;
    }
  }

  return 0;
}

#VAC< strictly speaking this is no longer remapping anything

=head2 
  Arg [1]    : 
  Description: 
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub remap_genes {
  my ($self) = @_;
  my @newf;
  my $slice = $self->query;

  my @genes = @{$self->combined_genes};
  push(@genes, $self->unmatched_genes);

  my $genecount = 0;
 GENE:
  foreach my $gene (@genes) {
    $genecount++;
    my @t = @{$gene->get_all_Transcripts};
    my $tran = $t[0];

    # check that it translates
    unless(Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_check_Translation($tran)){
      next GENE;
    }

    my $transcount = 0;
    foreach my $transcript ( @{$gene->get_all_Transcripts} ){
      $transcount++;
      $transcript->type( $genecount."_".$transcount );

      # set start and stop codons
      $transcript = Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->set_start_codon($transcript);
      $transcript = Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->set_stop_codon($transcript);
    }
  }
  return @genes;
}


=head2 validate_gene
  Arg [1]    : Bio::EnsEMBL::Gene
  Description: checks start and end coordinates of each exon of each transcript are sane 
  Returntype : 1 if gene is valid, otherwise zero
  Exceptions : 
  Example    : $self->validate_gene($gene) 
 
=cut

sub validate_gene{
  my ($self, $gene) = @_;

  # should be only a single transcript
  my @transcripts = @{$gene->get_all_Transcripts};
  if(scalar(@transcripts) != 1) {
    my $msg = "Rejecting gene - should have one transcript, not " . scalar(@transcripts) . "\n";
    $self->warn($msg);
    return 0;
  }

  foreach my $transcript(@transcripts){
    foreach my $exon(@{$transcript->get_all_Exons}){
      unless ( Bio::EnsEMBL::Pipeline::Tools::ExonUtils->_validate_Exon($exon)){
	my $msg = "Rejecting gene because of invalid exon\n";
	$self->warn($msg);
	return 0;
      }
    }
  }

  return 1;
}

=head2 _recalculate_translation
 
 Arg[1]      : Bio::EnsEMBL::Transcript
 Arg[2]      : the strand where the transcript sits
 Description : a transcript is used as evidence for genomewise
              to recalculate the ORF. The idea is to use this when
              the peptide has been shortened, due to a genewise model
              being incompatible with the cdna splicing. This can happen when 
              genewise cannot find very short exons
              and attaches them to one of the flanking exons.
              We tell genomewise to keep the splice boundaries pretty much
              static, so that we preserve the original splicing structure.
 Returntype  : Bio::EnsEMBL::Transcript
  Exceptions : 
  Example    : 

=cut

sub _recalculate_translation{
  my ($self, $mytranscript, $strand) = @_;

  my $this_is_my_transcript = Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_clone_Transcript($mytranscript);

  my $slice = $self->query;

  Bio::EnsEMBL::Pipeline::Tools::TranslationUtils->compute_translation($mytranscript);

  # check that everything is sane:
  unless (Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_check_Translation($mytranscript)){
    print STDERR "problem with the translation. Returning the original transcript\n";
    return $this_is_my_transcript;
  }
  return $mytranscript;
}


=head2 
  Arg [1]    : 
  Description: 
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub _recalculate_translation_old {
  my ($self, $mytranscript, $strand) = @_;

  my $this_is_my_transcript = Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_clone_Transcript($mytranscript);
  my $transcript;

  my $slice = $self->query;
  my $inverted_slice = $slice->invert;

  # the genomic sequence to be used with Genomewise (a PrimarySeq)

  # genomewise doesn't know about strands, we need to put everything in forward strand:
  my $genomic_sequence;

  if ( $strand == -1 ){
    $genomic_sequence = $inverted_slice;

    my $mygene               = Bio::EnsEMBL::Gene->new();
    $mygene->add_Transcript($mytranscript);
    my $gene                 = $mygene->transform($inverted_slice);
    my @inverted_transcripts = @{$gene->get_all_Transcripts};
    $transcript              = $inverted_transcripts[0];

  }
  else{
    $transcript       = $mytranscript;
    $genomic_sequence = $slice;
  }

  my @transcripts;
  push(@transcripts,$transcript);

  my $runnable = Bio::EnsEMBL::Pipeline::Runnable::MiniGenomewise->new(
								       -genomic     => $genomic_sequence,
								       -transcripts => \@transcripts,
								       -smell       => 0,
								      );
  eval{
      $runnable->run;
  };
  if ($@){
    print STDERR $@;
  }
  my @trans = $runnable->output;

  unless ( scalar(@trans) == 1 ){
    $self->warn("Something went wrong running Genomewise. Got ".scalar(@trans).
		" transcripts. returning without modifying the translation\n");
    return $mytranscript;
  }

  my $newtranscript;
  # if in the reverse strand, put it back in the original slice
  if ( $strand == -1 ){
    my $gene = Bio::EnsEMBL::Gene->new();
    $gene->add_Transcript($trans[0]);
    my $newgene        = $gene->transform($slice);
    my @newtranscripts = @{$newgene->get_all_Transcripts};
    $newtranscript     = $newtranscripts[0];
  }
  else{
    $newtranscript = $trans[0];
  }

  # check that everything is sane:
  unless (Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_check_Translation($newtranscript)){
    print STDERR "problem with the translation. Returning the original transcript\n";
    return $this_is_my_transcript;
  }
  return $newtranscript;
}

=head2 _transfer_evidence

  
  Arg [1]    : reference to Bio::EnsEMBL::Tanscript $combined_transcript
  Arg [2]    : reference to Bio::EnsEMBL::Transcript $cdna_transcript
  Description: transfers cdna evidence to combined transcript
  Returntype: Bio::EnsEMBL::Transcript
  Exceptions : 
  Example    : 
           
=cut 

sub _transfer_evidence {
  my ($self, $combined_transcript, $cdna_transcript) = @_;

  my $first_support_id;
  foreach my $combined_exon(@{$combined_transcript->get_all_Exons}){
    foreach my $cdna_exon(@{$cdna_transcript->get_all_Exons}){
      # exact match or overlap?

# exact match
#
#      if($combined_exon->start == $cdna_exon->start &&
#         $combined_exon->end == $cdna_exon->end &&
#         $combined_exon->strand == $cdna_exon->strand){
#         print STDERR "exact match " . $combined_exon->dbID . " with " . $cdna_exon->dbID . "; transferring evidence\n";
#         Bio::EnsEMBL::Pipeline::Tools::ExonUtils-> _transfer_supporting_evidence($cdna_exon, $combined_exon);
#      }

      # overlap - feature boundaries may well be wonky
      if($combined_exon->overlaps($cdna_exon)){
	Bio::EnsEMBL::Pipeline::Tools::ExonUtils-> _transfer_supporting_evidence($cdna_exon, $combined_exon);
      }
    }
  }

  my $cdna_trans = $cdna_transcript->get_all_Transcripts()->[0];
  foreach my $tsf (@{$cdna_trans->get_all_supporting_features}) {
    $combined_transcript->add_supporting_features($tsf);
  }
  return $combined_transcript;
}


#
# GET/SET METHODS
#

=head2 forward_genewise_clusters
  Arg [1]    : 
  Description: get/set for genewise clusters
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub forward_genewise_clusters{
  my ($self, $cluster_ref) = @_;
  if (!defined($self->{'_forward_genewise_clusters'})) {
    $self->{'_forward_genewise_clusters'} = [];
  }

  if (defined $cluster_ref && scalar(@{$cluster_ref})) {
    push(@{$self->{'_forward_genewise_clusters'}},@{$cluster_ref});
    # store them sorted
    @{$self->{'_forward_genewise_clusters'}} = sort { $a->start <=> $b->start } @{$self->{'_forward_genewise_clusters'}};
  }

  return $self->{'_forward_genewise_clusters'};
}

=head2 reverse_genewise_clusters
  Arg [1]    : 
  Description: get/set for genewise clusters
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub reverse_genewise_clusters{
  my ($self, $cluster_ref) = @_;
  if (!defined($self->{'_reverse_genewise_clusters'})) {
    $self->{'_reverse_genewise_clusters'} = [];
  }

  if (defined $cluster_ref && scalar(@{$cluster_ref})) {
    push(@{$self->{'_reverse_genewise_clusters'}},@{$cluster_ref});
    # store them sorted
    @{$self->{'_reverse_genewise_clusters'}} = sort { $a->start <=> $b->start } @{$self->{'_reverse_genewise_clusters'}};
  }

  return $self->{'_reverse_genewise_clusters'};
}


=head2 cdna_genes
  Arg [1]    : 
  Description: get/set for e2g gene array
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub cdna_genes {
  my ($self, $genes) = @_;

  if (!defined($self->{'_cdna_genes'})) {
    $self->{'_cdna_genes'} = [];
  }

  if (defined $genes && scalar(@{$genes})) {
    push(@{$self->{'_cdna_genes'}},@{$genes});
  }

  return @{$self->{'_cdna_genes'}};
}


=head2 ditags
  Arg [1]    : ref to array with ditags
  Description: get/set ditags
  Returntype : 
  Exceptions : 
  Example    : 
=cut

sub ditags {
  my ($self, $ditags) = @_;

  if (!defined($self->{'_ditags'})) {
    $self->{'_ditags'} = [];
  }

  if (defined $ditags && scalar(@{$ditags})) {
    push(@{$self->{'_ditags'}},@{$ditags});
  }

  return @{$self->{'_ditags'}};
}


=head2 gw_genes
  Arg [1]    : 
  Description: get/set for genewise gene array
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub gw_genes {
  my ($self, $genes) = @_;
  if (!defined($self->{'_gw_genes'})) {
    $self->{'_gw_genes'} = [];
  }

  if (defined $genes && scalar(@{$genes})) {
    push(@{$self->{'_gw_genes'}},@{$genes});
  }

  return $self->{'_gw_genes'};
}

=head2 blessed_genes
  Arg [1]    : 
  Description: get/set for blessed gene array
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub blessed_genes {
  my ($self, $slice, $genes) = @_;
  if (!defined($self->{'_blessed_genes'})) {
    $self->{'_blessed_genes'} = [];
  }

  if (defined $slice && defined $genes && scalar(@{$genes})) {

    # split input genes into one transcript per gene; keep type the same
  OLDGENE:
    foreach my $gene(@{$genes}){
      foreach my $transcript(@{$gene->get_all_Transcripts}){

	# check transcript sanity
	next OLDGENE unless ( Bio::EnsEMBL::Pipeline::Tools::TranscriptUtils->_check_Transcript($transcript,$self->query));

	# make a new gene
	my $newgene = new Bio::EnsEMBL::Gene;
	$newgene->type($gene->type);

	# clone transcript
	my $newtranscript = new Bio::EnsEMBL::Transcript;
	$newtranscript->slice($slice);

	# clone translation
	my $newtranslation = new Bio::EnsEMBL::Translation;
        my @seqeds = @{$transcript->translation->get_all_SeqEdits};
        if (scalar(@seqeds)) {
          print "Copying sequence edits\n"; 
          foreach my $se (@seqeds) {
            my $new_se =
              Bio::EnsEMBL::SeqEdit->new(
                -CODE    => $se->code,
                -NAME    => $se->name,
                -DESC    => $se->description,
                -START   => $se->start,
                -END     => $se->end,
                -ALT_SEQ => $se->alt_seq
              );
            my $attribute = $new_se->get_Attribute();
            $newtranslation->add_Attributes($attribute);
          }
        }
        my @support = @{$transcript->get_all_supporting_features};
        if (scalar(@support)) {
          $newtranscript->add_supporting_features(@support);
        }
        $newtranscript->add_Attributes(@{$transcript->get_all_Attributes});

	$newtranscript->translation($newtranslation);

	foreach my $exon(@{$transcript->get_all_Exons}){
	  # clone the exon
	  my $newexon = Bio::EnsEMBL::Pipeline::Tools::ExonUtils->_clone_Exon($exon);
	  # get rid of stable ids
	  $newexon->stable_id('');

	  # if this is start/end of translation, keep that info:
	  if ( $exon == $transcript->translation->start_Exon ){
		$newtranslation->start_Exon( $newexon );
		$newtranslation->start($transcript->translation->start);
	    }
	    if ( $exon == $transcript->translation->end_Exon ){
		$newtranslation->end_Exon( $newexon );
		$newtranslation->end($transcript->translation->end);
	    }
	  $newtranscript->add_Exon($newexon);
	}

	$newgene->add_Transcript($newtranscript);
	push(@{$self->{'_blessed_genes'}}, $newgene);	
	
      }
    }
  }

  return $self->{'_blessed_genes'};
}

=head2 
  Arg [1]    : combined_genes
  Description: get/set for combined gene array
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub combined_genes {
  my ($self, $genesref) = @_;

  if (!defined($self->{'_combined_genes'})) {
    $self->{'_combined_genes'} = [];
  }

  if (defined $genesref && scalar(@{$genesref})) {
    push(@{$self->{'_combined_genes'}},@{$genesref});
  }

  return $self->{'_combined_genes'};
}

=head2 unmatched_genes
  Arg [1]    : 
  Description: get/set for unmatched gene array
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub unmatched_genes {
  my ($self, @genes) = @_;

  if (!defined($self->{'_unmatched_genes'})) {
    $self->{'_unmatched_genes'} = [];
  }

    push(@{$self->{'_unmatched_genes'}},@genes);


  return @{$self->{'_unmatched_genes'}};
}


=head2 retrieve_unmerged_gene
  Arg [1]    : Bio::EnsEMBL::Gene
  Description: Returns unmeregd, frameshifted version of input gene
  Returntype : Bio::EnsEMBL::Gene
  Exceptions : 
  Example    : 
 
=cut

sub retrieve_unmerged_gene{
  my ($self, $merged_gene) = @_;

  my %pairs = %{$self->merged_unmerged_pairs()};
  return $pairs{$merged_gene};
}

=head2 merged_unmerged_pairs
  Arg [1]    : 
  Description: get/set for pairs of frameshift merged and unmerged
               genes. Key is merged gene, value is unmerged

  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub merged_unmerged_pairs {
  my ($self, $merged_gene, $unmerged_gene) = @_;

  if (!defined($self->{'_merged_unmerged_pairs'})) {
    $self->{'_merged_unmerged_pairs'} = {};
  }

  if ($unmerged_gene && $merged_gene) {
    $self->{'_merged_unmerged_pairs'}{$merged_gene}= $unmerged_gene;
  }

  # hash ref
  return $self->{'_merged_unmerged_pairs'};
}

=head2 modified_unmodified_pairs
  Arg [1]    : 
  Description: get/set for pairs of UTR modified and unmodified genes.
               Key is modified gene, value is unmodified

  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub modified_unmodified_pairs {
  my ($self, $modified_gene, $unmodified_gene) = @_;

  if (!defined($self->{'_modified_unmodified_pairs'})) {
    $self->{'_modified_unmodified_pairs'} = {};
  }

  if ($unmodified_gene && $modified_gene) {
    $self->{'_modified_unmodified_pairs'}{$modified_gene}= $unmodified_gene;
  }

  # hash ref
  return $self->{'_modified_unmodified_pairs'};
}

=head2 output
  Arg [1]    : 
  Description: 
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub output{
  my ($self,@genes) = @_;

  if (!defined($self->{'_output'})) {
    $self->{'_output'} = [];
  }

  if(@genes){
    push(@{$self->{'_output'}},@genes);
  }

  return @{$self->{'_output'}};
}

=head2 cdna_db
  Arg [1]    : 
  Description: get/set for db storing exonerate alignments of cDNAs 
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub cdna_db {
    my( $self, $cdna_db ) = @_;

    if ($cdna_db){
      $cdna_db->isa("Bio::EnsEMBL::DBSQL::DBAdaptor")
        || $self->throw("Input [$cdna_db] isn't a ".
                        "Bio::EnsEMBL::DBSQL::DBAdaptor");
      $self->{_cdna_db} = $cdna_db;
    }
    if(!$self->{_cdna_db}){
      $self->{_cdna_db} = new Bio::EnsEMBL::DBSQL::DBAdaptor
        (
         '-host'   => $GB_cDNA_DBHOST,
         '-user'   => $GB_cDNA_DBUSER,
         '-pass'   => $GB_cDNA_DBPASS,
         '-port'   => $GB_cDNA_DBPORT,
         '-dbname' => $GB_cDNA_DBNAME,
         '-dnadb' => $self->db,
        ); 
    }
    return $self->{_cdna_db};
}

=head2 est_db
  Arg [1]    : 
  Description: get/set for db storing exonerate alignments of ESTs 
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub est_db {
    my( $self, $est_db ) = @_;

    if ($est_db){
      $est_db->isa("Bio::EnsEMBL::DBSQL::DBAdaptor")
        || $self->throw("Input [$est_db] isn't a ".
                        "Bio::EnsEMBL::DBSQL::DBAdaptor");
      $self->{_est_db} = $est_db;
    }
    if(!$self->{_est_db}){
      $self->{_est_db} = new Bio::EnsEMBL::DBSQL::DBAdaptor
        (
         '-host'   => $GB_EST_DBHOST,
         '-user'   => $GB_EST_DBUSER,
         '-pass'   => $GB_EST_DBPASS,
         '-port'   => $GB_EST_DBPORT,
         '-dbname' => $GB_EST_DBNAME,
         '-dnadb' => $self->db,
        );
    }
    return $self->{_est_db};
}


=head2 ditag_db
  Arg [1]    : 
  Description: get/set for db storing exonerate alignments of ditags
  Returntype : 
  Exceptions : 
  Example    : 

=cut

sub ditag_db {
    my( $self, $ditag_db ) = @_;

    if ($ditag_db){
      $ditag_db->isa("Bio::EnsEMBL::DBSQL::DBAdaptor")
        || $self->throw("Input [$ditag_db] isn't a ".
                        "Bio::EnsEMBL::DBSQL::DBAdaptor");
      $self->{_ditag_db} = $ditag_db;
    }
    if(!$self->{_ditag_db}){
      $self->{_ditag_db} = new Bio::EnsEMBL::DBSQL::DBAdaptor
        (
         '-host'   => $DITAG_DBHOST,
         '-user'   => $DITAG_DBUSER,
         '-pass'   => $DITAG_DBPASS,
         '-port'   => $DITAG_DBPORT,
         '-dbname' => $DITAG_DBNAME,
         '-dnadb'  => $self->db,
        );
    }
    if(!$self->{_ditag_db}){
      $self->throw("Could not create DitagDB-Adaptor!\n");
    }

    return $self->{_ditag_db};
}


=head2 genewise_db
  Arg [1]    : 
  Description: get/set for db storing genewise alignments
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub genewise_db {
    my( $self, $genewise_db ) = @_;

    if ($genewise_db){
      $genewise_db->isa("Bio::EnsEMBL::DBSQL::DBAdaptor")
        || $self->throw("Input [$genewise_db] isn't a ".
                        "Bio::EnsEMBL::DBSQL::DBAdaptor");
      $self->{_genewise_db} = $genewise_db;
    }
    if(!$self->{_genewise_db}){
      $self->{_genewise_db} = new Bio::EnsEMBL::DBSQL::DBAdaptor
        (
         '-host'   => $GB_GW_DBHOST,
         '-user'   => $GB_GW_DBUSER,
         '-pass'   => $GB_GW_DBPASS,
         '-port'   => $GB_GW_DBPORT,
         '-dbname' => $GB_GW_DBNAME,
         '-dnadb' => $self->db,
        );
    }
    return $self->{_genewise_db};
}

=head2 blessed_db
  Arg [1]    : 
  Description: get/set for db storing blessed gene structures
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub blessed_db {
    my( $self, $blessed_db ) = @_;

    if ($blessed_db){
      $blessed_db->isa("Bio::EnsEMBL::DBSQL::DBAdaptor")
        || $self->throw("Input [$blessed_db] isn't a ".
                        "Bio::EnsEMBL::DBSQL::DBAdaptor");
      $self->{_blessed_db} = $blessed_db;
    }
    if(!$self->{_blessed_db}){
      if($GB_BLESSED_DBHOST && $GB_BLESSED_DBNAME) {
	$self->{_blessed_db} = new Bio::EnsEMBL::DBSQL::DBAdaptor
          (
           '-host'   => $GB_BLESSED_DBHOST,
           '-user'   => $GB_BLESSED_DBUSER,
           '-pass'   => $GB_BLESSED_DBPASS,
           '-port'   => $GB_BLESSED_DBPORT,
           '-dbname' => $GB_BLESSED_DBNAME,
           '-dnadb' => $self->db,
          );
      }
    }

    return $self->{_blessed_db};
}

=head2 output_db
  Arg [1]    : 
  Description: get/set for db in which UTR modified genes should be stored
  Returntype : 
  Exceptions : 
  Example    : 
 
=cut

sub output_db {
    my( $self, $output_db ) = @_;

    if ($output_db){
      $output_db->isa("Bio::EnsEMBL::DBSQL::DBAdaptor")
        || $self->throw("Input [$output_db] isn't a ".
                        "Bio::EnsEMBL::DBSQL::DBAdaptor");
      $self->{_output_db} = $output_db;
    }
    if(!$self->{_output_db}){
      $self->{_output_db} =  new Bio::EnsEMBL::DBSQL::DBAdaptor
        (
         '-host'   => $GB_COMB_DBHOST,
         '-user'   => $GB_COMB_DBUSER,
         '-pass'   => $GB_COMB_DBPASS,
         '-port'   => $GB_COMB_DBPORT,
         '-dbname' => $GB_COMB_DBNAME,
         '-dnadb' => $self->db,
        ); 
    }
    return $self->{_output_db};
}




1;
