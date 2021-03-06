use lib 't';
use Test;
use strict;

BEGIN { $| = 1; plan test => 8;
      }

use Bio::EnsEMBL::Pipeline::Runnable::EPCR;
use Bio::PrimarySeq;
use Bio::Seq;
use Bio::SeqIO;


ok(1);

ok(my $seq =  set_seq());

ok(my $clone =  Bio::PrimarySeq->new(
				     -seq         => $seq,
				     -id          => 'AC025422.19.99723.113695',
				     -accession   => 'AC025422.19.99723.113695',
				     -moltype     => 'dna'
				    ));

#create EPCR object    
ok(my $sts_db = 'HSa_Marker_W7.dat');

ok(my $epcr = Bio::EnsEMBL::Pipeline::Runnable::EPCR->new(
							  -QUERY   => $clone,
							  -STS     => $sts_db,
							  -OPTIONS => 'M=1000'
							 ));
 
ok($epcr->run);

ok(my @results = $epcr->output);

ok(display (@results));


sub display {
  my @results = @_;

  foreach my $obj (@results) {
    print STDERR ($obj->gffstring."\n");
  }
  return 1;
}

sub set_seq {
#embedded sequence! Because I can't create Bio::PrimarySeqs from files
my $seq = 
'TCCTTTAGTCCTTACATCTCTATGAGTTAGGTATAAGGCATTTGAAAAATAAGAAGACAG'.
'AGGTAAGGCAGAGCAGTGATTTGCCCAGGGTTAGGCAGCTTGAGAGTGATGGAGCGAGGA'.
'TGTAACTCCTGAACAATCTAGCTTGAGTCCATACTCAGGCTCTTCAAGATGCTGGAGCTG'.
'AACCTTAAGAATGAATTCATGCCAGGAGCAGTGGCTCACACCTGTAATCCCAGCACTTTG'.
'GGAGGCCGAGGCAGGTGGATCACCTGAGGTCAGGAGTTCAAGACCAACCTGACCAATATG'.
'GTGAAACCCCGTCTCTACTAAAAATACAAAAATTAGGCCGCCTGTAGTCCCAGCTACTTG'.
'GGAGGCTGAGACAGAAGAATCACTTGAACCCAGGAGCTGGAGGTTGCAGTGAGCCAAGAT'.
'GGTGCCAGCGCACTCCAGCCTGAGCGACAGAGCAAGACTCCATCTCAAAAAATAATAATA'.
'ATAATAATAATAATAATAATAATAATAATAATAATAATTCACTGGGCAGGTAAGGGAGAG'.
'GTCTTCCAGACAGAGGGAACAGCTCATACAAAAGCATGGAAACACAAAAAGACATGTTTT'.
'GGGAAGTGAGCTTAGTGGTGGAATCACAAGGAATGTTAACTAGATCCAGCTGGGACTAAA'.
'CATTTTTTTCTTTTTTTTTTTTGAGACGGAGCCTCGCTCTGTCTCCAGGCTGGAGTGCAG'.
'TGGCGCAATCTTGGCTCACTGTAACCTTTGCCTCCCGGGTTCAAGTCAATTCTCCTGCCT'.
'CAGCCTCCTGAGCAGTTGGGACTACAGGCGTGTGCCACCATGCCCAACTAATTTTTGTAT'.
'TTTTAGTAGAGATGGGGTTTCACCACGTTGGCCGGGATGGTTTTGATCTCTTGACCTCGT'.
'GATCCGCCTTGGCCTCCCAATGTGTTGGGATTACAGGCGTGAACCACCGTGCCTGGCCTA'.
'CTAAACACTTTTATGGTTTTTTTTTTTTTTTTGAGATGAAGTCTCGCTCTTGTCCCCCAG'.
'GCTGGAGTGCAATGGCACGATCTCAGCTCATTGCAACCTCCGCCTCCCAGGTTCAAGCAA'.
'TTCTCCTGCCTCAGCCTCCCGAGTAGCTGAGATTACAGGCACCTGCCACCACGCCCGGCT'.
'AATTTTTTGTATTTTTAGTAGAGGCTGGGTTTCACCATGTTGGCCAGGCTGGTCTCGAAC'.
'TCCTGACCTCAGATGATCCACCCGCCTCAACCTCCCAAAATGCTGAGATTACAGGCATGA'.
'GCCACTGTGCCTGGCCAGTTTTATGTATTCTTTAGACTAGTGGTTTCCAAAACTAAAGTT'.
'TTCTCTAAAGCTGTGGACCTTCTCCCCCAGATAATTTTACATAGAATGCAATATATAAAG'.
'CAGTTAAAAGCGGAGTTATTCTCTAACGGAAAAGTACCAAGGGCACTCCAATTTGGCCAG'.
'CTTTTGGGGTTGCACAGAAAAGTTTGAGAACCACTAAAAAGCCTGTTACCTTGAGTATGA'.
'GCTCTAAGCCAATGGCAAATCCTGGCTCTATCACTAAGTTGGAAACTTTGGACAAATTAC'.
'TTAAGCTCTGTGGCTCAGCACCCTCACATGAAACATGAGATTAATAATACTCCCATATCC'.
'ATAGGGTTGCAAGGAATGAACTAGTAAGCCACTTTCCCACAATTCCATGACTATACATTG'.
'ATTAGACCTCTTCTTCCCCTTTAACTCTTTACTCATCCTTTAAACCCATTTCCCTTCTTC'.
'CTGAAGTTTCCCGATATCCTTAGTGTGCGACAGATAACCCTCCTGTTTCCACAGCACCTG'.
'TTACTTTATACTACTATTGCTGTAGCAGTTCCCCTTTTCCTGAGTTGGGGAATGTATCCT'.
'TTCTTTGTCTTTGTCCTATGTAGAAAATTAAAACTGGCAATGCTGTCAATGCAAGTGCTG'.
'GGGCAACTGTAGACAGACATGTCCTGGCCCTTGAGAAATTAGTATCTAGGTAGAAGGCAG'.
'CAGAAAACAAGGGACTGGCTGTCTAGGTGAAAAAAGTGGCAGGAACACAGGCACACAGAT'.
'CTGAGTTGTTAGGCTAGAGTAGTGCTGTCTATCACTGCAAGCAAGCCACAGATGTCATTT'.
'TAAATGTTCTGGTAGCTCTATTAAAAAAAGAAACAGATGAAATTAACTTTAATGCATTTT'.
'ATTTAACCCAACACATATATTTCAACATGTAATCAGTATCAAATATTTTTGACATATTTT'.
'ACATTTTGTGTGCTGTCTTAGAAATCTGCTGTGTATTTTACACTTACATTACATCTCAAT'.
'TGAGACTAGTCATATTTCAAATGAGTCCTATGTGACTAGTGACTTCGGTACTAGTAGTCC'.
'AGGGCTAGAGGAAAATGTTCATACGGAAGAGTAACAGAGGTTCAAGTTGGAGGTAGGGGT'.
'CAAACTAGAGGGGGTCTGAATGCCACTAAAGAAAGTGGAAAGCCTTTGAAGGATTTTGAG'.
'TTGATTGTAAAGTTAATCTAGTGGTTAACACAGGATTAAGAGACCATCCTTAATGCCACT'.
'GTAGCAATCCTTCCTTCATTTCATTGAGGCTGTTCCACTCTGTCACAGCTTATCACTGGT'.
'GGTGCAGACTGCTTTTCCAAGCATGTACTTTTGTACCTTACCAACGGGTCTGGTAGGTAG'.
'TGAGGACTGAGCAATCAGGACAGCAGTATGCAGATGCTTCCCTCTTCAGATGACACACTC'.
'TTAGGCATGGCTGGGCACTAAAAAAGGTCCTTTGACAATGTTGGTGAAAGCTGAGATTCA'.
'GCCAGAGTATCAAACAGTGCGGATTGATGTGCCACAGGTACAATGTCAAGTATGACTCAG'.
'AGGACAAATTATCTAGATCCTTCTAATAATAGCATGTACCCCAACAACTGGATTCCTTAG'.
'TATTCTTCAAAATCTGAGGTAAAATCACTCTCGCTTTAAAAGATACCAACTTCACCCCTT'.
'CCTCTCTTCCCAACTCCCTCCTGCTTCCTTAAGGATCCATGCCAGCTAGCAGGTAAACCA'.
'GAGGCTGACTTGCTGACATCTTCCTTACCTTATTCCTCAGGTATACATCCTAGGCAGGGA'.
'AAATTTACAGAATGCATCCCAGCCTGATTTTGGAAGAATGAGAAAGTTATCTGAGGGCTC'.
'CCAAGGGCCTCCTGTGCATACCATCTTTATCTTCCAACTTAGAACTAACCAAATTCAGTC'.
'TTTTTGTGTAATGAAAAAAGGATAAGCTGGGCACAGTGGCTCACACCTGTAATCCCGGCA'.
'CTTTGGGAGACCGAGGCGGGAGGACTGCTTGAGCCCAGGAACAAGACCAGCCTGGGCAAC'.
'ATAGCGAGACCTTGTCTCTATACAAAAATAAAGAAGAAAAAAGGATGCAGGAAATTAACA'.
'ATAGGATAGCCAACACCCTCACTAAAGCATCAATTTCCATATGATGTTAAGTACCAGGTA'.
'GAAATCTCTCTGACTTTAAGGAGCTTTGGACACAAAAACTTTTCCTTAAACAAGCCATTT'.
'ATTTTCTAAACATGGACTTCCACTAGTTGTGTAACTCTCCTAGAATTCTAGCCAATATTT'.
'AATAATTGTTGCCACACTTTTGTATTTCAACTTAAGTATTTTATATTATTAAAAACTACC'.
'AATTATCTTAACAAACCTGCACATGGAGGGAGAGGTATATGAAACTCAGCCCACTAACTA'.
'GACCAAAATCCTCCTCAATGACACTAAGGTTGTAATACTAAAAAGTCCCAATCACCCTCC'.
'CAGGATTCTATTAAAGCAAGCTGTGGTTAACAGACAAGATGCCTTTTTCGTCATCATTTT'.
'CAAAAGCATTGTCACTTTTTTTCCAAGACACAACTTCTTTGAACCTGTTTCATAACCTAT'.
'CATATAAATACCAGCCTCAATACTGCTATCAAGATTAAACAATGAACAAAAAAGTGTTTT'.
'ATAAGTAAGAGTGGACAATGTGAGTTTTTATTGTTTGGCTCATTAGAAATGTTCTTGGCC'.
'ATCTCATGCAGGAACAGCTGGAGGAAATGGAAGAACGCCAGAGGCAGTTAAGAAATGGGG'.
'TGCAACTCCAGCAACAGAAGAACAAAGAGATGGAACAGCTAAGGCTCAGTCTTGCTGAAG'.
'AGCTCTCTACTTATAAGTCAGTTTCTGCTGCTATACAAATCTCATCTAATACTGGCTGAG'.
'GGGATGGTGGGAGGGCTTAGGGAAAATTTTACCTTAGAATCAAAAACAAAAAGAGGATTT'.
'GGGAAATGATTTTCAAATTGTGCTTATCCAAAAACACATGGAAAATGGCTCTCTCTTTTT'.
'AAAGGGCTATGCTACTACCCAAGAGCCTGGAACAGGCTGATGCTCCCACTTCTCAGGCAG'.
'GTGGAATGGAGACACAGTCTCAAGGTGATCTTTGTGAAGAGAAGAGTGGTGTTTGCATTG'.
'TTACTGCTTTCCTAACAATACTAATTAATGCCTTAAAAACAGGCCGGACGGGGTGGCTCA'.
'CGCCTGTAATCCTAGCACTTTGGGAGGCTGAGGAGGGTGGATCACCTGGAGTCAGGAGTT'.
'CAAGACCAGCCTGGCCAACATGGCAAAACTCCATCTCCACTAAAAATACAAAAATTAGCC'.
'GGGCATAGTGGCAGGCACTTATAATCCCAGCTACTCAGGAGGCCAAGGCAGGAGAATCGC'.
'TTGAACCAGGAGGCAGAGGTTGCAGTGAGTCAAGATCACAATACAGCACTCCAGCTTGTA'.
'CAACAGAGTGAGACTGCCTCAAAACAAAACAAAAACCCAAAAAACAAAAACAACAAAAAA'.
'CCCTTGTGTGCCTAATGACAAGGGGATAACCCAAACCTCCAAAACGCCTGAGTCAGGCAT'.
'TCAGAGTTCATTTGGAATGTTTGTTTCTAGTAGGACTCAAAATATGCCCTGATTATCACC'.
'ATGAATTCTGTGGCATCTAGGCTTTGGGCATCTTGTTTCCTCATCCTACCCTACCCACCT'.
'GCTATTCTCAGTTTTCCTTATAATAGCAGAGAAAGCAGTTGTGCTATCAAAAATAATAAA'.
'CATATCTATCCATTAAGTTCCTTATATAATATTCAAAGGCTGTGGTTTTGGGTGGAAGCA'.
'GAGATGTTCATGTTACACAGACTTACTCTTTTTTTTTTTTTTTTTTTGAGACGGAGTCTT'.
'GCTCTGTTGCCAGGCTGGAGTGCAGTGGCGTGACCTCTGCCTCCCGGGTTCAAGCGATTC'.
'CCCTGCCTCAGCCTCCCAAGTAGCTGGGATTATAGGCACGCACCACCACGCCTGGCTAAT'.
'TTTTTTGTATTTTAGTAGAGACGGGGTTTCACCATGTTGGCTAAGATGGTCTCATCTCCT'.
'GACCTTGTGATCCACTTGCCTCGGCCTCCCAAAGTGCTGGGATTTCAGGTGTGAGCCACC'.
'ATGCTTGGCCTAAACAGACTTAACTTTTAGACACTGACAAAACTGAAGGCATCTTTCTGA'.
'CCAATCACCTACTCAGGATCCCTCCCCCAATGTTTTACCAGTATATTCTGATAAAAGTTC'.
'TAGAGTCCGTGAAAGAAACTAAGGATAAAAGAAAGTCCGTGTCAAGTTGTACATTATACA'.
'GATGCCTATAAATTTTATTCATTTCCTAAGCTTACATCAAATTCACAACTTTCTTTTTTT'.
'TTTGAGACAGAGTCTCGCTCTGCCACCCAGGCTGGAGTGCAGTGGCACGGTCTCAGTTCA'.
'CTGCAACCTCCACCTCCTGGGTTCAAGTGATTTTCCTGCCTCAGCCTCCTGAGTAGCTGG'.
'GACTACAGGAGCATGCCACCACGGCCAGCTAGTTTTTGTATTTTTAGTAGAAACGGGGTT'.
'TCACCATCTTGGCCAGGCTGGTCTTGAACTCCTGACCTTGTGATCCACGTGCCTCAGCCT'.
'CTCAAAGTGCTGGGATTACAGGCGTGAACCACCGCGCCTGGCCCACAAGTAACTATTGTT'.
'GCTTTTTCTAATTTTCTAGGATTTTATTTCATTTTTTTAAATTTCTTTTTAGTAGAGATG'.
'GGGGGTCGGGTCTTGCTATTTTGCCCAGGCTGGAGTAGTGGCACGATCTTGGCTCACTGC'.
'AACTCTGCCTCCTGGGTTCAAACAATACTCCTGCCTCAGCCTGCTAAGTAGCTGGGATTA'.
'CAGGCATAAGCCATCACACCCAGCCTTGAGGATTTTCTTATACTGTGTTTGAATCCACAT'.
'GACTGATAATATGCTTAATGTTTGAGAAATTATAACCTTGCAATTGAGGTTAATGATCTA'.
'CTAACTACCTTTGTGTTGATCAGATTGTGTACAATCTGGAAAAGACAACGACTAATCCAA'.
'AGAAATGAAACTACAGAATTTCAGGCATTGTAATTATACCTGTAAGAAGTTAACCTAGCA'.
'GAGAAAACGTTTAACTATCCCTCCCATCACCATCACCATTCATTCTATTTGACAAACAGG'.
'AGGCATCCAAATATTTGCTAGGGGAAAGTCATCCCTGATCATCCATAAATCACACTGTAA'.
'CAATCTCTTCTCAACAAAGCCTGCAGTAACTAAACCTCAGAAGTTCACTGTTATAAACTT'.
'TTTCTTTCAACTTTACAGGGGCTGTTTAGAAATATATGGCCAAATCTGTAACCCGGAAAC'.
'AGCAAAAAACTTCTTAGCAAAGGATCACTAAGTACCCTTTGGATGTACTCTTCCAACCAG'.
'ACAAGAGTGCCAGAAACTTGGCAAGCAATTCATCCTGTGGAAGTTGCAAATACTGGCTGA'.
'CCTGCTTAAAAAGATTCTAGAGTTGGCCGGAGGCAGAACATGTCAACTCTTTGCTGGATT'.
'CTATTTCATCTGCTGTTGATACTGATCTCAATGCACCAAGGAAAGGAAAGATGAGCCTCC'.
'TGTCTTCCAGCAACAACCCTCACATATGCACTGAGTAAAGGATGAATGTATGGACACATC'.
'TGGGAGTATTTTAAAGAATGTATCTTGCCTTGTGTTGACCCAAACCAAAAACATTTTTGA'.
'GGGGCACATGTGGGGTCAAAAAGATAGCCAATTTCCATTACATGGGTTTACAATTTCCAT'.
'TCTTTTGTGCCACGAGTGTTAGAATTTAAATGAATACTTTTACAAAGTCTACTTTTTGTT'.
'CAAGGATATGCTGACCCATATAGTTTACTCTTAAAATTGTGTCAAGGTATTTCTCACTAT'.
'ACTCTAAAACAACTAGACTTGAAAAGAAACCATTTGAGATTTGAATCTAATGGTTAACGC'.
'TATTCAGATTTTCCCAAAGATCTTACCTCATGAAAGTAGTTCTGGGTCAGAATGATCTAC'.
'TCAGTTAAAAAACAACAACAACAAAAAACTAAGCGATTGGGAAAAAACAGGAATTTTATC'.
'TGGTTATTGCATCTGGTGATAGAGGCCTTCAAAGCCTATTATTTCTAACCTAAGTAAAGG'.
'CCCCAGTGAAAAACATACTGGGGAAATAAAACCTCTGAGAAAAGGTTCAAGCACCTTTTC'.
'CAAATTTAAATCTTGCCTTAAATTCTCTCTACCACACTGCCTTTGACACTCTTGGAAGTC'.
'CATGTAGTTCTCTACAGACAGACTTCAAAGAAACGTTACCTTATCAAAGACTAATCTGTG'.
'CCACCTCTGATTCAGTGTTTTATGTCTTTCACTTTCCCTGGGAAGGAGTAAAGTTCTTTT'.
'CTACAGCTCTGGGACTATTACATTTAATTCTGCTCTTGATAGTCAAAGACATGGACAACA'.
'ACTGTCATCTGAAGGACTCTTCTAGAAGCCAGAGACTGGTGTTTGATGGATGTTTTATAC'.
'TAAATAAAACCCATCAGCATGGGGTTATGTAGAAAAGCAATTTATTCCATTTTAAGCACT'.
'TACACAGTTAGTCATGGAGAGTAACAGGCCTGCTGGTGAAACAGGTCACCCAAAATGGAG'.
'ATGGCATCAAACTAGTGGTCAAGGACTAACTCCTAAAAAAAAAAAGCAACTCTTATCAAG'.
'GATTAATTTAATTTTTAAAACAAATACAAGTTATTGATTCACTCTTCTCAACTTGACAGT'.
'CTACCTGTGGTATAACTGTCAGGTAAAAACATACATCTTTACAACTTGGTGGTCCCAAGT'.
'TAAAAAAAAAAAAAAAAAAAACCAACAAAAAAAAAAAAAACACCATTTCACAGACAGGAA'.
'ATAAACAACATGAAAACAGCTCAAGAAATACACTAACGAGCAAAAATATATGAATATATG'.
'GGGAAAGAGGAACGTGTTGTTTTGACTTAACTGAAGAAACCAAGAGGAAACTGGTCTACG'.
'TATGAAAATGTGCATCCTGGAAAGTCAGGTGTCAAGATTTTCGAGTAGGAATCTATATGA'.
'CTTGAATCTCCCCCTATTTCCTGAATAAAAGTGACATCTTTCAGTATTTATACTTCATGG'.
'CTCAGACACCTACCTCATTTGGCTCTATTCCTTACTCACTCTAGCCTTTACTTAAATGAG'.
'TCTGAAAAACTTGGGGATATAGCATAAGAAGAAAAATAATCACACATAATATTCCCCTTT'.
'CTGTAGCTACTTTAGACCTGGGTTACTAGAAAATTCCTGAAGAAAATTTCAACGTTAAGT'.
'CTGTGGCTTTGTTGAATCAAGCCCCCCTATTAATATTTAGAAAACACCCACGGTTTGGGC'.
'TAATAGCATTATCGGTGGTACCTATTATATAGAGGGATAGCTGAATAAAGTCTGTCTCAA'.
'AACCAGTGTTAAATCACTCTCAGGGTTGAGAAGAAAAAAGGGGAGTCTAAAATCACAACA'.
'AGTAAAGACATATCTAGGACCCTTGTCCTTCTGGATCCACGCTTCCTTCAGGGTCTTCAT'.
'CATTATAAATGTTCTCTGCCTGCCCAAAAACAAGAAAAAGAATTTAAACATGAAGACTTC'.
'TTCTAAAACTCAAGGTTTCAACAACAGATTAGGCCAGGAAGCCAGAGAGTAAATACTTTA'.
'TAGCTTTTGGGCCACACAATCTGTGTTACAACTATTCAACTCTTGGATGAAAGTATCCGG'.
'AGACAACCTATAATGGGTAATGAAATATTAATTAGCATGATCATGTTCCAATAAAAATAA'.
'GCAGCTGATCCCCAGACGCCTGATTAGGACATTCCCACAAAACTGCAGTGTGGATACTAT'.
'TTGTCTTGATAGCCAACATTCTTGAGTTCTTTAACCAGGCATTATTATTTTTCTTTCCTT'.
'TTGAGATGGAGCCTTGCTCTGTCTCCCAGGCTGGAGTGCAGTGGCACCATCTCGGCTCAC'.
'TGCAACCTATGCCTCCCAGATTCAAGCAATTCTCCTGCCTCAGCCTCCAGAGTAGCTAGG'.
'ATTACAGGCACATGCCACTACGCCTGGCTAATTTTTGTATTTTTAATAGAGATGGGGTTT'.
'CACCATGTTGGCCAGGCTGGTCTCGAACTCCTGATCTCAGGTGATCTGCCCACCTCGGCC'.
'TCTCAAAGTGCTAGGATTATAGGAGTAAGCCACTGTGCCCAGCCTAACCAGACATTATTA'.
'ATAATAGCCAAAAAGTAAAAACAACCCAAATATCCATCAACTACTAAAATGGATACACGG'.
'TATATCCAATCCATATGATGGAATATTATTTGGCATAAAAAAGCCAGTCAGGCCAGGTGT'.
'GGTGGCTCATACCTGTAATCCCAGCACTTGGGAGGCTGAGGCAGACAGATCACTTGAGGT'.
'CATGAGTTTGAGACTAGCCTGACCAACAAGGCGAAACTGCATCTCTACTACAAATACAAA'.
'AATCAGCCATGTGTGGGGGTGCACCCCTGTGGTCCCAGCTACTTGGGAGGCTGAGGCATA'.
'AGAATTGATTGAACCTGGGAGGTGGTGGTTGTAGTGAGCCAAGATTGCACCACTGCACTC'.
'CAGCCTGGGTGGCAAAGCAAGACTGTGTGCCAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'.
'AAGCTGTCACATACTTTAGGATTTTATTTATATAAGGTGTCCAGGCCAGGTGTGGTGGCA'.
'CACGCCTGTAATCCCAGCATTTTGGGAGGCCAAGGCAGGCGTATCACCTGAGGTCAGGAG'.
'TTCGAGACCAGCCTGGCCAACATGGTGAAACGCTGTCTCTACTAAAAATATAAAAATTAG'.
'CCAGGCGTGGTGACAGGCGCCTGTAATCCCAGCTATTTGGGAGGCTAAGGCAGGAGAATC'.
'GCTTGAACCCAGGAGGCGGAGGTTTCAGTGAGCCGAGATCACACCACTGCACTCCAGCCT'.
'GGGGGGCAAGACTTCGTCTAAAAAAAACAGGGGTCCAAAACAGGCAAATCCATAGCTTGG'.
'TGGCTGCCTAGGGCTGGGGGACTATGAGAAAAATAGGAAATGATGGCTAATGGGTACAGG'.
'GTTTCTTTTTCAGATGATGAAAATGTTCTCAAATTGACTGTGGTTGATGGTTGCACAACT'.
'GTAAATACACTGAAGACTGCTGAACTGCACACTTAAAACTTCCAAAACAATATGTTCCGA'.
'ATCTCTATATATTGAAGAGAAAAACTGTTCTTGTATAGAATAAACTCTACTTCTACTGCT'.
'TGACAGAATACCTGTATCCAACGGCATAATCTTAAAATACAGGAACCACTTTCACAGGAG'.
'CAAAATTTACTGCTCTTAGCACCTACCATGCACATATCACTATGATAGGTACTGCAGAGG'.
'ACAGGATAGTCTTACCTTCAAAGAGCTTGTGATCTGACCCCAGAGAAAAGAATACATACA'.
'ATTGTGTGATGCTTTCTGACGTTACTTCTAACACCAAATGTGGGGTACCCTTTCTTAGGA'.
'CACCAACTGGGTGTACAACAACTCAATCCTATTCTGACACTATCTGAAGTTAGCTTTGGA'.
'GAAGACTGTCCTTACTTCAGAAGCCAGTTGCAATTCCCTGGTCCCAGGCTACCTGCACAC'.
'TTCTATCCCACTTGACTACAAATTTCAGGGTTCCCACTACTGCCTCCTCAGGTCTGATAA'.
'TTTGATGGAATGACTCACAGAACCCAAGAAAGCTTTTTACTATTACTGTTTTTTGTTTGT'.
'TTTTTGTTTTGTTTTTTTTTTTTAAATAAAGGATACAACTGAGGAACCACATGGAAGAGA'.
'TGCATACGGCAAGGTGGGGAGGGGCTGCAGAGTTTCCATCAAGTCTCTGGGCATGCTACC'.
'CACCCAGTATGTCGAGTTGTTCACCAATCCAGAAGCACATCAAATTAGGAGTTTTTATAG'.
'AGTTCAATCTCTGGCCCTGCAACCCCAAGGTTGGCAAGTGGGCTGACAAGTTTTAACCCT'.
'CAAATCAAGTGATTGGCCTTTCTGACTAAACCAACTATGAGGCTATCTAGGGGCCCCACC'.
'AAAATCACCTCACAGTAGAACAAACTCAGGTGTGGTCCAAAGTGGATCACTAGGAACGAC'.
'AAAGACACTCCTAGCACTCTGCAAACTCCGAGTGTTTTTGGAGAGCTCTGTGCCAAGAAC'.
'TGGGACAAAGACCAAATATTTACTTACTCTATTACAATGCTAAAAACACCAAATAAAGTA'.
'ACAACTTGGAATGGAGGTGATGGCCTTGCAGGGATCTAGTTTAACCTTGAATTCTTCAGT'.
'ATTTTTTTTTTGAGACAGGGTCTCGCTCTGTCACCCAGGCTGGAGTGCAGTGGCGCCATC'.
'TTAGCTCACTGCAACCTCTGCCTCCTGGGATCACGCTAGCCTCCCACTTCAGCCTCCCAA'.
'GGAACTGGGACTACAGGTACGTGCCATCACGCCCAGCTATTAAGTTTCTGTATTAATATT'.
'GAAGGGATTTATTACAAAGAGAGTGAGGTGAATTTTCTGTTTTCAAGTTACACATCTTTT'.
'TTGTAAAAAAATTATAATACAGAAAGGTCTAAAGAAACCAAGAACTAGGTACCAAGCACA'.
'TTTTAGCAAACAGCTTTTTTCTTTTTTTTTTTTTTTGAGATGGAGTTTTGCTCTTGTTGC'.
'CCATGTTCGAGTGCAATGGTGCGATCTTGGCTCACCGCAACTCCTCCGCCTCCTGGGTTC'.
'AAACAAGTCTCCTGCCTCAGCCTCCCAAGTAGCTGGGATTACAGGCGCCCGTCACCATGC'.
'CTGGCTAATTTTTGTATTTATTTTTTAGTAGAGATGGGGTTTCACTATGTTGACCAGGCT'.
'GGTCTCAAACTACTGACCTCAGGTGATCTGCCCACCTCGGCCTCCCAAAGTGTTGGAATT'.
'ACAGGCGTGAGCCACCACACCTGGCCAGTAATCAGCTTTCTAAATATAGACTAGATACAC'.
'AAAATTTTAATATGAGGAATACCATTATGCTATTCTTCAGTCTGCGCTTCCCCTTTAACA'.
'GCATGTCATGAATATCTTATAACCCTAACCGTACTTCTTTCTTTTCTTCCTTTAGAGACA'.
'GGGTCTCGCTATGTCATCTAGGCTGGAGTGCAGTGGTGTGATCACAGCCCACTGTAGCCT'.
'CAAACTCCTGGCCTCAAGGGATCCTTCTGTCACGGCCTCCCAAAGAGCAGGGACTAAAGG'.
'CACATGCCACCATGTCTCACAGCAGCCTCTACCCGCTGGATTCAAGGTATCCTCCTGCCT'.
'CGGCCTCCCAAGTAGCTGGGATCACAGGCACGTACCACCAAGCCTGGCTAATTTTTTTTT'.
'GGTAGAGACACGGTCTCACTTTATTGCCCAGGCTAGTCTAGAACTTCTGGGCTCAAGTGA'.
'TCCTCCGGCTTTGGCCTCCCAAAGTATTTGGATTACAGGTGTGAGCCACTGAGCACAGCC'.
'CCTAATCATACTTTTTAAATTTATTTTTATTATTTTTTTTGAGACAGAGTCTCGCCCTGT'.
'CACCCAGGCTAGAGTGCAGTGGCACGATCTCGGCTCACTGCAAGTCCTGCCTCCCGGGTT'.
'CACGCCATTCTCCTGCCTCAGCCTCCCGAGTAGCTGGGACTACAGGCGCCCGCCACCACG'.
'CCCGGCTAATTTTTTGTATTTTTAGTAGAGTCGGGGTTTCACCATGTTAGCCAGGATGGT'.
'CTCAATCTCCTGATCTTGTGATCCACCCGCCTCGGCCTCCCAAAGTGCTGGGAGTACAGG'.
'CGTGAGCCACCGCACCTGGCCCATCCTTCTTTTTGATAAGTAATATTACAAAGTATGAAT'.
'GTTGTGATGGTATTTGGAGGTAAAAGAAAAAAAAAGTATGGATGTAGTACAATCTGTTAG'.
'TCTGGCAGGTCACAAACTTATTTTATTTCTGTCTTCAATTAATAGTGCTATTACGCCAGG'.
'CGCGGTGGCTCACGCCTGTAATTCCAGCACTTTGGGAGGCCGAGGCAGGCAGATCACCTG'.
'AGGTCAGGAGTTCGAGGCCAGCCTGACCAACATGGAGAAACCCAGTCTCTACTAAAAAAA'.
'ATTACAAAAATTTAGCCAGGCGTGGTGGCGCATGCCTGTAATCTCAGCTACTCGGGAGGC'.
'TGAGGCAGGAGAATCGCTTGAACCCAGGAGGCGGAGGTTGCAGAGAGCCAAGATCGCACC'.
'ATTGCACTCCAGGCTGGAAAACAAGAACAAAACTCCGTCTCAAAAATAAAAATGCCGGGC'.
'ACGGTGGCTCACGTCTGTAATTCCAGTACTTTGGGAGGCCAAAGAGGGCGGATCATGAGG'.
'TCAGGAGATCGAGACCACCCTGACCAACATGGTGAAACCCCGTCTCTACTAAATAAAAAA'.
'CAACAACAAAAAAACTAGCCGGGCATGGTGGTGCATGCCTGTAATCCTAGCTAATCAGCA'.
'GGCCGAGGCAGGAGAATTGCTTGAACCTGGGAGGCAGAGGTTGCAGTGAGCTGAGATCTC'.
'ACCACTGAACTCCAGCCTGGGCAACAAGAGCGAAACTCCATCTCAAAAAAAGAATGAACC'.
'AACATTTATTTTGTCATAAATGCATATCCAGGTCTCCACTGTACAAAACATTTTTCTAGG'.
'TGCTTCCATCTGGAAAATGTTACCCATTTGTCATACCGGCAATTTTACAAATAAAACATT'.
'TATTCTACTTTTTATTAATGAGGAAATTAGTGACAACTAAGACTATCTGGCTATAAGAGG'.
'CAGACTTGGGACTTCAGACTCTAGTCAATGTATTTACACAAGATTCTTTTTTTTTTGAGA'.
'CAGAGTCTCACTCGGTTGCCAGGCTGGAGAAAATGGCGTGATCTTGGCTCACTGCAGCCT'.
'CCACGTTCTGCCTTTAAATGATNTNCCTAGTTAACTACAATAGCGGGCAAAAT';

return $seq;
}
