use Statistics::R;
use File::Find;

use strict;
use warnings;

use lib './lib';

use ScanBatch::Stats;

my $data_dir = (defined($ARGV[0]) && (-e $ARGV[0] or die "$ARGV[0] not found")) ? $ARGV[0] : '.';
my $out_dir = (defined($ARGV[1]) && (-e $ARGV[1] or die "$ARGV[1] not found")) ? $ARGV[1] : '.';

print "LOOKING IN $data_dir\n";
print "SAVING IN $out_dir\n";

my $s = ScanBatch::Stats->new(
  'data_dir' => $data_dir,
  'out_dir' => $out_dir,
  'data_threshhold' => $ARGV[2] || 0,
  'format' => $ARGV[3] || 'png'
  );

$s->dump();

$s->process();
