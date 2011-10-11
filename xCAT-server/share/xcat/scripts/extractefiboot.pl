#!/usr/bin/env perl
#This is a utility to scrape out the EFI boot image from an el torito enabled disk
use strict;
use Fcntl qw/SEEK_SET/;
my $iso;
my $outfile;
GetOptions("out=s" => \$outfile,
	   "iso=s" => \$iso);
my $emul;
my $blksize=2048;
my $istream;
use Getopt::Long;
sub grabimage {
	my $bootcat = shift;
	my $image;
	my @recdata = unpack("C2vC2vV",$bootcat);
	unless ($recdata[0] == 0x88) { printf "Error: EFI torito record not bootable\n"; exit; }
	$emul=$recdata[1];
	#for now, ignore load segment, system type
	seek($istream,$recdata[6]*$blksize,SEEK_SET);
	my $size=$recdata[5];
	if ($size==0) { $size = 1; } #if 0/1, it's auto-detect time
	my $readbytes=read($istream,$image,$size*512);
	if ($size == 1) { #we have to interpret the FAT header to get the real size
		seek($istream,$recdata[6]*$blksize,SEEK_SET); # go back to beginning
		my @fatheader = unpack("C11vCvC3vC11V",$image);
		my $secsize=$fatheader[11];
		if ($fatheader[17]) {
			$size=$secsize*($fatheader[17]);
		} else {
			die "Unsupported FAT header, requires test of commented code segment";
		}
#		} elsif ($fatheader[-1]) {
#			$size=$secsize*$fatheader[-1];
#		}
		$readbytes=read($istream,$image,$size);
	}
	my $outh;
	open($outh,">",$outfile);
	print $outh $image;
	close($outh);
}
if (! -r $iso) { 
	printf "Error, $iso does not seem to exist or is not readable";
	exit 1;
}
open($istream,"<",$iso) || die "Error opening $iso";
my $bootsect;
seek($istream,17*$blksize,SEEK_SET);
my $readbytes = read($istream,$bootsect,0x4b);
unless ($readbytes == 0x4b) {
	printf "Error reading boot record volume from $iso\n";
	exit 1;
}
my @recdata;
@recdata = unpack("CA5CA32C32V",$bootsect); #it would have been nice if the el torito actually said little endian on it..
unless ($recdata[0] == 0 and $recdata[1] eq 'CD001'
	and $recdata[2] == 1 and $recdata[3] eq "EL TORITO SPECIFICATION") { 
	printf "Error: Boot record volume format invalid\n";
	exit 1;
}
my $bootcatidx=$recdata[-1];
my $bootcat;
seek($istream,$bootcatidx*$blksize,SEEK_SET);
$readbytes = read($istream,$bootcat,0x20);
unless ($readbytes == 0x20) { printf "Error reading boot catalog at $bootcatidx\n"; exit 1; }
@recdata = unpack("C*",$bootcat);
unless ($recdata[0] == 1 and $recdata[0x1e] == 0x55 and $recdata[0x1f] == 0xaa) {
	printf "Boot catalog has invalid header\n"; exit 1; 
}
$readbytes = read($istream,$bootcat,0x20);
my $image;
unless ($readbytes == 0x20) { printf "Error reading default El torito record\n"; exit; }
if ($recdata[1] == 0xef) { #wow, the efi record came first, actually interpret that first record
	grabimage($bootcat);
} else { # keep looking for an *EFI* record
	#read in first header
	read($istream,$bootcat,0x20);
	@recdata = unpack("CCv",$bootcat);
	while ($recdata[0] == 0x90 and $recdata[1] != 0xef) { 	
		my $additionalrecords=$recdata[2];
		while ($additionalrecords) {
		 	read($istream,$bootcat,0x20); #throw away irrelevant sectors
			$additionalrecords -= 1;
		}
		read($istream,$bootcat,0x20); #throw away irrelevant sectors
		@recdata = unpack("CCv",$bootcat);
	}
	if ($recdata[1] != 0xef) {
		printf "No EFI boot image found\n";
		exit 1;
	}
	$readbytes=read($istream,$bootcat,0x20);
	grabimage($bootcat);
}
	
